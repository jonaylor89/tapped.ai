mod agent;
mod models;
mod utils;
mod templates;

use agent::Agent;
use clap::Parser;
use color_eyre::Result;
use log::{error, info, warn};
use models::*;
use std::{collections::HashMap, path::Path};
use tokio::time::{sleep, Duration};
use utils::*;

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Input file path (CSV or JSON)
    #[arg(short, long)]
    input: String,

    /// Output file path for enriched venues
    #[arg(short, long, default_value = "output/venues.json")]
    output: String,

    /// Configuration file path
    #[arg(short, long, default_value = "config.toml")]
    config: String,

    /// Maximum concurrent venues (deprecated - processing is now serial)
    #[arg(long, default_value = "1")]
    max_concurrent: usize,

    /// Exa API key (can also be set via EXA_API_KEY environment variable)
    #[arg(long)]
    exa_api_key: Option<String>,

    /// LLM API key (can also be set via LLM_API_KEY or OPENAI_API_KEY environment variable)
    #[arg(long)]
    llm_api_key: Option<String>,

    /// LLM API base URL
    #[arg(long, default_value = "https://api.openai.com/v1")]
    llm_base_url: String,

    /// LLM model to use
    #[arg(long, default_value = "gpt-3.5-turbo")]
    llm_model: String,

    /// Verbose logging
    #[arg(short, long)]
    verbose: bool,

    /// Dry run mode (don't make actual API calls)
    #[arg(long)]
    dry_run: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    color_eyre::install()?;
    dotenv::dotenv().ok();
    let args = Args::parse();
    env_logger::Builder::from_default_env()
        .filter_level(if args.verbose {
            log::LevelFilter::Debug
        } else {
            log::LevelFilter::Info
        })
        .init();

    info!("Starting venue enrichment pipeline");
    info!("Input: {}", args.input);
    info!("Output: {}", args.output);
    info!("Config: {}", args.config);

    let config = if Path::new(&args.config).exists() {
        info!("Loading configuration from: {}", args.config);
        Config::load_from_file(&args.config)?
    } else {
        warn!("Config file not found, using defaults");
        Config::default_config()
    };

    let venue_inputs = load_venue_inputs(&args.input).await?;
    info!("Loaded {} venue inputs", venue_inputs.len());

    if venue_inputs.is_empty() {
        warn!("No venue inputs found. Exiting.");
        return Ok(());
    }

    let exa_api_key = args
        .exa_api_key
        .or_else(|| std::env::var("EXA_API_KEY").ok())
        .ok_or_else(|| {
            error!(
                "Exa API key not provided. Set --exa-api-key or EXA_API_KEY environment variable"
            );
            color_eyre::Report::msg("Exa API key not provided")
        })?;

    let llm_api_key = args.llm_api_key
        .or_else(|| std::env::var("LLM_API_KEY").ok())
        .or_else(|| std::env::var("OPENAI_API_KEY").ok())
        .ok_or_else(|| {
            error!("LLM API key not provided. Set --llm-api-key or LLM_API_KEY/OPENAI_API_KEY environment variable");
            color_eyre::Report::msg("LLM API key not provided")
        })?;

    let agent = Agent::new(
        exa_api_key,
        llm_api_key,
        args.llm_base_url.clone(),
        args.llm_model.clone(),
    )?;

    let web_scraper = WebScraper::new(
        config.scraping.clone(),
        None, // No proxy for now
    )?;

    let data_extractor = DataExtractor::new();

    let enriched_venues = process_venues_serially(
        venue_inputs,
        agent,
        web_scraper,
        data_extractor,
        config,
        args.dry_run,
    )
    .await?;

    save_venues_to_json(&enriched_venues, &args.output).await?;

    let complete_venues = enriched_venues.iter().filter(|v| v.is_complete()).count();
    let total_fields_extracted: usize = enriched_venues
        .iter()
        .map(|v| 9 - v.missing_fields().len()) // Total 9 optional fields
        .sum();

    info!("=== ENRICHMENT SUMMARY ===");
    info!("Total venues processed: {}", enriched_venues.len());
    info!("Complete venues (with description): {}", complete_venues);
    info!("Total fields extracted: {}", total_fields_extracted);
    info!(
        "Average fields per venue: {:.1}",
        total_fields_extracted as f64 / enriched_venues.len() as f64
    );
    info!("Results saved to: {}", args.output);

    Ok(())
}

