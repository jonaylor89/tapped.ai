use crate::models::*;
use crate::templates::TemplateEngine;
use color_eyre::{eyre::Context, Result};
use reqwest::Client;
use serde_json::json;
use std::collections::HashMap;
use tokio::time::{sleep, Duration};
use url::Url;

pub struct Agent {
    client: Client,
    exa_api_key: String,
    llm_api_key: String,
    llm_base_url: String,
    llm_model: String,
    template_engine: TemplateEngine,
}

impl Agent {
    pub fn new(
        exa_api_key: String,
        llm_api_key: String,
        llm_base_url: String,
        llm_model: String,
    ) -> Result<Self> {
        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .user_agent("venue-enrichment/0.1.1")
            .build()
            .expect("Failed to create HTTP client");

        let mut template_engine = TemplateEngine::new();
        template_engine.load_default_templates()
            .context("Failed to load default templates")?;

        Ok(Agent {
            client,
            exa_api_key,
            llm_api_key,
            llm_base_url,
            llm_model,
            template_engine,
        })
    }

    pub async fn search_venues(&self, venue_input: &VenueInput) -> Result<Vec<ExaSearchResult>> {
        let query = if let Some(ref context) = venue_input.context {
            format!("{} {}", venue_input.name, context)
        } else {
            venue_input.name.clone()
        };

        log::debug!(
            "Searching for venue: '{}' with query: '{}'",
            venue_input.name,
            query
        );

        let search_request = ExaSearchRequest {
            query: format!("music venue concert hall \"{}\" contact information", query),
            search_type: Some("neural".to_string()),
            category: Some("company".to_string()),
            num_results: Some(10),
            include_domains: None,
            exclude_domains: None,
            start_crawl_date: None,
            end_crawl_date: None,
            start_published_date: None,
            end_published_date: None,
            include_text: None,
            exclude_text: None,
            context: Some(true),
            moderation: Some(true),
        };

        log::debug!(
            "Sending Exa API request: {}",
            serde_json::to_string_pretty(&search_request).unwrap_or_default()
        );

        let response = self
            .client
            .post("https://api.exa.ai/search")
            .header("x-api-key", &self.exa_api_key)
            .header("Content-Type", "application/json")
            .json(&search_request)
            .send()
            .await
            .map_err(|e| {
                log::error!(
                    "Failed to send Exa search request for venue: {}",
                    venue_input.name
                );
                color_eyre::Report::new(e).wrap_err(format!(
                    "Failed to send Exa search request for venue: {}",
                    venue_input.name
                ))
            })?;

        if !response.status().is_success() {
            let status = response.status();
            let error_text = response.text().await.unwrap_or_default();

            // Enhanced error logging with more context
            log::error!(
                "Exa API request failed for venue '{}' - Status: {}, Body: {}, Query: '{}'",
                venue_input.name,
                status,
                error_text,
                query
            );

            // Provide more specific error messages based on status code
            let error_message = match status.as_u16() {
                401 => format!(
                    "Authentication failed - check your Exa API key. Status: {}",
                    status
                ),
                403 => format!(
                    "Access forbidden - your API key may not have the required permissions. Status: {}",
                    status
                ),
                429 => format!(
                    "Rate limit exceeded - slow down your requests. Status: {}",
                    status
                ),
                400 => format!(
                    "Bad request - check your search query format. Status: {}, Body: {}",
                    status, error_text
                ),
                500..=599 => format!("Exa API server error - try again later. Status: {}", status),
                _ => format!(
                    "Exa search failed. Status: {}, Body: {}",
                    status, error_text
                ),
            };

            return Err(color_eyre::Report::msg(error_message));
        }

        let search_response: ExaSearchResponse = response.json().await.map_err(|e| {
            log::error!(
                "Failed to parse Exa search response for venue: {}",
                venue_input.name
            );
            color_eyre::Report::new(e).wrap_err(format!(
                "Failed to parse Exa search response for venue: {}",
                venue_input.name
            ))
        })?;

        log::debug!(
            "Parsed Exa response structure for '{}': request_id={:?}, search_type={:?}, results_count={}",
            venue_input.name,
            search_response.request_id,
            search_response.resolved_search_type,
            search_response.results.len()
        );

        let results_count = search_response.results.len();

        if results_count > 0 {
            let cost = search_response
                .cost_dollars
                .as_ref()
                .and_then(|c| c.total)
                .unwrap_or(0.0);

            log::info!(
                "Found {} search results for venue: '{}' (cost: ${:.4})",
                results_count,
                venue_input.name,
                cost
            );

            // Log top results for debugging
            log::debug!(
                "Top 3 results for '{}': {:#?}",
                venue_input.name,
                search_response.results.iter().take(3).collect::<Vec<_>>()
            );
        } else {
            log::warn!(
                "⚠ No search results found for venue: '{}'",
                venue_input.name
            );
        }

        Ok(search_response.results)
    }

