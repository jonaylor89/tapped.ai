//! Founder notifications belong to the authoritative Postgres mutation, not a Firestore mirror.
//! A unique event key deduplicates API retries. Delivery is at-least-once: Slack incoming webhooks
//! cannot atomically acknowledge with Postgres, so an ambiguous remote success can be repeated.
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{PgPool, Postgres, Row, Transaction};
use std::time::Duration;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct FounderMessage {
    pub text: String,
}

fn escaped(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}
fn field<'a>(doc: &'a Value, key: &str) -> &'a str {
    doc[key].as_str().unwrap_or_default()
}
fn message(title: &str, body: &str) -> FounderMessage {
    let mut text = format!("*{}* - {}", escaped(title), escaped(body));
    if text.len() > 39_000 {
        let mut boundary = 39_000;
        while !text.is_char_boundary(boundary) {
            boundary -= 1;
        }
        text.truncate(boundary);
        text.push_str("… [truncated]");
    }
    FounderMessage { text }
}

pub fn onboarding_message(user: &Value) -> Option<FounderMessage> {
    if user["unclaimed"] == true || user["deleted"] == true {
        return None;
    }
    Some(message(
        "user onboarded 😎",
        &format!(
            "{} just onboarded -> https://app.tapped.ai/u/{}",
            field(user, "email"),
            field(user, "username")
        ),
    ))
}

pub fn booking_message(
    booking: &Value,
    requester: Option<&Value>,
    requestee: Option<&Value>,
) -> Option<FounderMessage> {
    if !booking["scraperInfo"].is_null() || !booking["crawlerInfo"].is_null() {
        return None;
    }
    if booking["addedByUser"] == true {
        if field(booking, "requesterId").is_empty() {
            let profile = requestee
                .map(|u| field(u, "username"))
                .filter(|name| !name.is_empty())
                .map(|name| format!("https://app.tapped.ai/u/{name}"))
                .unwrap_or_else(|| "<UNKNOWN>".into());
            return Some(message(
                "booking without location",
                &format!(
                    "booking https://app.tapped.ai/booking/{} has no venue. added by {profile} and requested",
                    field(booking, "id")
                ),
            ));
        }
        return None;
    }
    if field(booking, "requesterId").is_empty() {
        return Some(message(
            "booking without requester",
            &format!("booking {} has no requester", field(booking, "id")),
        ));
    }
    let name = |user: Option<&Value>| {
        user.and_then(|u| u["artistName"].as_str())
            .unwrap_or("<UNKNOWN>")
            .to_owned()
    };
    Some(message(
        "NEW TAPPED BOOKING!!!",
        &format!("{} booked {}", name(requester), name(requestee)),
    ))
}

pub fn application_message(user: &Value, opportunity: &Value, comment: &str) -> FounderMessage {
    let display_name = if field(user, "artistName").is_empty() {
        field(user, "username")
    } else {
        field(user, "artistName")
    };
    message(
        &format!(
            "{display_name} applied for \"{}\"",
            field(opportunity, "title")
        ),
        &format!(
            "https://app.tapped.ai/u/{} applied for https://app.tapped.ai/opportunity/{} with the comment\n\n\"{comment}\"",
            field(user, "username"),
            field(opportunity, "id")
        ),
    )
}

pub async fn enqueue(
    tx: &mut Transaction<'_, Postgres>,
    event_id: &str,
    event_type: &str,
    subject_id: &str,
    actor_id: &str,
    message: &FounderMessage,
) -> Result<(), sqlx::Error> {
    sqlx::query("INSERT INTO founder_notification_outbox(event_id,event_type,subject_id,actor_id,payload) VALUES($1,$2,$3,$4,$5) ON CONFLICT(event_id) DO NOTHING")
        .bind(event_id).bind(event_type).bind(subject_id).bind(actor_id)
        .bind(serde_json::to_value(message).expect("FounderMessage is serializable"))
        .execute(&mut **tx).await?;
    Ok(())
}

/// Called only by new API-created records, never imports or profile/booking updates.
pub async fn record_created(
    tx: &mut Transaction<'_, Postgres>,
    table: &str,
    doc: &Value,
    actor: &str,
) -> Result<(), sqlx::Error> {
    let id = field(doc, "id");
    let notification = match table {
        "users" => onboarding_message(doc),
        "bookings" => {
            let requester: Option<Value> =
                sqlx::query_scalar("SELECT doc FROM api_users WHERE id=$1")
                    .bind(field(doc, "requesterId"))
                    .fetch_optional(&mut **tx)
                    .await?;
            let requestee: Option<Value> =
                sqlx::query_scalar("SELECT doc FROM api_users WHERE id=$1")
                    .bind(field(doc, "requesteeId"))
                    .fetch_optional(&mut **tx)
                    .await?;
            booking_message(doc, requester.as_ref(), requestee.as_ref())
        }
        _ => None,
    };
    if let Some(notification) = notification {
        let kind = if table == "users" {
            "onboarding"
        } else {
            "booking"
        };
        enqueue(tx, &format!("{kind}:{id}"), kind, id, actor, &notification).await?;
    }
    Ok(())
}