async fn load_venue_inputs(file_path: &str) -> Result<Vec<VenueInput>> {
    let path = Path::new(file_path);
    match path.extension().and_then(|s| s.to_str()) {
        Some("csv") => load_venue_inputs_from_csv(file_path).await,
        Some("json") => load_venue_inputs_from_json(file_path).await,
        _ => Err(color_eyre::Report::msg(
            "Unsupported file format. Use .csv or .json files",
        )),
    }
}

async fn process_venues_serially(
    venue_inputs: Vec<VenueInput>,
    agent: Agent,
    web_scraper: WebScraper,
    data_extractor: DataExtractor,
    config: Config,
    dry_run: bool,
) -> Result<Vec<Venue>> {
    let total_venues = venue_inputs.len();
    let mut enriched_venues = Vec::new();

    for (index, venue_input) in venue_inputs.into_iter().enumerate() {
        info!(
            "Processing venue {}/{}: {}",
            index + 1,
            total_venues,
            venue_input.name
        );

        match process_single_venue(
            venue_input,
            &agent,
            &web_scraper,
            &data_extractor,
            &config.blocklist.domains,
            dry_run,
        )
        .await
        {
            Ok(venue) => {
                info!(
                    "Completed venue: {} (extracted {} fields)",
                    venue.name,
                    9 - venue.missing_fields().len()
                );
                enriched_venues.push(venue);
            }
            Err(e) => {
                error!("✗ Failed to process venue: {}", e);
            }
        }

        // Add a small delay between venues to be respectful to APIs
        if index < total_venues - 1 {
            sleep(Duration::from_millis(1000)).await;
        }
    }

    info!(
        "Successfully processed {}/{} venues",
        enriched_venues.len(),
        total_venues
    );
    Ok(enriched_venues)
}

async fn process_single_venue(
    venue_input: VenueInput,
    agent: &Agent,
    web_scraper: &WebScraper,
    data_extractor: &DataExtractor,
    blocklist: &[String],
    dry_run: bool,
) -> Result<Venue> {
    let mut venue = Venue::new(venue_input.name.clone());

    if dry_run {
        info!("[DRY RUN] Would process venue: {}", venue_input.name);
        venue.set_field_with_source(
            "description",
            "Mock description".to_string(),
            "dry_run".to_string(),
        );
        return Ok(venue);
    }

    // Step 1: Search for venue information using Exa
    let search_results = match agent.search_venues(&venue_input).await {
        Ok(results) => results,
        Err(e) => {
            error!("Failed to search for venue '{}': {}", venue_input.name, e);
            // Check if it's an API key issue
            if e.to_string().contains("Authentication") || e.to_string().contains("401") {
                error!(
                    "💡 Tip: Check your EXA_API_KEY environment variable or --exa-api-key argument"
                );
            }
            return Err(e.wrap_err(format!(
                "Failed to search for venue information for '{}'",
                venue_input.name
            )));
        }
    };

    if search_results.is_empty() {
        warn!(
            "⚠ No search results found for venue: '{}' - skipping enrichment",
            venue_input.name
        );
        return Ok(venue);
    }

    // Step 2: Rank and filter sources using AI
    let ranked_sources = match agent
        .rank_sources(&venue_input.name, &search_results, blocklist)
        .await
    {
        Ok(sources) => sources,
        Err(e) => {
            error!(
                "Failed to rank sources for venue '{}': {}",
                venue_input.name, e
            );
            // Check if it's an LLM API issue
            if e.to_string().contains("Authentication") || e.to_string().contains("401") {
                error!(
                    "💡 Tip: Check your OPENAI_API_KEY environment variable or --llm-api-key argument"
                );
            }
            return Err(e.wrap_err(format!(
                "Failed to rank sources for venue '{}'",
                venue_input.name
            )));
        }
    };

    if ranked_sources.is_empty() {
        warn!(
            "⚠ All sources were filtered out for venue: '{}' (likely blocked by blocklist)",
            venue_input.name
        );
        return Ok(venue);
    }

    // Step 3: Determine which sources to scrape based on missing fields
    let missing_fields = venue.missing_fields();
    let selected_sources = agent
        .determine_best_sources(&venue_input.name, &ranked_sources, &missing_fields)
        .await
        .map_err(|e| {
            error!(
                "Failed to select best sources for venue '{}': {}",
                venue_input.name, e
            );
            e.wrap_err("Failed to select best sources")
        })?;

    // Step 4: Scrape selected sources and extract data
    for source_url in selected_sources.iter().take(3) {
        // Limit to top 3 sources
        match scrape_and_extract_data(
            &venue_input.name,
            source_url,
            agent,
            web_scraper,
            data_extractor,
            &venue.missing_fields(),
        )
        .await
        {
            Ok(extracted_data) => {
                // Apply extracted data to venue
                for (field, value) in extracted_data {
                    if !value.trim().is_empty() {
                        venue.set_field_with_source(field.as_str(), value, source_url.clone());
                    }
                }
            }
            Err(e) => {
                warn!("Failed to extract data from {}: {}", source_url, e);
            }
        }

        // Add delay between scraping different sources
        sleep(Duration::from_millis(500)).await;
    }

    // Step 5: Validate the enriched venue data
    if let Err(e) = venue.validate() {
        warn!("Venue validation failed for {}: {}", venue.name, e);
    }

    Ok(venue)
}

