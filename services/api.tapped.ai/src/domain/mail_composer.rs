use async_trait::async_trait;
use minijinja::{AutoEscape, Environment, context};
use reqwest::Client;
use serde::{Deserialize, Serialize};

use super::mail_bridge::EmailMessage;

const CONTACT_VENUE_HTML: &str = r#"
<p>Hey</p>
<p>{{ email_text }}</p>
{% if social_links %}<div style="margin-top: 20px;"><h3>Social Links</h3>{% for link in social_links %}<p>{{ link.label }}: <a href="{{ link.url }}">{{ link.url }}</a></p>{% endfor %}</div>{% endif %}
<p>You can check my past booking history here: <a href="https://app.tapped.ai/u/{{ username }}">https://app.tapped.ai/u/{{ username }}</a></p>
{% if press_kit_url %}<p><a href="{{ press_kit_url }}">my press kit</a></p>{% endif %}
<p>If you require any additional information or wish to discuss this opportunity further please email me back and let me know.</p>
<p>Thanks,</p><p>{{ display_name }}</p>
<p>Sent from <a href="https://tapped.ai">Tapped Ai</a></p>
"#;

const CONTACT_VENUE_TEXT: &str = r#"Hey,

{{ email_text }}
{% if social_links %}
Social Links
{% for link in social_links %}{{ link.label }}: {{ link.url }}
{% endfor %}{% endif %}
You can check my past booking history here: https://app.tapped.ai/u/{{ username }}
{% if press_kit_url %}
my press kit: {{ press_kit_url }}
{% endif %}
If you require any additional information or wish to discuss this opportunity further please email me back and let me know.

Sent from Tapped Ai

Thanks,
{{ display_name }}"#;

#[derive(Debug, Clone, Serialize)]
pub struct SocialLink {
    pub label: String,
    pub url: String,
}

