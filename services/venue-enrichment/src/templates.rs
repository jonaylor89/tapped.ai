use color_eyre::{Result, eyre::Context, eyre::eyre};
use log::debug;
use minijinja::value::Value as MiniValue;
use minijinja::{Environment, Template};

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PromptTemplate {
    pub name: String,
    pub template: String,
    pub schema: Value,
    #[serde(skip)]
    compiled_template: Option<Template<'static, 'static>>,
}

pub struct TemplateEngine {
    environment: Environment<'static>,
    templates: HashMap<String, PromptTemplate>,
}

impl PromptTemplate {
    pub fn new(name: String, template: String, schema: Value) -> Self {
        Self {
            name,
            template,
            schema,
            compiled_template: None,
        }
    }

    pub fn validate_input(&self, input: &Value) -> Result<()> {
        if jsonschema::is_valid(&self.schema, input) {
            Ok(())
        } else {
            Err(eyre!(
                "Template input validation failed for '{}': input does not match schema",
                self.name
            ))
        }
    }

    pub fn render(&self, input: &Value) -> Result<String> {
        if let Some(ref template) = self.compiled_template {
            self.validate_input(input)?;
            debug!("Rendering validated template '{}'", self.name);
            let mj_value: MiniValue = MiniValue::from_serialize(input);
            let result = template
                .render(mj_value)
                .context(format!("Failed to render template '{}'", self.name))?;
            Ok(result)
        } else {
            Err(eyre!("Template '{}' is not compiled", self.name))
        }
    }
}

impl TemplateEngine {
    pub fn new() -> Self {
        let mut env = Environment::new();
        env.set_trim_blocks(true);
        env.set_lstrip_blocks(true);

        Self {
            environment: env,
            templates: HashMap::new(),
        }
    }

    pub fn add_template(&mut self, mut template: PromptTemplate) -> Result<()> {
        // Compile the Jinja template
        let compiled_template = self
            .environment
            .template_from_str(&template.template)
            .context(format!(
                "Failed to compile Jinja template '{}'",
                template.name
            ))?;

        // Store compiled template (this is a workaround for lifetime issues)
        template.compiled_template = Some(unsafe { std::mem::transmute(compiled_template) });

        self.templates.insert(template.name.clone(), template);
        Ok(())
    }

    pub fn render_template(&self, template_name: &str, input: &Value) -> Result<String> {
        let template = self
            .templates
            .get(template_name)
            .ok_or_else(|| eyre!("Template '{}' not found", template_name))?;

        debug!(
            "Rendering template '{}' with input: {:?}",
            template_name, input
        );

        template.render(input)
    }

    pub fn load_default_templates(&mut self) -> Result<()> {
        // Rank Sources Template
        let rank_sources_template = PromptTemplate::new(
            "rank_sources".to_string(),
            include_str!("../templates/rank_sources.jinja").to_string(),
            json!({
                "type": "object",
                "properties": {
                    "venue_name": {"type": "string", "minLength": 1},
                    "search_results": {"type": "string", "minLength": 1}
                },
                "required": ["venue_name", "search_results"]
            }),
        );

        // Scraping Instructions Template
        let scraping_instructions_template = PromptTemplate::new(
            "scraping_instructions".to_string(),
            include_str!("../templates/scraping_instructions.jinja").to_string(),
            json!({
                "type": "object",
                "properties": {
                    "venue_name": {"type": "string", "minLength": 1},
                    "missing_fields": {
                        "type": "array",
                        "items": {"type": "string"},
                        "minItems": 1
                    },
                    "source_url": {"type": "string", "format": "uri"},
                    "content_preview": {"type": ["string", "null"]}
                },
                "required": ["venue_name", "missing_fields", "source_url"]
            }),
        );

        // Structured Extraction Template
        let structured_extraction_template = PromptTemplate::new(
            "structured_extraction".to_string(),
            include_str!("../templates/structured_extraction.jinja").to_string(),
            json!({
                "type": "object",
                "properties": {
                    "venue_name": {"type": "string", "minLength": 1},
                    "source_url": {"type": "string", "format": "uri"},
                    "html_preview": {"type": "string", "minLength": 1},
                    "target_fields": {
                        "type": "array",
                        "items": {"type": "string"},
                        "minItems": 1
                    }
                },
                "required": ["venue_name", "source_url", "html_preview", "target_fields"]
            }),
        );

        // Best Sources Template
        let best_sources_template = PromptTemplate::new(
            "best_sources".to_string(),
            include_str!("../templates/best_sources.jinja").to_string(),
            json!({
                "type": "object",
                "properties": {
                    "venue_name": {"type": "string", "minLength": 1},
                    "sources_info": {"type": "string", "minLength": 1},
                    "missing_fields": {
                        "type": "array",
                        "items": {"type": "string"}
                    }
                },
                "required": ["venue_name", "sources_info", "missing_fields"]
            }),
        );

        self.add_template(rank_sources_template)?;
        self.add_template(scraping_instructions_template)?;
        self.add_template(structured_extraction_template)?;
        self.add_template(best_sources_template)?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_template_validation() {
        let template = PromptTemplate::new(
            "test".to_string(),
            "Hello {{ name }}!".to_string(),
            json!({
                "type": "object",
                "properties": {
                    "name": {"type": "string", "minLength": 1}
                },
                "required": ["name"]
            }),
        );

        // Valid input
        let valid_input = json!({"name": "World"});
        assert!(template.validate_input(&valid_input).is_ok());

        // Invalid input (missing required field)
        let invalid_input = json!({});
        assert!(template.validate_input(&invalid_input).is_err());
    }

    #[test]
    fn test_template_engine() {
        let mut engine = TemplateEngine::new();

        let template = PromptTemplate::new(
            "greeting".to_string(),
            "Hello {{ name }}!".to_string(),
            json!({
                "type": "object",
                "properties": {
                    "name": {"type": "string"}
                },
                "required": ["name"]
            }),
        );

        engine
            .add_template(template)
            .expect("Failed to add template");

        let result = engine
            .render_template("greeting", &json!({"name": "World"}))
            .expect("Failed to render template");

        assert_eq!(result, "Hello World!");
    }
}