async fn scrape_and_extract_data(
    venue_name: &str,
    source_url: &str,
    agent: &Agent,
    web_scraper: &WebScraper,
    data_extractor: &DataExtractor,
    missing_fields: &[String],
) -> Result<HashMap<String, String>> {
    let html_content = web_scraper.scrape_url(source_url).await.map_err(|e| {
        error!("Failed to scrape {}: {}", source_url, e);
        e.wrap_err(format!("Failed to scrape {}", source_url))
    })?;

    if html_content.trim().is_empty() {
        return Err(color_eyre::Report::msg(format!(
            "Empty content from {}",
            source_url
        )));
    }

    let mut extracted_data = data_extractor.extract_basic_data(&html_content);
    let still_missing: Vec<String> = missing_fields
        .iter()
        .filter(|field| !extracted_data.contains_key(*field))
        .cloned()
        .collect();

    if !still_missing.is_empty() {
        match agent
            .generate_scraping_instructions(
                venue_name,
                &still_missing,
                source_url,
                Some(&html_content[..std::cmp::min(1000, html_content.len())]),
            )
            .await
        {
            Ok(instructions) => {
                let ai_extracted = data_extractor
                    .extract_with_instructions(&html_content, &instructions)
                    .unwrap_or_default();
                extracted_data.extend(ai_extracted);
            }
            Err(e) => {
                warn!("Failed to generate scraping instructions: {}", e);
            }
        }
    }

    // If basic extraction failed, try AI-powered structured extraction
    if extracted_data.is_empty() || (!still_missing.is_empty() && still_missing.len() > 2) {
        match agent
            .extract_structured_data(venue_name, source_url, &html_content, &still_missing)
            .await
        {
            Ok(ai_extracted) => {
                // AI extraction can override heuristic extraction if more comprehensive
                if ai_extracted.len() > extracted_data.len() {
                    extracted_data = ai_extracted;
                } else {
                    extracted_data.extend(ai_extracted);
                }
            }
            Err(e) => {
                warn!("AI-powered extraction failed for {}: {}", source_url, e);
            }
        }
    }

    extracted_data.retain(|field, value| {
        let cleaned_value = value.trim();
        if cleaned_value.is_empty() {
            return false;
        }

        match field.as_str() {
            "email" => cleaned_value.contains('@') && cleaned_value.len() > 5,
            "phone" => cleaned_value.chars().filter(|c| c.is_ascii_digit()).count() >= 10,
            "website" | "facebook_url" | "twitter_url" | "instagram_url" | "logo_url" => {
                validate_url(cleaned_value)
            }
            _ => true,
        }
    });
    for (field, value) in extracted_data.iter_mut() {
        if field.ends_with("_url") || field == "website" {
            match normalize_url(value, Some(source_url)) {
                Ok(normalized) => *value = normalized,
                Err(e) => {
                    warn!("Failed to normalize URL {}: {}", value, e);
                }
            }
        }
    }

    info!(
        "Extracted {} fields from {}: {:?}",
        extracted_data.len(),
        source_url,
        extracted_data.keys().collect::<Vec<_>>()
    );

    Ok(extracted_data)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_load_venue_inputs() {
        // This would require actual test files
        // For now, just test the function exists and handles errors properly
        let result = load_venue_inputs("nonexistent.csv").await;
        assert!(result.is_err());
    }

    #[test]
    fn test_venue_creation() {
        let venue = Venue::new("Test Venue".to_string());
        assert_eq!(venue.name, "Test Venue");
        assert!(!venue.is_complete());
    }
}
