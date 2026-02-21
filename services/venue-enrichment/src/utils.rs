use crate::models::*;
use color_eyre::{Result, eyre::WrapErr};
use log::error;
use rand::prelude::*;
use regex::Regex;
use reqwest::{Client, Proxy};
use scraper::{Html, Selector};
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, fs, path::Path, time::Duration};
use url::Url;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub blocklist: Blocklist,
    pub scraping: ScrapingConfig,
    pub agent: AgentConfig,
    pub rate_limiting: RateLimitConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Blocklist {
    pub domains: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScrapingConfig {
    pub max_depth: u32,
    pub max_pages_per_site: u32,
    pub timeout_seconds: u64,
    pub user_agents: Vec<String>,
    pub respect_robots_txt: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentConfig {
    pub retry_attempts: u32,
    pub retry_delay_seconds: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RateLimitConfig {
    pub requests_per_second: f64,
    pub burst_size: u32,
    pub delay_between_requests_ms: u64,
}

#[derive(Debug, Clone)]
pub struct ProxyConfig {
    pub http_proxy: Option<String>,
    pub https_proxy: Option<String>,
}

pub struct WebScraper {
    client: Client,
    config: ScrapingConfig,
}

pub struct DataExtractor {
    email_regex: Regex,
    phone_regex: Regex,
    social_media_patterns: HashMap<String, Regex>,
}

impl Config {
    pub fn load_from_file<P: AsRef<Path>>(path: P) -> Result<Self> {
        let content = fs::read_to_string(path.as_ref()).map_err(|e| {
            error!("Failed to read config file: {:?}", path.as_ref());
            color_eyre::Report::new(e).wrap_err("Failed to read config file")
        })?;

        let config: Config = toml::from_str(&content).map_err(|e| {
            error!("Failed to parse config file as TOML: {:?}", path.as_ref());
            color_eyre::Report::new(e).wrap_err("Failed to parse config file as TOML")
        })?;

        Ok(config)
    }

    pub fn default_config() -> Self {
        Config {
            blocklist: Blocklist {
                domains: vec![
                    "facebook.com".to_string(),
                    "instagram.com".to_string(),
                    "linkedin.com".to_string(),
                    "pinterest.com".to_string(),
                    "reddit.com".to_string(),
                    "youtube.com".to_string(),
                ],
            },
            scraping: ScrapingConfig {
                max_depth: 2,
                max_pages_per_site: 5,
                timeout_seconds: 30,
                user_agents: vec![
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
                        .to_string(),
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36".to_string(),
                    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36".to_string(),
                ],
                respect_robots_txt: true,
            },
            agent: AgentConfig {
                retry_attempts: 3,
                retry_delay_seconds: 2,
            },
            rate_limiting: RateLimitConfig {
                requests_per_second: 2.0,
                burst_size: 5,
                delay_between_requests_ms: 500,
            },
        }
    }
}

impl WebScraper {
    pub fn new(config: ScrapingConfig, proxy_config: Option<ProxyConfig>) -> Result<Self> {
        let mut client_builder = Client::builder()
            .timeout(Duration::from_secs(config.timeout_seconds))
            .user_agent(&config.user_agents[0]);

        if let Some(proxy) = proxy_config {
            if let Some(http_proxy) = proxy.http_proxy {
                client_builder = client_builder.proxy(Proxy::http(http_proxy)?);
            }
            if let Some(https_proxy) = proxy.https_proxy {
                client_builder = client_builder.proxy(Proxy::https(https_proxy)?);
            }
        }

        let client = client_builder.build()?;

        Ok(WebScraper { client, config })
    }

    pub async fn scrape_url(&self, url: &str) -> Result<String> {
        self.apply_rate_limiting().await;

        log::info!("Scraping and extracting data from {}", url);

        let user_agent = self
            .config
            .user_agents
            .choose(&mut rand::rng())
            .unwrap_or(&self.config.user_agents[0]);

        let response = self
            .client
            .get(url)
            .header("User-Agent", user_agent)
            .header(
                "Accept",
                "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            )
            .header("Accept-Language", "en-US,en;q=0.5")
            .header("Accept-Encoding", "gzip, deflate")
            .header("DNT", "1")
            .header("Connection", "keep-alive")
            .send()
            .await
            .wrap_err(format!("Failed to fetch URL: {}", url))?;

        if !response.status().is_success() {
            return Err(color_eyre::Report::msg(format!(
                "HTTP request failed with status: {}",
                response.status()
            )));
        }

        let content = response
            .text()
            .await
            .context("Failed to read response body")?;

        log::info!("Successfully scraped {} bytes from {}", content.len(), url);
        Ok(content)
    }

    async fn apply_rate_limiting(&self) {
        // let now = std::time::Instant::now();
        // let last_request = self.last_request_time.lock().unwrap();

        // let min_interval = Duration::from_millis(self.rate_limit_config.delay_between_requests_ms);
        // let elapsed = now.duration_since(*last_request);

        // if elapsed < min_interval {
        //     let sleep_duration = min_interval - elapsed;
        //     drop(last_request); // Release lock before sleeping
        //     sleep(sleep_duration).await;
        // }

        // *self.last_request_time.lock().unwrap() = std::time::Instant::now();
    }
}

impl DataExtractor {
    pub fn new() -> Self {
        let email_regex = Regex::new(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}")
            .expect("Invalid email regex");

        let phone_regex = Regex::new(r"\+?[\d\s\-\(\)\.]{10,}").expect("Invalid phone regex");

        let mut social_media_patterns = HashMap::new();
        social_media_patterns.insert(
            "facebook_url".to_string(),
            Regex::new(r"https?://(?:www\.)?facebook\.com/[a-zA-Z0-9\.]+/?")
                .expect("Invalid Facebook regex"),
        );
        social_media_patterns.insert(
            "twitter_url".to_string(),
            Regex::new(r"https?://(?:www\.)?(?:twitter\.com|x\.com)/[a-zA-Z0-9_]+/?")
                .expect("Invalid Twitter regex"),
        );
        social_media_patterns.insert(
            "instagram_url".to_string(),
            Regex::new(r"https?://(?:www\.)?instagram\.com/[a-zA-Z0-9_.]+/?")
                .expect("Invalid Instagram regex"),
        );

        DataExtractor {
            email_regex,
            phone_regex,
            social_media_patterns,
        }
    }

    pub fn extract_with_instructions(
        &self,
        html: &str,
        instructions: &[ScrapingInstruction],
    ) -> Result<HashMap<String, String>> {
        let document = Html::parse_document(html);
        let mut extracted_data = HashMap::new();

        for instruction in instructions {
            let value = match instruction.method.as_str() {
                "regex" => self.extract_with_regex(html, &instruction.pattern)?,
                "css_selector" => {
                    self.extract_with_css_selector(&document, &instruction.pattern)?
                }
                "meta_tag" => self.extract_meta_tag(&document, &instruction.pattern)?,
                "xpath" => {
                    log::warn!(
                        "XPath extraction not implemented, skipping field: {}",
                        instruction.field
                    );
                    continue;
                }
                "text_search" => self.extract_with_text_search(html, &instruction.pattern)?,
                _ => {
                    log::warn!("Unknown extraction method: {}", instruction.method);
                    continue;
                }
            };

            if let Some(val) = value {
                extracted_data.insert(instruction.field.clone(), val);
                log::debug!(
                    "Extracted {} using {}: {}",
                    instruction.field,
                    instruction.method,
                    extracted_data[&instruction.field]
                );
            }
        }

        Ok(extracted_data)
    }

    pub fn extract_basic_data(&self, html: &str) -> HashMap<String, String> {
        let document = Html::parse_document(html);
        let mut data = HashMap::new();

        // Extract emails
        if let Some(email) = self
            .extract_with_regex(html, self.email_regex.as_str())
            .unwrap_or(None)
        {
            data.insert("email".to_string(), email);
        }

        // Extract phone numbers
        if let Some(phone) = self
            .extract_with_regex(html, self.phone_regex.as_str())
            .unwrap_or(None)
        {
            data.insert("phone".to_string(), self.clean_phone_number(&phone));
        }

        // Extract social media URLs
        for (field, regex) in &self.social_media_patterns {
            if let Some(url) = self
                .extract_with_regex(html, regex.as_str())
                .unwrap_or(None)
            {
                data.insert(field.clone(), url);
            }
        }

        // Extract meta tags
        if let Some(description) = self
            .extract_meta_tag(&document, "og:description")
            .unwrap_or(None)
        {
            data.insert("description".to_string(), description);
        } else if let Some(description) = self
            .extract_meta_tag(&document, "description")
            .unwrap_or(None)
        {
            data.insert("description".to_string(), description);
        }

        if let Some(logo) = self.extract_meta_tag(&document, "og:image").unwrap_or(None) {
            data.insert("logo_url".to_string(), logo);
        }

        data
    }

    fn extract_with_regex(&self, text: &str, pattern: &str) -> Result<Option<String>> {
        let regex = Regex::new(pattern).map_err(|e| {
            error!("Invalid regex pattern: {}", pattern);
            color_eyre::Report::new(e).wrap_err(format!("Invalid regex pattern: {}", pattern))
        })?;

        Ok(regex.find(text).map(|m| m.as_str().to_string()))
    }

    fn extract_with_css_selector(
        &self,
        document: &Html,
        selector_str: &str,
    ) -> Result<Option<String>> {
        let selector = Selector::parse(selector_str).map_err(|e| {
            color_eyre::Report::msg(format!("Invalid CSS selector '{}': {:?}", selector_str, e))
        })?;

        Ok(document
            .select(&selector)
            .next()
            .map(|element| element.text().collect::<String>().trim().to_string())
            .filter(|s| !s.is_empty()))
    }

    fn extract_meta_tag(&self, document: &Html, name: &str) -> Result<Option<String>> {
        let selectors = [
            format!("meta[name='{}']", name),
            format!("meta[property='{}']", name),
            format!("meta[name='{}']", name.to_lowercase()),
            format!("meta[property='{}']", name.to_lowercase()),
        ];

        for selector_str in &selectors {
            if let Ok(selector) = Selector::parse(selector_str) {
                if let Some(element) = document.select(&selector).next() {
                    if let Some(content) = element.value().attr("content") {
                        let trimmed = content.trim();
                        if !trimmed.is_empty() {
                            return Ok(Some(trimmed.to_string()));
                        }
                    }
                }
            }
        }

        Ok(None)
    }

    fn extract_with_text_search(&self, text: &str, pattern: &str) -> Result<Option<String>> {
        if text.to_lowercase().contains(&pattern.to_lowercase()) {
            // Find the line containing the pattern and return it
            for line in text.lines() {
                if line.to_lowercase().contains(&pattern.to_lowercase()) {
                    return Ok(Some(line.trim().to_string()));
                }
            }
        }
        Ok(None)
    }

    fn clean_phone_number(&self, phone: &str) -> String {
        // Remove extra whitespace and normalize formatting
        let cleaned = phone
            .trim()
            .replace("  ", " ")
            .replace("( ", "(")
            .replace(" )", ")");

        // Ensure we have enough digits
        let digit_count = cleaned.chars().filter(|c| c.is_ascii_digit()).count();
        if digit_count >= 10 {
            cleaned
        } else {
            phone.to_string() // Return original if cleaning resulted in too few digits
        }
    }
}

pub async fn load_venue_inputs_from_csv(file_path: &str) -> Result<Vec<VenueInput>> {
    let content = fs::read_to_string(file_path).map_err(|e| {
        error!("Failed to read CSV file: {}", file_path);
        color_eyre::Report::new(e).wrap_err(format!("Failed to read CSV file: {}", file_path))
    })?;

    let mut reader = csv::Reader::from_reader(content.as_bytes());
    let mut venues = Vec::new();

    for result in reader.deserialize() {
        let venue_input: VenueInput = result.map_err(|e| {
            error!("Failed to parse CSV row");
            color_eyre::Report::new(e).wrap_err("Failed to parse CSV row")
        })?;
        venues.push(venue_input);
    }

    log::info!(
        "Loaded {} venues from CSV file: {}",
        venues.len(),
        file_path
    );
    Ok(venues)
}

pub async fn load_venue_inputs_from_json(file_path: &str) -> Result<Vec<VenueInput>> {
    let content = fs::read_to_string(file_path).map_err(|e| {
        error!("Failed to read JSON file: {}", file_path);
        color_eyre::Report::new(e).wrap_err(format!("Failed to read JSON file: {}", file_path))
    })?;

    let venues: Vec<VenueInput> = serde_json::from_str(&content).map_err(|e| {
        error!("Failed to parse JSON file: {}", file_path);
        color_eyre::Report::new(e).wrap_err("Failed to parse JSON file")
    })?;

    log::info!(
        "Loaded {} venues from JSON file: {}",
        venues.len(),
        file_path
    );
    Ok(venues)
}

pub async fn save_venues_to_json(venues: &[Venue], file_path: &str) -> Result<()> {
    // Ensure output directory exists
    if let Some(parent) = Path::new(file_path).parent() {
        fs::create_dir_all(parent).map_err(|e| {
            error!("Failed to create output directory: {:?}", parent);
            color_eyre::Report::new(e).wrap_err("Failed to create output directory")
        })?;
    }

    let json_content = serde_json::to_string_pretty(venues).map_err(|e| {
        error!("Failed to serialize venues to JSON");
        color_eyre::Report::new(e).wrap_err("Failed to serialize venues to JSON")
    })?;

    fs::write(file_path, json_content).map_err(|e| {
        error!("Failed to write venues to file: {}", file_path);
        color_eyre::Report::new(e)
            .wrap_err(format!("Failed to write venues to file: {}", file_path))
    })?;

    log::info!("Saved {} venues to: {}", venues.len(), file_path);
    Ok(())
}

pub fn validate_url(url: &str) -> bool {
    Url::parse(url).is_ok()
}

pub fn normalize_url(url: &str, base_url: Option<&str>) -> Result<String> {
    if url.starts_with("http://") || url.starts_with("https://") {
        return Ok(url.to_string());
    }

    if let Some(base) = base_url {
        let base_url = Url::parse(base).wrap_err("Invalid base URL")?;
        let full_url = base_url.join(url).wrap_err("Failed to join URLs")?;
        Ok(full_url.to_string())
    } else {
        // Assume https if no protocol specified
        if url.starts_with("//") {
            Ok(format!("https:{}", url))
        } else if url.starts_with("/") {
            Err(color_eyre::Report::msg(format!(
                "Relative URL requires base URL: {}",
                url
            )))
        } else {
            Ok(format!("https://{}", url))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_data_extractor_email() {
        let extractor = DataExtractor::new();
        let html = r#"<html><body>Contact us at info@venue.com</body></html>"#;
        let data = extractor.extract_basic_data(html);

        assert_eq!(data.get("email"), Some(&"info@venue.com".to_string()));
    }

    #[test]
    fn test_data_extractor_phone() {
        let extractor = DataExtractor::new();
        let html = r#"<html><body>Call us at (555) 123-4567</body></html>"#;
        let data = extractor.extract_basic_data(html);

        assert!(data.contains_key("phone"));
    }

    #[test]
    fn test_validate_url() {
        assert!(validate_url("https://example.com"));
        assert!(validate_url("http://venue.com/contact"));
        assert!(!validate_url("not-a-url"));
    }

    #[test]
    fn test_normalize_url() {
        assert_eq!(
            normalize_url("https://example.com", None).unwrap(),
            "https://example.com"
        );

        assert_eq!(
            normalize_url("example.com", None).unwrap(),
            "https://example.com"
        );

        assert_eq!(
            normalize_url("/contact", Some("https://example.com")).unwrap(),
            "https://example.com/contact"
        );
    }
}
