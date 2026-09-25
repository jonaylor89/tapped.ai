use async_trait::async_trait;
use axum::{
    Json,
    body::Bytes,
    extract::State,
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
};
use chrono::Utc;
use hmac::{Hmac, Mac};
use mailparse::{MailHeaderMap, parse_mail};
use rusqlite::{Connection, OptionalExtension, params};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};
use uuid::Uuid;

use crate::{domain::firebase_auth::FirebaseUser, state::AppStateDyn};

type HmacSha256 = Hmac<Sha256>;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct EmailThread {
    pub id: String,
    pub performer_id: String,
    pub performer_username: String,
    pub venue_id: String,
    pub recipients: Vec<String>,
    pub subject: String,
    pub latest_message_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct QueuedEmail {
    pub event_id: String,
    pub thread_id: String,
    pub from: String,
    pub to: Vec<String>,
    pub subject: String,
    pub text_body: String,
    #[serde(default)]
    pub html_body: Option<String>,
    pub message_id: String,
    pub in_reply_to: String,
    pub references: String,
    pub attachments: Vec<String>,
    #[serde(default)]
    pub encoded_attachments: Vec<EncodedAttachment>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct EncodedAttachment {
    pub name: String,
    pub content_type: String,
    pub content: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct StreamDelivery {
    pub event_id: String,
    pub thread_id: String,
    pub sender_id: String,
    pub receiver_id: String,
    pub text: String,
}

#[async_trait]
pub trait MailStore: Send + Sync {
    async fn upsert_thread(&self, thread: EmailThread) -> anyhow::Result<()>;
    async fn create_thread_and_enqueue(
        &self,
        thread: EmailThread,
        email: QueuedEmail,
    ) -> anyhow::Result<bool>;
    async fn thread_for_stream(
        &self,
        performer_id: &str,
        venue_id: &str,
    ) -> anyhow::Result<Option<EmailThread>>;
    async fn thread_for_reply(
        &self,
        username: &str,
        references: &[String],
    ) -> anyhow::Result<Option<EmailThread>>;
    async fn enqueue_outbound(&self, email: QueuedEmail) -> anyhow::Result<bool>;
    async fn claim_inbound(
        &self,
        message_id: &str,
        raw: &[u8],
        delivery: &StreamDelivery,
    ) -> anyhow::Result<bool>;
    async fn mark_inbound_delivered(&self, message_id: &str) -> anyhow::Result<()>;
    async fn mark_inbound_failed(&self, message_id: &str) -> anyhow::Result<()>;
    async fn record_orphan(&self, raw: &[u8], reason: &str) -> anyhow::Result<()>;
    async fn update_latest_message_id(
        &self,
        thread_id: &str,
        message_id: &str,
    ) -> anyhow::Result<()>;
}

#[async_trait]
pub trait StreamGateway: Send + Sync {
    async fn send_message(&self, delivery: &StreamDelivery) -> anyhow::Result<()>;
}

#[derive(Clone)]
pub struct MailBridge {
    pub store: Arc<dyn MailStore>,
    pub stream: Arc<dyn StreamGateway>,
    pub stream_webhook_secret: String,
    pub ingress_secret: String,
    pub service_secret: String,
    pub booking_domain: String,
}

impl MailBridge {
    pub fn disabled() -> Self {
        Self {
            store: Arc::new(InMemoryMailStore::default()),
            stream: Arc::new(NoopStreamGateway),
            stream_webhook_secret: "disabled".into(),
            ingress_secret: "disabled".into(),
            service_secret: "disabled".into(),
            booking_domain: "booking.tapped.ai".into(),
        }
    }
}

#[derive(Default)]
struct MemoryState {
    threads: Vec<EmailThread>,
    outbound: Vec<QueuedEmail>,
    inbound: HashMap<String, (String, StreamDelivery)>,
    orphans: Vec<(Vec<u8>, String)>,
}

#[derive(Default)]
pub struct InMemoryMailStore {
    state: Mutex<MemoryState>,
}

impl InMemoryMailStore {
    pub fn outbound(&self) -> Vec<QueuedEmail> {
        self.state.lock().unwrap().outbound.clone()
    }

    pub fn orphan_count(&self) -> usize {
        self.state.lock().unwrap().orphans.len()
    }
}

#[async_trait]
impl MailStore for InMemoryMailStore {
    async fn upsert_thread(&self, thread: EmailThread) -> anyhow::Result<()> {
        let mut state = self.state.lock().unwrap();
        state.threads.retain(|item| item.id != thread.id);
        state.threads.push(thread);
        Ok(())
    }

    async fn create_thread_and_enqueue(
        &self,
        thread: EmailThread,
        email: QueuedEmail,
    ) -> anyhow::Result<bool> {
        let mut state = self.state.lock().unwrap();
        if state
            .outbound
            .iter()
            .any(|item| item.event_id == email.event_id)
        {
            return Ok(false);
        }
        if state
            .threads
            .iter()
            .any(|item| item.id == thread.id && item.performer_id != thread.performer_id)
        {
            anyhow::bail!("email thread belongs to another performer");
        }
        state.threads.retain(|item| item.id != thread.id);
        state.threads.push(thread);
        state.outbound.push(email);
        Ok(true)
    }

    async fn thread_for_stream(
        &self,
        performer_id: &str,
        venue_id: &str,
    ) -> anyhow::Result<Option<EmailThread>> {
        Ok(self
            .state
            .lock()
            .unwrap()
            .threads
            .iter()
            .find(|thread| thread.performer_id == performer_id && thread.venue_id == venue_id)
            .cloned())
    }

    async fn thread_for_reply(
        &self,
        username: &str,
        references: &[String],
    ) -> anyhow::Result<Option<EmailThread>> {
        let state = self.state.lock().unwrap();
        Ok(state
            .threads
            .iter()
            .find(|thread| {
                thread.performer_username.eq_ignore_ascii_case(username)
                    && references.iter().any(|reference| {
                        reference == &thread.latest_message_id
                            || state.outbound.iter().any(|email| {
                                email.thread_id == thread.id && &email.message_id == reference
                            })
                            || state
                                .inbound
                                .get(reference)
                                .is_some_and(|(_, delivery)| delivery.thread_id == thread.id)
                    })
            })
            .cloned())
    }

    async fn enqueue_outbound(&self, email: QueuedEmail) -> anyhow::Result<bool> {
        let mut state = self.state.lock().unwrap();
        if state
            .outbound
            .iter()
            .any(|item| item.event_id == email.event_id)
        {
            return Ok(false);
        }
        if let Some(thread) = state
            .threads
            .iter_mut()
            .find(|thread| thread.id == email.thread_id)
        {
            thread.latest_message_id = email.message_id.clone();
        }
        state.outbound.push(email);
        Ok(true)
    }

    async fn claim_inbound(
        &self,
        message_id: &str,
        _raw: &[u8],
        _delivery: &StreamDelivery,
    ) -> anyhow::Result<bool> {
        let mut state = self.state.lock().unwrap();
        match state
            .inbound
            .get(message_id)
            .map(|(status, _)| status.as_str())
        {
            Some("processing" | "delivered") => Ok(false),
            _ => {
                state.inbound.insert(
                    message_id.to_owned(),
                    ("processing".into(), _delivery.clone()),
                );
                Ok(true)
            }
        }
    }

    async fn mark_inbound_delivered(&self, message_id: &str) -> anyhow::Result<()> {
        if let Some((status, _)) = self.state.lock().unwrap().inbound.get_mut(message_id) {
            *status = "delivered".into();
        }
        Ok(())
    }

    async fn mark_inbound_failed(&self, message_id: &str) -> anyhow::Result<()> {
        if let Some((status, _)) = self.state.lock().unwrap().inbound.get_mut(message_id) {
            *status = "failed".into();
        }
        Ok(())
    }

    async fn record_orphan(&self, raw: &[u8], reason: &str) -> anyhow::Result<()> {
        self.state
            .lock()
            .unwrap()
            .orphans
            .push((raw.to_vec(), reason.to_owned()));
        Ok(())
    }

    async fn update_latest_message_id(
        &self,
        thread_id: &str,
        message_id: &str,
    ) -> anyhow::Result<()> {
        if let Some(thread) = self
            .state
            .lock()
            .unwrap()
            .threads
            .iter_mut()
            .find(|thread| thread.id == thread_id)
        {
            thread.latest_message_id = message_id.to_owned();
        }
        Ok(())
    }
}

pub struct SqliteMailStore {
    connection: Mutex<Connection>,
}

impl SqliteMailStore {
    pub fn open(path: &str) -> anyhow::Result<Self> {
        let connection = Connection::open(path)?;
        connection.busy_timeout(std::time::Duration::from_secs(5))?;
        connection.execute_batch(
            "PRAGMA journal_mode=WAL;
             PRAGMA synchronous=FULL;
             CREATE TABLE IF NOT EXISTS email_threads (
               id TEXT PRIMARY KEY, performer_id TEXT NOT NULL, performer_username TEXT NOT NULL,
               venue_id TEXT NOT NULL, recipients TEXT NOT NULL, subject TEXT NOT NULL,
               latest_message_id TEXT NOT NULL,
               UNIQUE(performer_id, venue_id)
             );
             CREATE TABLE IF NOT EXISTS email_outbox (
               event_id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, payload TEXT NOT NULL,
               state TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0,
               created_at INTEGER NOT NULL
             );
             CREATE TABLE IF NOT EXISTS inbound_emails (
               message_id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, raw BLOB NOT NULL,
               delivery TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'pending', created_at INTEGER NOT NULL
             );
             CREATE TABLE IF NOT EXISTS orphan_emails (
               id INTEGER PRIMARY KEY AUTOINCREMENT, raw BLOB NOT NULL, reason TEXT NOT NULL,
               created_at INTEGER NOT NULL
             );",
        )?;
        let _ = connection.execute(
            "ALTER TABLE inbound_emails ADD COLUMN state TEXT NOT NULL DEFAULT 'pending'",
            [],
        );
        Ok(Self {
            connection: Mutex::new(connection),
        })
    }

    pub fn claim_outbound(&self, limit: usize) -> anyhow::Result<Vec<QueuedEmail>> {
        let mut connection = self.connection.lock().unwrap();
        let transaction = connection.transaction()?;
        let now = Utc::now().timestamp();
        let mut statement = transaction.prepare(
            "SELECT event_id,payload FROM email_outbox
             WHERE (state IN ('pending','failed') AND created_at <= ?1)
                OR (state='processing' AND created_at < ?3)
             ORDER BY created_at LIMIT ?2",
        )?;
        let rows = statement.query_map(params![now, limit as i64, now - 300], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;
        let selected: Vec<(String, String)> = rows.collect::<Result<_, _>>()?;
        drop(statement);
        for (event_id, _) in &selected {
            transaction.execute(
                "UPDATE email_outbox SET state='processing',created_at=?1 WHERE event_id=?2",
                params![now, event_id],
            )?;
        }
        transaction.commit()?;
        selected
            .into_iter()
            .map(|(_, payload)| Ok(serde_json::from_str(&payload)?))
            .collect()
    }

    pub fn mark_outbound_sent(&self, event_id: &str) -> anyhow::Result<()> {
        self.connection.lock().unwrap().execute(
            "UPDATE email_outbox SET state='sent' WHERE event_id=?1",
            params![event_id],
        )?;
        Ok(())
    }

    pub fn mark_outbound_failed(&self, event_id: &str) -> anyhow::Result<()> {
        self.connection.lock().unwrap().execute(
            "UPDATE email_outbox
             SET state='failed',attempts=attempts+1,
                 created_at=strftime('%s','now') + MIN(3600, 30 * (1 << MIN(attempts, 7)))
             WHERE event_id=?1",
            params![event_id],
        )?;
        Ok(())
    }

    fn decode_thread(row: &rusqlite::Row<'_>) -> rusqlite::Result<EmailThread> {
        let recipients: String = row.get(4)?;
        Ok(EmailThread {
            id: row.get(0)?,
            performer_id: row.get(1)?,
            performer_username: row.get(2)?,
            venue_id: row.get(3)?,
            recipients: serde_json::from_str(&recipients).unwrap_or_default(),
            subject: row.get(5)?,
            latest_message_id: row.get(6)?,
        })
    }
}

#[async_trait]
impl MailStore for SqliteMailStore {
    async fn upsert_thread(&self, thread: EmailThread) -> anyhow::Result<()> {
        self.connection.lock().unwrap().execute(
            "INSERT INTO email_threads VALUES (?1,?2,?3,?4,?5,?6,?7)
             ON CONFLICT(id) DO UPDATE SET performer_id=excluded.performer_id,
             performer_username=excluded.performer_username, venue_id=excluded.venue_id,
             recipients=excluded.recipients, subject=excluded.subject, latest_message_id=excluded.latest_message_id",
            params![thread.id, thread.performer_id, thread.performer_username, thread.venue_id,
                serde_json::to_string(&thread.recipients)?, thread.subject, thread.latest_message_id],
        )?;
        Ok(())
    }

    async fn create_thread_and_enqueue(
        &self,
        thread: EmailThread,
        email: QueuedEmail,
    ) -> anyhow::Result<bool> {
        let mut connection = self.connection.lock().unwrap();
        let transaction = connection.transaction()?;
        let owner = transaction
            .query_row(
                "SELECT performer_id FROM email_threads WHERE id=?1",
                params![thread.id],
                |row| row.get::<_, String>(0),
            )
            .optional()?;
        if owner.is_some_and(|performer_id| performer_id != thread.performer_id) {
            anyhow::bail!("email thread belongs to another performer");
        }
        transaction.execute(
            "INSERT INTO email_threads VALUES (?1,?2,?3,?4,?5,?6,?7)
             ON CONFLICT(id) DO UPDATE SET performer_id=excluded.performer_id,
             performer_username=excluded.performer_username, venue_id=excluded.venue_id,
             recipients=excluded.recipients, subject=excluded.subject, latest_message_id=excluded.latest_message_id",
            params![thread.id, thread.performer_id, thread.performer_username, thread.venue_id,
                serde_json::to_string(&thread.recipients)?, thread.subject, thread.latest_message_id],
        )?;
        let inserted = transaction.execute(
            "INSERT OR IGNORE INTO email_outbox(event_id,thread_id,payload,created_at) VALUES (?1,?2,?3,?4)",
            params![email.event_id, email.thread_id, serde_json::to_string(&email)?, Utc::now().timestamp()],
        )? == 1;
        transaction.commit()?;
        Ok(inserted)
    }

    async fn thread_for_stream(
        &self,
        performer_id: &str,
        venue_id: &str,
    ) -> anyhow::Result<Option<EmailThread>> {
        let connection = self.connection.lock().unwrap();
        Ok(connection.query_row(
            "SELECT id,performer_id,performer_username,venue_id,recipients,subject,latest_message_id
             FROM email_threads WHERE performer_id=?1 AND venue_id=?2",
            params![performer_id, venue_id], Self::decode_thread,
        ).optional()?)
    }

    async fn thread_for_reply(
        &self,
        username: &str,
        references: &[String],
    ) -> anyhow::Result<Option<EmailThread>> {
        let connection = self.connection.lock().unwrap();
        for reference in references {
            let found = connection.query_row(
                "SELECT id,performer_id,performer_username,venue_id,recipients,subject,latest_message_id
                 FROM email_threads WHERE lower(performer_username)=lower(?1) AND latest_message_id=?2",
                params![username, reference], Self::decode_thread,
            ).optional()?;
            if found.is_some() {
                return Ok(found);
            }
            let historic = connection.query_row(
                "SELECT t.id,t.performer_id,t.performer_username,t.venue_id,t.recipients,t.subject,t.latest_message_id
                 FROM email_threads t
                 WHERE lower(t.performer_username)=lower(?1) AND (
                   EXISTS (SELECT 1 FROM inbound_emails i WHERE i.thread_id=t.id AND i.message_id=?2)
                   OR EXISTS (SELECT 1 FROM email_outbox o WHERE o.thread_id=t.id AND json_extract(o.payload,'$.message_id')=?2)
                 ) LIMIT 1",
                params![username, reference], Self::decode_thread,
            ).optional()?;
            if historic.is_some() {
                return Ok(historic);
            }
        }
        Ok(None)
    }

    async fn enqueue_outbound(&self, email: QueuedEmail) -> anyhow::Result<bool> {
        let mut connection = self.connection.lock().unwrap();
        let transaction = connection.transaction()?;
        let inserted = transaction.execute(
            "INSERT OR IGNORE INTO email_outbox(event_id,thread_id,payload,created_at) VALUES (?1,?2,?3,?4)",
            params![email.event_id, email.thread_id, serde_json::to_string(&email)?, Utc::now().timestamp()],
        )? == 1;
        if inserted {
            transaction.execute(
                "UPDATE email_threads SET latest_message_id=?1 WHERE id=?2",
                params![email.message_id, email.thread_id],
            )?;
        }
        transaction.commit()?;
        Ok(inserted)
    }

    async fn claim_inbound(
        &self,
        message_id: &str,
        raw: &[u8],
        delivery: &StreamDelivery,
    ) -> anyhow::Result<bool> {
        let mut connection = self.connection.lock().unwrap();
        let transaction = connection.transaction()?;
        transaction.execute(
            "INSERT OR IGNORE INTO inbound_emails(message_id,thread_id,raw,delivery,state,created_at) VALUES (?1,?2,?3,?4,'pending',?5)",
            params![message_id, delivery.thread_id, raw, serde_json::to_string(delivery)?, Utc::now().timestamp()],
        )?;
        let claimed = transaction.execute(
            "UPDATE inbound_emails SET state='processing',created_at=?1
             WHERE message_id=?2 AND (state IN ('pending','failed') OR (state='processing' AND created_at < ?3))",
            params![Utc::now().timestamp(), message_id, Utc::now().timestamp() - 300],
        )? == 1;
        transaction.commit()?;
        Ok(claimed)
    }

    async fn mark_inbound_delivered(&self, message_id: &str) -> anyhow::Result<()> {
        self.connection.lock().unwrap().execute(
            "UPDATE inbound_emails SET state='delivered' WHERE message_id=?1",
            params![message_id],
        )?;
        Ok(())
    }

    async fn mark_inbound_failed(&self, message_id: &str) -> anyhow::Result<()> {
        self.connection.lock().unwrap().execute(
            "UPDATE inbound_emails SET state='failed' WHERE message_id=?1",
            params![message_id],
        )?;
        Ok(())
    }

    async fn record_orphan(&self, raw: &[u8], reason: &str) -> anyhow::Result<()> {
        self.connection.lock().unwrap().execute(
            "INSERT INTO orphan_emails(raw,reason,created_at) VALUES (?1,?2,?3)",
            params![raw, reason, Utc::now().timestamp()],
        )?;
        Ok(())
    }

    async fn update_latest_message_id(
        &self,
        thread_id: &str,
        message_id: &str,
    ) -> anyhow::Result<()> {
        self.connection.lock().unwrap().execute(
            "UPDATE email_threads SET latest_message_id=?1 WHERE id=?2",
            params![message_id, thread_id],
        )?;
        Ok(())
    }
}

pub struct StreamHttpGateway {
    client: reqwest::Client,
    api_key: String,
    server_token: String,
    base_url: String,
}

impl StreamHttpGateway {
    pub fn new(api_key: String, secret: &str) -> anyhow::Result<Self> {
        let server_token = jsonwebtoken::encode(
            &jsonwebtoken::Header::new(jsonwebtoken::Algorithm::HS256),
            &serde_json::json!({ "server": true }),
            &jsonwebtoken::EncodingKey::from_secret(secret.as_bytes()),
        )?;
        Ok(Self {
            client: reqwest::Client::new(),
            api_key,
            server_token,
            base_url: "https://chat.stream-io-api.com".into(),
        })
    }
}

#[async_trait]
impl StreamGateway for StreamHttpGateway {
    async fn send_message(&self, delivery: &StreamDelivery) -> anyhow::Result<()> {
        let query = self.client.post(format!("{}/channels/messaging/query", self.base_url))
            .query(&[("api_key", &self.api_key)])
            .header("Authorization", &self.server_token)
            .json(&serde_json::json!({
                "data": { "members": [delivery.sender_id.clone(), delivery.receiver_id.clone()], "created_by_id": delivery.sender_id },
                "state": true,
            }))
            .send().await?.error_for_status()?;
        let response: serde_json::Value = query.json().await?;
        let channel_id = response
            .pointer("/channel/id")
            .and_then(|value| value.as_str())
            .or_else(|| {
                response
                    .pointer("/channels/0/channel/id")
                    .and_then(|value| value.as_str())
            })
            .ok_or_else(|| anyhow::anyhow!("Stream did not return a channel id"))?;
        self.client.post(format!("{}/channels/messaging/{}/message", self.base_url, channel_id))
            .query(&[("api_key", &self.api_key)])
            .header("Authorization", &self.server_token)
            .json(&serde_json::json!({ "message": { "text": delivery.text, "user_id": delivery.sender_id } }))
            .send().await?.error_for_status()?;
        Ok(())
    }
}

pub struct NoopStreamGateway;
#[async_trait]
impl StreamGateway for NoopStreamGateway {
    async fn send_message(&self, _delivery: &StreamDelivery) -> anyhow::Result<()> {
        Ok(())
    }
}

#[derive(Debug, Deserialize)]
pub struct StreamUser {
    pub id: String,
    pub username: Option<String>,
}
#[derive(Debug, Deserialize)]
pub struct StreamMember {
    pub user: StreamUser,
}
#[derive(Debug, Deserialize)]
pub struct StreamAttachment {
    pub image_url: Option<String>,
}
#[derive(Debug, Deserialize)]
pub struct StreamMessage {
    pub id: String,
    pub text: Option<String>,
    #[serde(default)]
    pub attachments: Vec<StreamAttachment>,
}
#[derive(Debug, Deserialize)]
pub struct StreamWebhook {
    pub user: StreamUser,
    pub message: StreamMessage,
    pub members: Vec<StreamMember>,
}

fn valid_signature(secret: &str, content: &[u8], provided: &str) -> bool {
    let Ok(mut mac) = HmacSha256::new_from_slice(secret.as_bytes()) else {
        return false;
    };
    mac.update(content);
    let Ok(signature) = hex::decode(provided) else {
        return false;
    };
    mac.verify_slice(&signature).is_ok()
}

pub async fn stream_before_message(
    State(state): State<AppStateDyn>,
    headers: HeaderMap,
    body: Bytes,
) -> impl IntoResponse {
    let signature = headers
        .get("x-signature")
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();
    if !valid_signature(&state.mail.stream_webhook_secret, &body, signature) {
        return (StatusCode::UNAUTHORIZED, "invalid signature");
    }
    let payload: StreamWebhook = match serde_json::from_slice(&body) {
        Ok(payload) => payload,
        Err(_) => return (StatusCode::BAD_REQUEST, "invalid payload"),
    };
    let Some(receiver) = payload
        .members
        .iter()
        .find(|member| member.user.id != payload.user.id)
    else {
        return (StatusCode::BAD_REQUEST, "receiver not found");
    };
    let Some(text) = payload.message.text.filter(|text| !text.trim().is_empty()) else {
        return (StatusCode::BAD_REQUEST, "message text required");
    };
    let thread = match state
        .mail
        .store
        .thread_for_stream(&payload.user.id, &receiver.user.id)
        .await
    {
        Ok(Some(thread)) => thread,
        Ok(None) => return (StatusCode::OK, "no email thread"),
        Err(_) => return (StatusCode::INTERNAL_SERVER_ERROR, "store error"),
    };
    let message_id = format!("<{}@{}>", Uuid::new_v4(), state.mail.booking_domain);
    let email = QueuedEmail {
        event_id: format!("stream:{}", payload.message.id),
        thread_id: thread.id,
        from: format!(
            "{}@{}",
            thread.performer_username, state.mail.booking_domain
        ),
        to: thread.recipients,
        subject: thread.subject,
        text_body: text,
        html_body: None,
        message_id,
        in_reply_to: thread.latest_message_id.clone(),
        references: thread.latest_message_id,
        attachments: payload
            .message
            .attachments
            .into_iter()
            .filter_map(|item| item.image_url)
            .collect(),
        encoded_attachments: vec![],
    };
    match state.mail.store.enqueue_outbound(email).await {
        Ok(_) => (StatusCode::OK, "ok"),
        Err(_) => (StatusCode::INTERNAL_SERVER_ERROR, "store error"),
    }
}

fn header_values(parsed: &mailparse::ParsedMail<'_>, name: &str) -> Vec<String> {
    parsed
        .headers
        .iter()
        .filter(|header| header.get_key_ref().eq_ignore_ascii_case(name))
        .flat_map(|header| {
            header
                .get_value()
                .split_whitespace()
                .map(str::to_owned)
                .collect::<Vec<_>>()
        })
        .collect()
}

fn plain_body(parsed: &mailparse::ParsedMail<'_>) -> String {
    if parsed.subparts.is_empty() {
        return parsed.get_body().unwrap_or_default();
    }
    parsed
        .subparts
        .iter()
        .find(|part| part.ctype.mimetype == "text/plain")
        .map(plain_body)
        .unwrap_or_default()
}

pub async fn inbound_email(
    State(state): State<AppStateDyn>,
    headers: HeaderMap,
    body: Bytes,
) -> impl IntoResponse {
    let timestamp = headers
        .get("x-tapped-timestamp")
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();
    let signature = headers
        .get("x-tapped-signature")
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();
    let Ok(timestamp_number) = timestamp.parse::<i64>() else {
        return (StatusCode::UNAUTHORIZED, "invalid timestamp");
    };
    if (Utc::now().timestamp() - timestamp_number).abs() > 300 {
        return (StatusCode::UNAUTHORIZED, "expired signature");
    }
    let envelope_to = headers
        .get("x-tapped-envelope-to")
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();
    let signed = [
        timestamp.as_bytes(),
        b".",
        envelope_to.as_bytes(),
        b".",
        &body,
    ]
    .concat();
    if !valid_signature(&state.mail.ingress_secret, &signed, signature) {
        return (StatusCode::UNAUTHORIZED, "invalid signature");
    }
    let parsed = match parse_mail(&body) {
        Ok(parsed) => parsed,
        Err(_) => {
            let _ = state.mail.store.record_orphan(&body, "invalid email").await;
            return (StatusCode::BAD_REQUEST, "invalid email");
        }
    };
    let to = (!envelope_to.is_empty())
        .then(|| envelope_to.to_owned())
        .or_else(|| parsed.headers.get_first_value("To"))
        .unwrap_or_default();
    let username = to
        .split('@')
        .next()
        .unwrap_or_default()
        .trim()
        .trim_matches('<');
    let message_id = parsed
        .headers
        .get_first_value("Message-ID")
        .unwrap_or_default();
    let mut references = header_values(&parsed, "In-Reply-To");
    references.extend(header_values(&parsed, "References"));
    if username.is_empty() || message_id.is_empty() || references.is_empty() {
        let _ = state
            .mail
            .store
            .record_orphan(&body, "missing routing headers")
            .await;
        return (StatusCode::UNPROCESSABLE_ENTITY, "missing routing headers");
    }
    let thread = match state
        .mail
        .store
        .thread_for_reply(username, &references)
        .await
    {
        Ok(Some(thread)) => thread,
        Ok(None) => {
            let _ = state
                .mail
                .store
                .record_orphan(&body, "thread not found")
                .await;
            return (StatusCode::NOT_FOUND, "thread not found");
        }
        Err(_) => return (StatusCode::INTERNAL_SERVER_ERROR, "store error"),
    };
    let delivery = StreamDelivery {
        event_id: format!("email:{message_id}"),
        thread_id: thread.id.clone(),
        sender_id: thread.venue_id,
        receiver_id: thread.performer_id,
        text: plain_body(&parsed).trim().to_owned(),
    };
    let is_new = match state
        .mail
        .store
        .claim_inbound(&message_id, &body, &delivery)
        .await
    {
        Ok(is_new) => is_new,
        Err(_) => return (StatusCode::INTERNAL_SERVER_ERROR, "store error"),
    };
    if is_new {
        if state.mail.stream.send_message(&delivery).await.is_err() {
            let _ = state.mail.store.mark_inbound_failed(&message_id).await;
            return (StatusCode::SERVICE_UNAVAILABLE, "stream unavailable");
        }
        if state
            .mail
            .store
            .mark_inbound_delivered(&message_id)
            .await
            .is_err()
        {
            return (StatusCode::INTERNAL_SERVER_ERROR, "store error");
        }
        if state
            .mail
            .store
            .update_latest_message_id(&thread.id, &message_id)
            .await
            .is_err()
        {
            return (StatusCode::INTERNAL_SERVER_ERROR, "store error");
        }
    }
    (StatusCode::OK, "ok")
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct ServiceEmail {
    pub from: String,
    pub to: String,
    #[serde(default)]
    pub cc: Option<String>,
    pub subject: String,
    #[serde(default)]
    pub text_body: Option<String>,
    #[serde(default)]
    pub html_body: Option<String>,
    #[serde(default)]
    pub headers: Vec<ServiceEmailHeader>,
    #[serde(default)]
    pub attachments: Vec<ServiceEmailAttachment>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct ServiceEmailHeader {
    pub name: String,
    pub value: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct ServiceEmailAttachment {
    pub name: String,
    pub content_type: String,
    pub content: String,
}

pub async fn enqueue_service_email(
    State(state): State<AppStateDyn>,
    headers: HeaderMap,
    body: Bytes,
) -> impl IntoResponse {
    let timestamp = headers
        .get("x-tapped-timestamp")
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();
    let signature = headers
        .get("x-tapped-signature")
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();
    let Ok(timestamp_number) = timestamp.parse::<i64>() else {
        return StatusCode::UNAUTHORIZED;
    };
    if (Utc::now().timestamp() - timestamp_number).abs() > 300 {
        return StatusCode::UNAUTHORIZED;
    }
    let signed = [timestamp.as_bytes(), b".", b"", b".", &body].concat();
    if !valid_signature(&state.mail.service_secret, &signed, signature) {
        return StatusCode::UNAUTHORIZED;
    }
    let message: ServiceEmail = match serde_json::from_slice(&body) {
        Ok(message) => message,
        Err(_) => return StatusCode::BAD_REQUEST,
    };
    let message_id = message
        .headers
        .iter()
        .find(|header| header.name.eq_ignore_ascii_case("Message-ID"))
        .map(|header| header.value.clone())
        .unwrap_or_else(|| format!("<{}@{}>", Uuid::new_v4(), state.mail.booking_domain));
    let in_reply_to = message
        .headers
        .iter()
        .find(|header| header.name.eq_ignore_ascii_case("In-Reply-To"))
        .map(|header| header.value.clone())
        .unwrap_or_default();
    let references = message
        .headers
        .iter()
        .find(|header| header.name.eq_ignore_ascii_case("References"))
        .map(|header| header.value.clone())
        .unwrap_or_default();
    let mut recipients = message
        .to
        .split(',')
        .map(str::trim)
        .filter(|item| !item.is_empty())
        .map(str::to_owned)
        .collect::<Vec<_>>();
    if let Some(cc) = message.cc {
        recipients.extend(
            cc.split(',')
                .map(str::trim)
                .filter(|item| !item.is_empty())
                .map(str::to_owned),
        );
    }
    if recipients.is_empty() || message.from.is_empty() || message.subject.is_empty() {
        return StatusCode::BAD_REQUEST;
    }
    let queued = QueuedEmail {
        event_id: format!("service:{message_id}"),
        thread_id: format!("service:{message_id}"),
        from: message.from,
        to: recipients,
        subject: message.subject,
        text_body: message.text_body.unwrap_or_default(),
        html_body: message.html_body,
        message_id,
        in_reply_to,
        references,
        attachments: vec![],
        encoded_attachments: message
            .attachments
            .into_iter()
            .map(|attachment| EncodedAttachment {
                name: attachment.name,
                content_type: attachment.content_type,
                content: attachment.content,
            })
            .collect(),
    };
    match state.mail.store.enqueue_outbound(queued).await {
        Ok(_) => StatusCode::ACCEPTED,
        Err(_) => StatusCode::INTERNAL_SERVER_ERROR,
    }
}

#[derive(Debug, Deserialize)]
pub struct CreateEmailThread {
    pub id: String,
    pub venue_id: String,
    pub subject: String,
    pub text_body: String,
}

pub async fn create_email_thread(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Json(command): Json<CreateEmailThread>,
) -> impl IntoResponse {
    let performer = match state.database.get_user_by_id(&user.uid).await {
        Ok(performer) if !performer.username.is_empty() => performer,
        Ok(_) => return StatusCode::BAD_REQUEST,
        Err(_) => return StatusCode::NOT_FOUND,
    };
    let venue = match state.database.get_user_by_id(&command.venue_id).await {
        Ok(venue) => venue,
        Err(_) => return StatusCode::NOT_FOUND,
    };
    let Some(recipient) = venue.booking_email().map(str::to_owned) else {
        return StatusCode::BAD_REQUEST;
    };
    let recipients = vec![recipient];
    let message_id = format!("<{}@{}>", Uuid::new_v4(), state.mail.booking_domain);
    let thread = EmailThread {
        id: command.id.clone(),
        performer_id: user.uid,
        performer_username: performer.username.clone(),
        venue_id: command.venue_id,
        recipients: recipients.clone(),
        subject: command.subject.clone(),
        latest_message_id: message_id.clone(),
    };
    let email = QueuedEmail {
        event_id: format!("venue-contact:{}", command.id),
        thread_id: command.id,
        from: format!("{}@{}", performer.username, state.mail.booking_domain),
        to: recipients,
        subject: command.subject,
        text_body: command.text_body,
        html_body: None,
        message_id,
        in_reply_to: String::new(),
        references: String::new(),
        attachments: vec![],
        encoded_attachments: vec![],
    };
    match state
        .mail
        .store
        .create_thread_and_enqueue(thread, email)
        .await
    {
        Ok(_) => StatusCode::ACCEPTED,
        Err(_) => StatusCode::INTERNAL_SERVER_ERROR,
    }
}