#[derive(Debug, Clone)]
pub struct OpportunityContext {
    pub title: String,
    pub date: String,
    pub other_performers: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct ComposeVenueEmail {
    pub performer_display_name: String,
    pub performer_username: String,
    pub performer_genres: Vec<String>,
    pub performer_press_kit_url: Option<String>,
    pub performer_social_links: Vec<SocialLink>,
    pub venue_name: String,
    pub note: String,
    pub opportunities: Vec<OpportunityContext>,
    pub previous_messages: Vec<EmailMessage>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ComposedEmail {
    pub subject: String,
    pub generated_body: String,
    pub text_body: String,
    pub html_body: String,
}

#[async_trait]
pub trait EmailComposer: Send + Sync {
    async fn compose(&self, request: ComposeVenueEmail) -> anyhow::Result<ComposedEmail>;
}

/// LLM completions are slow; the client still gives up well before the 90s request timeout.
const COMPLETION_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(45);

pub struct OpenAiEmailComposer {
    client: Client,
    api_key: String,
    model: String,
    endpoint: String,
}

impl OpenAiEmailComposer {
    pub fn new(api_key: String, model: String) -> Self {
        Self {
            client: crate::http::client_with_timeout(COMPLETION_TIMEOUT),
            api_key,
            model,
            endpoint: "https://api.openai.com/v1/chat/completions".into(),
        }
    }

    #[cfg(test)]
    pub fn with_endpoint(api_key: String, model: String, endpoint: String) -> Self {
        Self {
            client: crate::http::client_with_timeout(COMPLETION_TIMEOUT),
            api_key,
            model,
            endpoint,
        }
    }

    fn prompt(request: &ComposeVenueEmail) -> String {
        let opportunities = request
            .opportunities
            .iter()
            .map(|opportunity| {
                format!(
                    "{} on {} with these other performers {}.",
                    opportunity.title,
                    opportunity.date,
                    opportunity.other_performers.join(", ")
                )
            })
            .collect::<Vec<_>>()
            .join("\n");
        let previous = request
            .previous_messages
            .iter()
            .map(|message| message.text_body.as_str())
            .collect::<Vec<_>>()
            .join("\n--------------\n");

        format!(
            "Venue Name: {}\nPerformer Name: {}\nPerformers Genres: {}\nNote: {}\n{}\n\
             Given only the information above, write one friendly, professional, concise, slightly dry paragraph saying the performer is open to performing for these opportunities:\n{}\n\
             Mention that Tapped Ai recommended reaching out. Do not include a greeting, introduction, sign-off, or signature. Return only the paragraph.",
            request.venue_name,
            request.performer_display_name,
            request.performer_genres.join(", "),
            request.note,
            if previous.is_empty() {
                String::new()
            } else {
                format!("Previous Conversations/Email Thread:\n###\n{previous}\n###")
            },
            opportunities,
        )
    }

    fn render(
        request: &ComposeVenueEmail,
        generated_body: String,
    ) -> anyhow::Result<ComposedEmail> {
        let mut environment = Environment::new();
        environment.set_auto_escape_callback(|_| AutoEscape::Html);
        environment.add_template("contact.html", CONTACT_VENUE_HTML)?;
        environment.add_template("contact.txt", CONTACT_VENUE_TEXT)?;
        let values = context! {
            email_text => generated_body,
            username => request.performer_username,
            display_name => request.performer_display_name,
            press_kit_url => request.performer_press_kit_url,
            social_links => request.performer_social_links,
        };
        let html_body = environment.get_template("contact.html")?.render(&values)?;
        let text_body = environment.get_template("contact.txt")?.render(&values)?;
        Ok(ComposedEmail {
            subject: format!(
                "Performance Inquiry from {}",
                request.performer_display_name
            ),
            generated_body,
            text_body,
            html_body,
        })
    }
}

#[derive(Serialize)]
struct ChatRequest<'a> {
    model: &'a str,
    messages: [ChatRequestMessage; 1],
}

#[derive(Serialize)]
struct ChatRequestMessage {
    role: &'static str,
    content: String,
}

#[derive(Deserialize)]
struct ChatResponse {
    choices: Vec<ChatChoice>,
}

#[derive(Deserialize)]
struct ChatChoice {
    message: ChatResponseMessage,
}

#[derive(Deserialize)]
struct ChatResponseMessage {
    content: String,
}

#[async_trait]
impl EmailComposer for OpenAiEmailComposer {
    #[tracing::instrument(skip_all, fields(dependency = "openai", otel.kind = "client", server.address = "api.openai.com", gen_ai.provider.name = "openai", gen_ai.operation.name = "chat"))]
    async fn compose(&self, request: ComposeVenueEmail) -> anyhow::Result<ComposedEmail> {
        let response = self
            .client
            .post(&self.endpoint)
            .bearer_auth(&self.api_key)
            .json(&ChatRequest {
                model: &self.model,
                messages: [ChatRequestMessage {
                    role: "user",
                    content: Self::prompt(&request),
                }],
            })
            .send()
            .await?
            .error_for_status()?
            .json::<ChatResponse>()
            .await?;
        let generated_body = response
            .choices
            .into_iter()
            .next()
            .map(|choice| choice.message.content.trim().to_owned())
            .filter(|body| !body.is_empty())
            .ok_or_else(|| anyhow::anyhow!("OpenAI returned no email content"))?;
        Self::render(&request, generated_body)
    }
}

pub struct StaticEmailComposer;

#[async_trait]
impl EmailComposer for StaticEmailComposer {
    async fn compose(&self, request: ComposeVenueEmail) -> anyhow::Result<ComposedEmail> {
        let opportunities = request
            .opportunities
            .iter()
            .map(|opportunity| {
                format!(
                    "{} on {} with {}",
                    opportunity.title,
                    opportunity.date,
                    opportunity.other_performers.join(", ")
                )
            })
            .collect::<Vec<_>>()
            .join("; ");
        let body = format!(
            "I'm {}. Tapped Ai recommended I reach out about {}. {}",
            request.performer_display_name, opportunities, request.note
        );
        OpenAiEmailComposer::render(&request, body)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{Json, Router, body::Bytes, routing::post};
    use std::sync::{Arc, Mutex};
    use tokio::net::TcpListener;

    fn request() -> ComposeVenueEmail {
        ComposeVenueEmail {
            performer_display_name: "The <Band>".into(),
            performer_username: "the-band".into(),
            performer_genres: vec!["Rock".into()],
            performer_press_kit_url: Some("https://example.com/press-kit".into()),
            performer_social_links: vec![SocialLink {
                label: "Instagram".into(),
                url: "https://instagram.com/theband".into(),
            }],
            venue_name: "Venue".into(),
            note: "Available Friday".into(),
            opportunities: vec![OpportunityContext {
                title: "Showcase".into(),
                date: "2026-10-01".into(),
                other_performers: vec!["Other Act".into()],
            }],
            previous_messages: vec![EmailMessage {
                thread_id: "thread".into(),
                message_id: "message".into(),
                direction: "outbound".into(),
                from: "artist@example.com".into(),
                to: vec!["venue@example.com".into()],
                subject: "Inquiry".into(),
                text_body: "Our previous conversation".into(),
                html_body: None,
                created_at: 1,
            }],
        }
    }

    #[tokio::test]
    async fn composes_and_escapes_the_legacy_template() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let captured = Arc::new(Mutex::new(Vec::new()));
        let capture = captured.clone();
        let app = Router::new().route(
            "/",
            post(move |body: Bytes| {
                let capture = capture.clone();
                async move {
                    *capture.lock().unwrap() = body.to_vec();
                    Json(serde_json::json!({ "choices": [{ "message": { "content": "We <rock>" } }] }))
                }
            }),
        );
        let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        let composer = OpenAiEmailComposer::with_endpoint(
            "key".into(),
            "model".into(),
            format!("http://{address}/"),
        );
        let email = composer.compose(request()).await.unwrap();
        server.abort();
        assert!(email.html_body.contains("We &lt;rock&gt;"));
        assert!(email.html_body.contains("Social Links"));
        assert!(email.text_body.contains("https://app.tapped.ai/u/the-band"));
        assert_eq!(email.subject, "Performance Inquiry from The <Band>");
        let payload: serde_json::Value = serde_json::from_slice(&captured.lock().unwrap()).unwrap();
        let prompt = payload["messages"][0]["content"].as_str().unwrap();
        assert!(prompt.contains("Showcase on 2026-10-01 with these other performers Other Act"));
        assert!(prompt.contains("Our previous conversation"));
    }
}