    pub async fn rank_sources(
        &self,
        venue_name: &str,
        search_results: &[ExaSearchResult],
        blocklist: &[String],
    ) -> Result<Vec<(ExaSearchResult, f32)>> {
        let filtered_results: Vec<_> = search_results
            .iter()
            .filter(|result| !self.is_blocked_url(&result.url, blocklist))
            .cloned()
            .collect();

        if filtered_results.is_empty() {
            log::warn!("All search results were blocked for venue: {}", venue_name);
            return Ok(vec![]);
        }

        let _results_json = serde_json::to_string_pretty(&filtered_results).map_err(|e| {
            log::error!("Failed to serialize search results");
            color_eyre::Report::new(e).wrap_err("Failed to serialize search results")
        })?;

        let search_results_json = serde_json::to_string_pretty(&filtered_results)?;
        let context = json!({
            "venue_name": venue_name,
            "search_results": search_results_json
        });
        let prompt = self.template_engine.render_template("rank_sources", &context)?;

        let ranking_response = self.call_llm(&prompt).await?;
        let mut ranked_results = Vec::new();

        // Parse XML response to extract rankings
        for line in ranking_response.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with("<source>") {
                let mut url: Option<String> = None;
                let mut score: Option<f32> = None;
                let mut reasoning: Option<String> = None;

                // Parse the source block
                let line_iter = ranking_response
                    .lines()
                    .skip_while(|l| !l.trim().eq(trimmed));

                for line in line_iter {
                    let line = line.trim();
                    if line.starts_with("<url>") && line.ends_with("</url>") {
                        url = line
                            .strip_prefix("<url>")
                            .and_then(|s| s.strip_suffix("</url>"))
                            .map(|s| s.trim().to_string());
                    } else if line.starts_with("<score>") && line.ends_with("</score>") {
                        if let Some(score_str) = line
                            .strip_prefix("<score>")
                            .and_then(|s| s.strip_suffix("</score>"))
                        {
                            score = score_str.trim().parse::<f32>().ok();
                        }
                    } else if line.starts_with("<reasoning>") && line.ends_with("</reasoning>") {
                        reasoning = line
                            .strip_prefix("<reasoning>")
                            .and_then(|s| s.strip_suffix("</reasoning>"))
                            .map(|s| s.trim().to_string());
                    } else if line == "</source>" {
                        break;
                    }
                }

                if let (Some(url), Some(score)) = (url, score) {
                    if let Some(result) = filtered_results.iter().find(|r| r.url == url) {
                        ranked_results.push((result.clone(), score));
                        log::debug!(
                            "Ranked {} with score {}: {}",
                            url,
                            score,
                            reasoning.unwrap_or_else(|| "no reason".to_string())
                        );
                    }
                }
            }
        }

        ranked_results.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        log::info!(
            "Ranked {} sources for venue: {} (top score: {:.2})",
            ranked_results.len(),
            venue_name,
            ranked_results.first().map(|r| r.1).unwrap_or(0.0)
        );

