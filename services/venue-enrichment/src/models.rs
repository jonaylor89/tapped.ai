use serde::{Deserialize, Serialize};
use schemars::JsonSchema;
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct Venue {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub phone: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub website: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "facebookUrl")]
    pub facebook_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "twitterUrl")]
    pub twitter_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "instagramUrl")]
    pub instagram_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "logoUrl")]
    pub logo_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "idealPerformerProfile")]
    pub ideal_performer_profile: Option<String>,
    
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provenance: Option<HashMap<String, String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VenueInput {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub context: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExaSearchResult {
    pub id: Option<String>,
    pub url: String,
    pub title: Option<String>,
    pub text: Option<String>,
    #[serde(rename = "publishedDate")]
    pub published_date: Option<String>,
    pub author: Option<String>,
    pub highlights: Option<Vec<String>>,
    #[serde(rename = "highlightScores")]
    pub highlight_scores: Option<Vec<f64>>,
    pub summary: Option<String>,
    pub image: Option<String>,
    pub favicon: Option<String>,
    pub extras: Option<serde_json::Value>, // Flexible for additional fields
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExaCostBreakdown {
    pub total: Option<f64>,
    #[serde(rename = "breakDown")]
    pub break_down: Option<Vec<serde_json::Value>>, // Complex nested structure
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExaSearchResponse {
    #[serde(rename = "requestId")]
    pub request_id: Option<String>,
    #[serde(rename = "resolvedSearchType")]
    pub resolved_search_type: Option<String>,
    #[serde(rename = "searchType")]
    pub search_type: Option<String>,
    pub results: Vec<ExaSearchResult>,
    pub context: Option<String>,
    #[serde(rename = "costDollars")]
    pub cost_dollars: Option<ExaCostBreakdown>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExaSearchRequest {
    pub query: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "type")]
    pub search_type: Option<String>, // "keyword", "neural", "fast", "auto"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "numResults")]
    pub num_results: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "includeDomains")]
    pub include_domains: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "excludeDomains")]
    pub exclude_domains: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "startCrawlDate")]
    pub start_crawl_date: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "endCrawlDate")]
    pub end_crawl_date: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "startPublishedDate")]
    pub start_published_date: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "endPublishedDate")]
    pub end_published_date: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "includeText")]
    pub include_text: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "excludeText")]
    pub exclude_text: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub context: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub moderation: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LLMRequest {
    pub messages: Vec<LLMMessage>,
    pub model: String,
    pub temperature: Option<f32>,
    pub max_tokens: Option<u32>,
    pub stop: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LLMMessage {
    pub role: String, // "system", "user", "assistant"
    pub content: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LLMResponse {
    pub choices: Vec<LLMChoice>,
    pub usage: Option<LLMUsage>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LLMChoice {
    pub message: LLMMessage,
    pub finish_reason: Option<String>,
    pub index: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LLMUsage {
    pub prompt_tokens: u32,
    pub completion_tokens: u32,
    pub total_tokens: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExtractedData {
    pub venue: Venue,
    pub confidence: f32,
    pub reasoning: String,
    pub sources_used: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScrapingInstruction {
    pub field: String,
    pub method: String, // "regex", "css_selector", "xpath", "llm_extract"
    pub pattern: String,
    pub priority: u32,
    pub reasoning: String,
}

impl Venue {
    pub fn new(name: String) -> Self {
        Venue {
            name,
            description: None,
            email: None,
            phone: None,
            website: None,
            facebook_url: None,
            twitter_url: None,
            instagram_url: None,
            logo_url: None,
            ideal_performer_profile: None,
            provenance: Some(HashMap::new()),
        }
    }

    pub fn set_field_with_source(&mut self, field: &str, value: String, source: String) {
        if let Some(ref mut provenance) = self.provenance {
            provenance.insert(field.to_string(), source);
        }

        match field {
            "description" => self.description = Some(value),
            "email" => self.email = Some(value),
            "phone" => self.phone = Some(value),
            "website" => self.website = Some(value),
            "facebook_url" => self.facebook_url = Some(value),
            "twitter_url" => self.twitter_url = Some(value),
            "instagram_url" => self.instagram_url = Some(value),
            "logo_url" => self.logo_url = Some(value),
            "ideal_performer_profile" => self.ideal_performer_profile = Some(value),
            _ => log::warn!("Unknown field: {}", field),
        }
    }

    pub fn is_complete(&self) -> bool {
        self.description.is_some()
    }

    pub fn missing_fields(&self) -> Vec<String> {
        let mut missing = Vec::new();
        
        if self.description.is_none() { missing.push("description".to_string()); }
        if self.email.is_none() { missing.push("email".to_string()); }
        if self.phone.is_none() { missing.push("phone".to_string()); }
        if self.website.is_none() { missing.push("website".to_string()); }
        if self.facebook_url.is_none() { missing.push("facebook_url".to_string()); }
        if self.twitter_url.is_none() { missing.push("twitter_url".to_string()); }
        if self.instagram_url.is_none() { missing.push("instagram_url".to_string()); }
        if self.logo_url.is_none() { missing.push("logo_url".to_string()); }
        if self.ideal_performer_profile.is_none() { missing.push("ideal_performer_profile".to_string()); }
        
        missing
    }

    pub fn validate(&self) -> color_eyre::Result<()> {
        if self.name.trim().is_empty() {
            return Err(color_eyre::Report::msg("Venue name cannot be empty"));
        }

        if let Some(ref email) = self.email {
            if !email.contains('@') || email.len() < 5 {
                return Err(color_eyre::Report::msg(format!("Invalid email format: {}", email)));
            }
        }

        if let Some(ref url) = self.website {
            if !url.starts_with("http://") && !url.starts_with("https://") {
                return Err(color_eyre::Report::msg(format!("Website URL must start with http:// or https://: {}", url)));
            }
        }

        Ok(())
    }
}

impl Default for Venue {
    fn default() -> Self {
        Venue::new("".to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_venue_creation() {
        let venue = Venue::new("Test Venue".to_string());
        assert_eq!(venue.name, "Test Venue");
        assert!(venue.description.is_none());
        assert!(venue.provenance.is_some());
    }

    #[test]
    fn test_set_field_with_source() {
        let mut venue = Venue::new("Test Venue".to_string());
        venue.set_field_with_source("email", "test@example.com".to_string(), "website".to_string());
        
        assert_eq!(venue.email, Some("test@example.com".to_string()));
        assert_eq!(venue.provenance.unwrap().get("email"), Some(&"website".to_string()));
    }

    #[test]
    fn test_missing_fields() {
        let venue = Venue::new("Test Venue".to_string());
        let missing = venue.missing_fields();
        assert!(!missing.is_empty());
        assert!(missing.contains(&"description".to_string()));
    }

    #[test]
    fn test_venue_validation() {
        let venue = Venue::new("Test Venue".to_string());
        assert!(venue.validate().is_ok());
        
        let mut invalid_venue = venue.clone();
        invalid_venue.name = "".to_string();
        assert!(invalid_venue.validate().is_err());
    }
}