pub async fn record_application(
    tx: &mut Transaction<'_, Postgres>,
    opportunity_id: &str,
    actor: &str,
    comment: &str,
) -> Result<(), sqlx::Error> {
    let user: Option<Value> = sqlx::query_scalar("SELECT doc FROM api_users WHERE id=$1")
        .bind(actor)
        .fetch_optional(&mut **tx)
        .await?;
    let opportunity: Option<Value> =
        sqlx::query_scalar("SELECT doc FROM api_opportunities WHERE id=$1")
            .bind(opportunity_id)
            .fetch_optional(&mut **tx)
            .await?;
    let user = user.unwrap_or_else(|| serde_json::json!({"id":actor,"username":actor}));
    let opportunity =
        opportunity.unwrap_or_else(|| serde_json::json!({"id":opportunity_id,"title":"<UNKNOWN>"}));
    enqueue(
        tx,
        &format!("application:{opportunity_id}:{actor}"),
        "opportunity_interest",
        opportunity_id,
        actor,
        &application_message(&user, &opportunity, comment),
    )
    .await
}

#[derive(Debug, PartialEq)]
pub enum DeliveryError {
    Network,
    Timeout,
    Http(u16, Option<u64>),
    InvalidPayload,
}
impl DeliveryError {
    fn category(&self) -> &'static str {
        match self {
            Self::Network => "network",
            Self::Timeout => "timeout",
            Self::Http(_, _) => "http",
            Self::InvalidPayload => "invalid_payload",
        }
    }
}

#[async_trait]
pub trait FounderTransport: Send + Sync {
    async fn send(&self, message: &FounderMessage) -> Result<(), DeliveryError>;
}

pub struct SlackWebhook {
    client: reqwest::Client,
    url: reqwest::Url,
}
impl SlackWebhook {
    /// Never include the URL (which contains the credential) in errors or Debug output.
    pub fn new(url: &str) -> anyhow::Result<Self> {
        let url =
            reqwest::Url::parse(url).map_err(|_| anyhow::anyhow!("invalid SLACK_WEBHOOK_URL"))?;
        anyhow::ensure!(
            url.scheme() == "https"
                && matches!(
                    url.host_str(),
                    Some("hooks.slack.com" | "hooks.slack-gov.com")
                )
                && url.path().starts_with("/services/")
                && url.username().is_empty()
                && url.password().is_none()
                && url.query().is_none()
                && url.fragment().is_none(),
            "SLACK_WEBHOOK_URL must be a Slack HTTPS incoming webhook"
        );
        Ok(Self {
            client: reqwest::Client::builder()
                .connect_timeout(Duration::from_secs(5))
                .timeout(Duration::from_secs(15))
                .redirect(reqwest::redirect::Policy::none())
                .build()?,
            url,
        })
    }
}
#[async_trait]
impl FounderTransport for SlackWebhook {
    async fn send(&self, message: &FounderMessage) -> Result<(), DeliveryError> {
        let response = self
            .client
            .post(self.url.clone())
            .json(message)
            .send()
            .await
            .map_err(|e| {
                if e.is_timeout() {
                    DeliveryError::Timeout
                } else {
                    DeliveryError::Network
                }
            })?;
        if response.status().is_success() {
            Ok(())
        } else {
            let retry_after = response
                .headers()
                .get("retry-after")
                .and_then(|v| v.to_str().ok())
                .and_then(|v| v.parse().ok());
            Err(DeliveryError::Http(response.status().as_u16(), retry_after))
        }
    }
}

