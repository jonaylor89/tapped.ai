//! Direct APNs delivery with token-based (.p8) auth, for iOS builds without FirebaseMessaging.
use anyhow::{Result, anyhow, ensure};
use serde_json::{Value, json};
use std::{
    sync::Arc,
    time::{Duration, Instant},
};
use tokio::sync::Mutex;

const PRODUCTION_URL: &str = "https://api.push.apple.com";
const DEVELOPMENT_URL: &str = "https://api.sandbox.push.apple.com";
/// Apple rejects provider tokens older than an hour and throttles refreshes under 20 minutes.
const PROVIDER_TOKEN_LIFETIME: Duration = Duration::from_secs(40 * 60);

#[derive(Clone)]
pub struct Apns {
    client: reqwest::Client,
    key: Arc<jsonwebtoken::EncodingKey>,
    key_id: String,
    team_id: String,
    topic: String,
    production_url: String,
    development_url: String,
    token: Arc<Mutex<Option<(String, Instant)>>>,
}

impl Apns {
    pub fn new(key_file: &str, key_id: &str, team_id: &str, topic: &str) -> Result<Self> {
        let pem = std::fs::read(key_file).map_err(|_| anyhow!("APNs key file unavailable"))?;
        let key = jsonwebtoken::EncodingKey::from_ec_pem(&pem)
            .map_err(|_| anyhow!("invalid APNs signing key"))?;
        ensure!(
            !key_id.is_empty() && !team_id.is_empty() && !topic.is_empty(),
            "APNs key ID, team ID and topic are required"
        );
        Ok(Self {
            // APNs only speaks HTTP/2; TLS ALPN negotiates it.
            client: reqwest::Client::builder()
                .timeout(Duration::from_secs(30))
                .redirect(reqwest::redirect::Policy::none())
                .build()?,
            key: Arc::new(key),
            key_id: key_id.into(),
            team_id: team_id.into(),
            topic: topic.into(),
            production_url: PRODUCTION_URL.into(),
            development_url: DEVELOPMENT_URL.into(),
            token: Arc::new(Mutex::new(None)),
        })
    }

    /// Trusted test endpoints, never derived from an application request.
    pub fn with_base_urls(mut self, production: &str, development: &str) -> Self {
        self.production_url = production.into();
        self.development_url = development.into();
        self
    }

    async fn provider_token(&self) -> Result<String> {
        let mut cached = self.token.lock().await;
        if let Some((token, issued)) = cached.as_ref()
            && issued.elapsed() < PROVIDER_TOKEN_LIFETIME
        {
            return Ok(token.clone());
        }
        let mut header = jsonwebtoken::Header::new(jsonwebtoken::Algorithm::ES256);
        header.kid = Some(self.key_id.clone());
        let claims = json!({"iss": self.team_id, "iat": chrono::Utc::now().timestamp()});
        let token = jsonwebtoken::encode(&header, &claims, &self.key)
            .map_err(|_| anyhow!("APNs provider token signing failed"))?;
        *cached = Some((token.clone(), Instant::now()));
        Ok(token)
    }

    /// true means accepted by APNs, false means the device token is definitively invalid.
    pub async fn push(&self, payload: &Value) -> Result<bool> {
        let token = payload["token"].as_str().unwrap_or_default();
        ensure!(
            !token.is_empty() && token.bytes().all(|b| b.is_ascii_hexdigit()),
            "invalid APNs device token"
        );
        let base = match payload["environment"].as_str() {
            Some("production") => &self.production_url,
            Some("development") => &self.development_url,
            _ => return Err(anyhow!("invalid APNs environment")),
        };
        let response = self
            .client
            .post(format!("{base}/3/device/{token}"))
            .bearer_auth(self.provider_token().await?)
            .header("apns-topic", &self.topic)
            .header("apns-push-type", "alert")
            .header("apns-priority", "10")
            .json(&notification(payload))
            .send()
            .await
            .map_err(|_| anyhow!("APNs network error"))?;
        let status = response.status().as_u16();
        if response.status().is_success() {
            return Ok(true);
        }
        let body: Value = response.json().await.unwrap_or_default();
        let reason = body["reason"].as_str().unwrap_or_default();
        match (status, reason) {
            (410, _) | (400, "BadDeviceToken" | "DeviceTokenNotForTopic") => Ok(false),
            (403, "ExpiredProviderToken" | "InvalidProviderToken") => {
                *self.token.lock().await = None;
                Err(anyhow!("APNs rejected the provider token"))
            }
            _ => Err(anyhow!("APNs HTTP {status}")),
        }
    }
}

/// The APNs body for an outbox `push` payload: an activity (`activityId`/`bookingId`) or a direct
/// message (`conversationId`/`messageId`, threaded per conversation in Notification Center).
fn notification(payload: &Value) -> Value {
    let mut aps =
        json!({"alert": {"title": payload["title"], "body": payload["body"]}, "sound": "default"});
    let mut body = json!({});
    if let Some(conversation) = payload["conversationId"].as_str() {
        aps["thread-id"] = json!(conversation);
        body["conversationId"] = json!(conversation);
        body["messageId"] = payload["messageId"].clone();
    } else {
        body["activityId"] = payload["activityId"].clone();
        body["bookingId"] = payload["bookingId"].clone();
    }
    body["aps"] = aps;
    body
}

#[cfg(test)]
mod notification_tests {
    use super::*;

    #[test]
    fn direct_messages_thread_per_conversation_and_activities_keep_their_shape() {
        let dm = notification(
            &json!({"title":"Alice","body":"hey","conversationId":"c1","messageId":"m1"}),
        );
        assert_eq!(dm["aps"]["thread-id"], "c1");
        assert_eq!(dm["conversationId"], "c1");
        assert_eq!(dm["messageId"], "m1");
        assert!(dm.get("activityId").is_none());
        let activity =
            notification(&json!({"title":"t","body":"b","activityId":"a1","bookingId":"b1"}));
        assert_eq!(activity["activityId"], "a1");
        assert_eq!(activity["bookingId"], "b1");
        assert!(activity["aps"].get("thread-id").is_none());
    }
}