        Ok(ranked_results)
    }

    pub async fn generate_scraping_instructions(
        &self,
        venue_name: &str,
        missing_fields: &[String],
        source_url: &str,
        source_content_preview: Option<&str>,
    ) -> Result<Vec<ScrapingInstruction>> {
        let _content_info = if let Some(preview) = source_content_preview {
            format!("Content preview:\n{}\n\n", preview)
        } else {
            "No content preview available.\n\n".to_string()
        };

        let context = json!({
            "venue_name": venue_name,
            "missing_fields": missing_fields,
            "source_url": source_url,
            "content_preview": source_content_preview
        });
        let prompt = self.template_engine.render_template("scraping_instructions", &context)?;

        let response = self.call_llm(&prompt).await?;

        // Parse XML response to extract instructions
        let mut instructions = Vec::new();

        for line in response.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with("<instruction>") {
                let mut field: Option<String> = None;
                let mut method: Option<String> = None;
                let mut pattern: Option<String> = None;
                let mut priority: Option<i32> = None;
                let mut reasoning: Option<String> = None;

                // Parse the instruction block
                let line_iter = response.lines().skip_while(|l| !l.trim().eq(trimmed));

                for line in line_iter {
                    let line = line.trim();
                    if line.starts_with("<field>") && line.ends_with("</field>") {
                        field = line
                            .strip_prefix("<field>")
                            .and_then(|s| s.strip_suffix("</field>"))
                            .map(|s| s.trim().to_string());
                    } else if line.starts_with("<method>") && line.ends_with("</method>") {
                        method = line
                            .strip_prefix("<method>")
                            .and_then(|s| s.strip_suffix("</method>"))
                            .map(|s| s.trim().to_string());
                    } else if line.starts_with("<pattern>") && line.ends_with("</pattern>") {
                        pattern = line
                            .strip_prefix("<pattern>")
                            .and_then(|s| s.strip_suffix("</pattern>"))
                            .map(|s| s.trim().to_string());
                    } else if line.starts_with("<priority>") && line.ends_with("</priority>") {
                        if let Some(priority_str) = line
                            .strip_prefix("<priority>")
                            .and_then(|s| s.strip_suffix("</priority>"))
                        {
                            priority = priority_str.trim().parse::<i32>().ok();
                        }
                    } else if line.starts_with("<reasoning>") && line.ends_with("</reasoning>") {
                        reasoning = line
                            .strip_prefix("<reasoning>")
                            .and_then(|s| s.strip_suffix("</reasoning>"))
                            .map(|s| s.trim().to_string());
                    } else if line == "</instruction>" {
                        break;
                    }
                }

                if let (Some(field), Some(method), Some(pattern)) = (field, method, pattern) {
                    instructions.push(ScrapingInstruction {
                        field,
                        method,
                        pattern,
                        priority: priority.unwrap_or(1) as u32,
                        reasoning: reasoning.unwrap_or_else(|| "No reasoning provided".to_string()),
                    });
                }
            }
        }

        log::info!(
            "Generated {} scraping instructions for {} missing fields",
            instructions.len(),
            missing_fields.len()
        );

        Ok(instructions)
    }

    pub async fn extract_structured_data(
        &self,
        venue_name: &str,
        source_url: &str,
        raw_html: &str,
        target_fields: &[String],
    ) -> Result<HashMap<String, String>> {
        let html_preview = if raw_html.len() > 5000 {
            format!("{}...[truncated]", &raw_html[..5000])
        } else {
            raw_html.to_string()
        };

        let context = json!({
            "venue_name": venue_name,
            "target_fields": target_fields,
            "source_url": source_url,
            "html_preview": html_preview
        });
        let prompt = self.template_engine.render_template("structured_extraction", &context)?;

        let response = self.call_llm(&prompt).await?;

        // Parse XML response to extract venue data
        let mut extracted_data = HashMap::new();

        for line in response.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with("<")
                && trimmed.ends_with(">")
                && !trimmed.starts_with("</")
                && !trimmed.eq("<venue_data>")
                && !trimmed.eq("</venue_data>")
            {
                if let Some(tag_end) = trimmed.find(">") {
                    let tag_name = &trimmed[1..tag_end];
                    let closing_tag = format!("</{}>", tag_name);

                    if let Some(value_start) = trimmed.get(tag_end + 1..) {
                        if let Some(closing_pos) = value_start.rfind(&closing_tag) {
                            let value = value_start[..closing_pos].trim();
                            if !value.is_empty() {
                                extracted_data.insert(tag_name.to_string(), value.to_string());
                            }
                        }
                    }
                }
            }
        }

        log::info!(
            "Extracted {} fields from {}: {:?}",
            extracted_data.len(),
            source_url,
            extracted_data.keys().collect::<Vec<_>>()
        );

        Ok(extracted_data)
    }

    async fn call_llm(&self, prompt: &str) -> Result<String> {
        let request = LLMRequest {
            messages: vec![
                LLMMessage {
                    role: "system".to_string(),
                    content: "You are a helpful AI assistant that always responds with valid XML when requested. Be precise and accurate in your analysis.".to_string(),
                },
                LLMMessage {
                    role: "user".to_string(),
                    content: prompt.to_string(),
                },
            ],
            model: self.llm_model.clone(),
            temperature: Some(0.1),
            max_tokens: Some(2000),
            stop: None,
        };

        let mut attempts = 0;
        let max_attempts = 3;

        while attempts < max_attempts {
            let response = self
                .client
                .post(format!("{}/chat/completions", self.llm_base_url))
                .header("Authorization", format!("Bearer {}", self.llm_api_key))
                .header("Content-Type", "application/json")
                .json(&request)
                .send()
                .await;

            match response {
                Ok(resp) if resp.status().is_success() => {
                    let llm_response: LLMResponse = resp.json().await.map_err(|e| {
                        log::error!("Failed to parse LLM response");
                        color_eyre::Report::new(e).wrap_err("Failed to parse LLM response")
                    })?;

                    if let Some(choice) = llm_response.choices.first() {
                        return Ok(choice.message.content.clone());
                    } else {
                        return Err(color_eyre::Report::msg("No choices in LLM response"));
                    }
                }
                Ok(resp) => {
                    let status = resp.status();
                    let error_text = resp.text().await.unwrap_or_default();
                    log::warn!(
                        "LLM request failed (attempt {}): {} - {}",
                        attempts + 1,
                        status,
                        error_text
                    );
                }
                Err(e) => {
                    log::warn!("LLM request error (attempt {}): {}", attempts + 1, e);
                }
            }

            attempts += 1;
            if attempts < max_attempts {
                sleep(Duration::from_secs(2_u64.pow(attempts))).await;
            }
        }

        Err(color_eyre::Report::msg(format!(
            "Failed to get response from LLM after {} attempts",
            max_attempts
        )))
    }

    fn is_blocked_url(&self, url: &str, blocklist: &[String]) -> bool {
        if let Ok(parsed_url) = Url::parse(url) {
            if let Some(domain) = parsed_url.host_str() {
                return blocklist.iter().any(|blocked| {
                    domain == blocked || domain.ends_with(&format!(".{}", blocked))
                });
            }
        }
        false
    }

    pub async fn determine_best_sources(
        &self,
        venue_name: &str,
        ranked_sources: &[(ExaSearchResult, f32)],
        missing_fields: &[String],
    ) -> Result<Vec<String>> {
        if ranked_sources.is_empty() {
            return Ok(vec![]);
        }

        let sources_info: Vec<_> = ranked_sources
            .iter()
            .take(5) // Consider top 5 sources
            .map(|(result, score)| {
                json!({
                    "url": result.url,
                    "title": result.title.as_ref().unwrap_or(&"No title".to_string()),
                    "score": score,
                    "text_preview": result.text.as_ref().map(|t|
                        if t.len() > 200 { format!("{}...", &t[..200]) } else { t.clone() }
                    )
                })
            })
            .collect();

        let sources_info_json = serde_json::to_string_pretty(&sources_info)?;
        let context = json!({
            "venue_name": venue_name,
            "missing_fields": missing_fields,
            "sources_info": sources_info_json
        });
        let prompt = self.template_engine.render_template("best_sources", &context)?;

        let response = self.call_llm(&prompt).await?;

        // Parse XML response to extract URLs
        let mut selected_urls = Vec::new();

        // Simple XML parsing - look for <source> tags
        for line in response.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with("<source>") && trimmed.ends_with("</source>") {
                let url = trimmed
                    .strip_prefix("<source>")
                    .and_then(|s| s.strip_suffix("</source>"))
                    .unwrap_or("")
                    .trim();
                if !url.is_empty() {
                    selected_urls.push(url.to_string());
                }
            }
        }

        if selected_urls.is_empty() {
            return Err(color_eyre::Report::msg("Failed to parse any URLs from XML response"));
        }

        log::info!(
            "Selected {} sources to scrape for venue: {} ({:?})",
            selected_urls.len(),
            venue_name,
            selected_urls
        );

        Ok(selected_urls)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_agent_creation() {
        let agent = Agent::new(
            "test-exa-key".to_string(),
            "test-llm-key".to_string(),
            "https://api.openai.com/v1".to_string(),
            "gpt-3.5-turbo".to_string(),
        );

        assert_eq!(agent.exa_api_key, "test-exa-key");
        assert_eq!(agent.llm_model, "gpt-3.5-turbo");
    }

    #[test]
    fn test_is_blocked_url() {
        let agent = Agent::new(
            "test".to_string(),
            "test".to_string(),
            "test".to_string(),
            "test".to_string(),
        );

        let blocklist = vec!["facebook.com".to_string(), "twitter.com".to_string()];

        assert!(agent.is_blocked_url("https://facebook.com/venue", &blocklist));
        assert!(agent.is_blocked_url("https://www.facebook.com/venue", &blocklist));
        assert!(!agent.is_blocked_url("https://example.com", &blocklist));
    }
}