struct Claimed {
    event_id: String,
    lease_token: String,
    attempts: i32,
    payload: Value,
}
async fn claim(pool: &PgPool) -> Result<Option<Claimed>, sqlx::Error> {
    let lease_token = uuid::Uuid::new_v4().to_string();
    let row = sqlx::query("WITH next AS (SELECT event_id FROM founder_notification_outbox WHERE delivered_at IS NULL AND available_at<=now() AND (locked_until IS NULL OR locked_until<=now()) ORDER BY available_at,created_at,event_id FOR UPDATE SKIP LOCKED LIMIT 1) UPDATE founder_notification_outbox o SET lease_token=$1,locked_until=now()+interval '60 seconds',attempts=attempts+1 FROM next WHERE o.event_id=next.event_id RETURNING o.event_id,o.payload,o.attempts")
        .bind(&lease_token).fetch_optional(pool).await?;
    Ok(row.map(|row| Claimed {
        event_id: row.get("event_id"),
        lease_token,
        attempts: row.get("attempts"),
        payload: row.get("payload"),
    }))
}
fn retry_seconds(attempts: i32, error: &DeliveryError) -> i64 {
    let backoff = (5_i64 * 2_i64.pow((attempts.saturating_sub(1).clamp(0, 10)) as u32)).min(3600);
    match error {
        DeliveryError::Http(429, Some(seconds)) => backoff.max((*seconds).min(3600) as i64),
        _ => backoff,
    }
}
async fn finish(
    pool: &PgPool,
    claimed: &Claimed,
    outcome: Result<(), DeliveryError>,
) -> Result<(), sqlx::Error> {
    match outcome {
        Ok(()) => {
            sqlx::query("UPDATE founder_notification_outbox SET delivered_at=now(),lease_token=NULL,locked_until=NULL,last_error=NULL WHERE event_id=$1 AND lease_token=$2")
                .bind(&claimed.event_id).bind(&claimed.lease_token).execute(pool).await?;
        }
        Err(error) => {
            // Log only a category/status, never Slack credentials, response bodies or user payloads.
            tracing::warn!(
                category = error.category(),
                "founder notification delivery will retry"
            );
            sqlx::query("UPDATE founder_notification_outbox SET available_at=now()+($3::bigint*interval '1 second'),lease_token=NULL,locked_until=NULL,last_error=$4 WHERE event_id=$1 AND lease_token=$2")
                .bind(&claimed.event_id).bind(&claimed.lease_token).bind(retry_seconds(claimed.attempts, &error))
                .bind(error.category()).execute(pool).await?;
        }
    }
    Ok(())
}
/// Process one event. Leases recover crashed workers; stale workers cannot acknowledge newer leases.
pub async fn deliver_one(
    pool: &PgPool,
    transport: &dyn FounderTransport,
) -> Result<bool, sqlx::Error> {
    let Some(claimed) = claim(pool).await? else {
        return Ok(false);
    };
    let outcome = match serde_json::from_value::<FounderMessage>(claimed.payload.clone()) {
        Ok(message) if !message.text.is_empty() && message.text.len() <= 40_000 => {
            transport.send(&message).await
        }
        _ => Err(DeliveryError::InvalidPayload),
    };
    finish(pool, &claimed, outcome).await?;
    Ok(true)
}

pub async fn run_worker(pool: PgPool, transport: SlackWebhook) {
    loop {
        let delay = match deliver_one(&pool, &transport).await {
            Ok(true) => Duration::from_secs(1), // Slack incoming-webhook per-channel rate limit.
            Ok(false) => Duration::from_secs(5),
            Err(_) => {
                tracing::warn!("founder notification database unavailable; worker will retry");
                Duration::from_secs(5)
            }
        };
        tokio::time::sleep(delay).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn notification_filters_match_legacy_business_rules() {
        let user = json!({"id":"a","email":"a@example.test","username":"artist"});
        assert!(
            onboarding_message(&user)
                .unwrap()
                .text
                .contains("user onboarded")
        );
        assert!(onboarding_message(&json!({"unclaimed":true})).is_none());
        assert!(onboarding_message(&json!({"deleted":true})).is_none());
        let booking = json!({"id":"b","requesterId":"a","requesteeId":"v"});
        assert!(
            booking_message(&booking, Some(&user), Some(&user))
                .unwrap()
                .text
                .contains("NEW TAPPED BOOKING")
        );
        for metadata in ["scraperInfo", "crawlerInfo"] {
            let mut scraped = booking.clone();
            scraped[metadata] = json!({});
            assert!(booking_message(&scraped, None, None).is_none());
        }
        let mut past = booking.clone();
        past["addedByUser"] = json!(true);
        assert!(booking_message(&past, None, None).is_none());
        past["requesterId"] = Value::Null;
        assert!(
            booking_message(&past, None, Some(&user))
                .unwrap()
                .text
                .contains("booking without location")
        );
        past["addedByUser"] = json!(false);
        assert!(
            booking_message(&past, None, None)
                .unwrap()
                .text
                .contains("booking without requester")
        );
    }
    #[test]
    fn untrusted_profile_title_and_comment_cannot_inject_slack_mentions() {
        let msg = application_message(
            &json!({"username":"artist","artistName":"<!here>"}),
            &json!({"id":"o","title":"<@admin>"}),
            "<&>",
        );
        assert!(!msg.text.contains("<!here>"));
        assert!(msg.text.contains("&lt;!here&gt;"));
        assert!(msg.text.contains("https://app.tapped.ai/opportunity/o"));
        assert!(msg.text.contains("&lt;&amp;&gt;"));
    }
    #[test]
    fn retry_backoff_is_bounded_and_honors_slack_rate_limits() {
        assert_eq!(retry_seconds(1, &DeliveryError::Network), 5);
        assert_eq!(retry_seconds(3, &DeliveryError::Timeout), 20);
        assert_eq!(retry_seconds(i32::MAX, &DeliveryError::Network), 3600);
        assert_eq!(retry_seconds(1, &DeliveryError::Http(429, Some(120))), 120);
    }
    #[test]
    fn invalid_webhook_configuration_does_not_echo_credentials() {
        for url in [
            "http://hooks.slack.com/services/private-token",
            "https://evil.invalid/services/private-token",
            "https://user:password@hooks.slack.com/services/private-token",
        ] {
            let error = SlackWebhook::new(url).err().unwrap().to_string();
            assert!(!error.contains("private-token"));
            assert!(!error.contains("password"));
        }
    }
}
