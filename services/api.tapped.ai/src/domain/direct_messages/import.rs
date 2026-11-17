//! One-off Stream Chat → Postgres import (`dm_import` binary). Idempotent and resumable: channels
//! upsert on `legacy_stream_cid` (or the member pair), messages on `legacy_stream_id`, and read
//! cursors only move forward, so the same command runs once before launch and again as the final
//! delta after Stream writes stop. Each channel commits in its own transaction.
use anyhow::{Context, Result, anyhow, ensure};
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sqlx::PgPool;
use std::collections::{BTreeMap, HashSet};
use uuid::Uuid;

use super::store::{self, Attachment, MAX_MESSAGE_CHARS, NewMessage, PostOptions};

#[derive(Debug, Clone, Deserialize)]
pub struct StreamUserRef {
    pub id: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct StreamChannelInfo {
    pub cid: String,
    pub created_at: DateTime<Utc>,
    #[serde(default)]
    pub created_by: Option<StreamUserRef>,
    #[serde(default)]
    pub frozen: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct StreamMemberRef {
    #[serde(default)]
    pub user_id: Option<String>,
    #[serde(default)]
    pub user: Option<StreamUserRef>,
}

impl StreamMemberRef {
    fn id(&self) -> Option<&str> {
        self.user_id
            .as_deref()
            .or(self.user.as_ref().map(|user| user.id.as_str()))
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct StreamRead {
    pub user: StreamUserRef,
    pub last_read: DateTime<Utc>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct StreamAttachment {
    #[serde(default, rename = "type")]
    pub kind: Option<String>,
    #[serde(default)]
    pub image_url: Option<String>,
    #[serde(default)]
    pub asset_url: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct StreamMessage {
    pub id: String,
    #[serde(default)]
    pub text: String,
    #[serde(default, rename = "type")]
    pub kind: String,
    pub user: StreamUserRef,
    pub created_at: DateTime<Utc>,
    #[serde(default)]
    pub deleted_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub attachments: Vec<StreamAttachment>,
    #[serde(default)]
    pub show_in_channel: Option<bool>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct StreamChannelState {
    pub channel: StreamChannelInfo,
    #[serde(default)]
    pub members: Vec<StreamMemberRef>,
    #[serde(default)]
    pub read: Vec<StreamRead>,
}

/// The read-only slice of Stream's server API the import needs.
#[async_trait]
pub trait StreamSource: Send + Sync {
    /// Messaging channels created at or after `since`, oldest first.
    async fn channels(
        &self,
        since: Option<DateTime<Utc>>,
        limit: usize,
    ) -> Result<Vec<StreamChannelState>>;
    /// A page of the channel's messages before `before_id` (newest page when `None`), oldest first.
    async fn messages(
        &self,
        cid: &str,
        before_id: Option<&str>,
        limit: usize,
    ) -> Result<Vec<StreamMessage>>;
}

pub struct StreamHttpSource {
    client: reqwest::Client,
    api_key: String,
    secret: String,
    base_url: String,
}

impl StreamHttpSource {
    pub fn new(api_key: String, secret: String, base_url: String) -> Self {
        Self {
            client: crate::http::client(),
            api_key,
            secret,
            base_url: base_url.trim_end_matches('/').to_owned(),
        }
    }

    async fn post(&self, path: &str, body: Value) -> Result<Value> {
        let now = Utc::now().timestamp();
        let token = jsonwebtoken::encode(
            &jsonwebtoken::Header::new(jsonwebtoken::Algorithm::HS256),
            &json!({"server": true, "iat": now, "exp": now + 300}),
            &jsonwebtoken::EncodingKey::from_secret(self.secret.as_bytes()),
        )?;
        for attempt in 0..6u32 {
            let response = self
                .client
                .post(format!("{}{path}", self.base_url))
                .query(&[("api_key", &self.api_key)])
                .header("Authorization", &token)
                .header("Stream-Auth-Type", "jwt")
                .json(&body)
                .send()
                .await
                .map_err(|_| anyhow!("Stream network error"))?;
            let status = response.status();
            // Stream rate limits per endpoint; back off and retry instead of failing the run.
            if status.as_u16() == 429 || status.is_server_error() {
                tokio::time::sleep(std::time::Duration::from_secs(2u64.pow(attempt))).await;
                continue;
            }
            ensure!(
                status.is_success(),
                "Stream {path} HTTP {}",
                status.as_u16()
            );
            return Ok(response.json().await?);
        }
        Err(anyhow!("Stream {path} kept failing"))
    }
}

#[async_trait]
impl StreamSource for StreamHttpSource {
    async fn channels(
        &self,
        since: Option<DateTime<Utc>>,
        limit: usize,
    ) -> Result<Vec<StreamChannelState>> {
        let mut filter = json!({"type": "messaging"});
        if let Some(since) = since {
            filter["created_at"] = json!({"$gte": since.to_rfc3339()});
        }
        let response = self
            .post(
                "/channels",
                json!({
                    "filter_conditions": filter,
                    "sort": [{"field": "created_at", "direction": 1}],
                    "limit": limit, "state": true, "watch": false, "presence": false,
                    "message_limit": 0, "member_limit": 100,
                }),
            )
            .await?;
        Ok(serde_json::from_value(response["channels"].clone()).context("Stream channels")?)
    }

    async fn messages(
        &self,
        cid: &str,
        before_id: Option<&str>,
        limit: usize,
    ) -> Result<Vec<StreamMessage>> {
        let (kind, id) = cid.split_once(':').ok_or_else(|| anyhow!("invalid cid"))?;
        let mut page = json!({"limit": limit});
        if let Some(before_id) = before_id {
            page["id_lt"] = json!(before_id);
        }
        let response = self
            .post(
                &format!("/channels/{kind}/{id}/query"),
                json!({"state": true, "watch": false, "presence": false, "messages": page}),
            )
            .await?;
        Ok(serde_json::from_value(response["messages"].clone()).context("Stream messages")?)
    }
}

#[derive(Debug, Default, Clone, PartialEq, Serialize)]
pub struct ImportStats {
    pub channels_seen: usize,
    pub channels_imported: usize,
    /// Reason → count (unknown members, group channels, …).
    pub channels_skipped: BTreeMap<String, usize>,
    pub messages_imported: usize,
    /// Already imported by a previous run.
    pub messages_existing: usize,
    /// Reason → count (deleted, system, unknown author, …).
    pub messages_skipped: BTreeMap<String, usize>,
}

impl ImportStats {
    fn skip_channel(&mut self, reason: &str) {
        *self.channels_skipped.entry(reason.into()).or_default() += 1;
    }
    fn skip_message(&mut self, reason: &str) {
        *self.messages_skipped.entry(reason.into()).or_default() += 1;
    }
}

const CHANNEL_PAGE: usize = 30;
const MESSAGE_PAGE: usize = 300;

/// Imports every messaging channel. `dry_run` rolls each channel back after importing it.
pub async fn run(pool: &PgPool, source: &dyn StreamSource, dry_run: bool) -> Result<ImportStats> {
    let mut stats = ImportStats::default();
    let mut since: Option<DateTime<Utc>> = None;
    // Channels at the `since` boundary, which `$gte` returns again on the next page.
    let mut boundary: HashSet<String> = HashSet::new();
    loop {
        let page = source.channels(since, CHANNEL_PAGE).await?;
        let fresh: Vec<_> = page
            .iter()
            .filter(|channel| !boundary.contains(&channel.channel.cid))
            .cloned()
            .collect();
        if fresh.is_empty() {
            break;
        }
        for channel in &fresh {
            stats.channels_seen += 1;
            import_channel(pool, source, channel, dry_run, &mut stats)
                .await
                .with_context(|| format!("importing {}", channel.channel.cid))?;
        }
        let newest = fresh.iter().map(|channel| channel.channel.created_at).max();
        if newest != since {
            boundary.clear();
        }
        since = newest;
        boundary.extend(
            fresh
                .iter()
                .filter(|channel| Some(channel.channel.created_at) == since)
                .map(|channel| channel.channel.cid.clone()),
        );
        if page.len() < CHANNEL_PAGE {
            break;
        }
    }
    Ok(stats)
}

/// Deterministic per Stream message, so every run (and a dry run) agrees on IDs.
pub fn legacy_message_id(stream_id: &str) -> Uuid {
    use sha2::{Digest, Sha256};
    let digest = Sha256::digest(format!("stream-message:{stream_id}").as_bytes());
    let mut bytes = [0u8; 16];
    bytes.copy_from_slice(&digest[..16]);
    uuid::Builder::from_random_bytes(bytes).into_uuid()
}

fn attachments(message: &StreamMessage) -> Vec<Attachment> {
    message
        .attachments
        .iter()
        .filter_map(|attachment| {
            let url = attachment
                .image_url
                .clone()
                .or(attachment.asset_url.clone())?;
            url.starts_with("https://").then(|| Attachment {
                kind: match attachment.kind.as_deref() {
                    Some("image") | None => "image".into(),
                    Some(other) => other.into(),
                },
                url,
            })
        })
        .collect()
}

async fn import_channel(
    pool: &PgPool,
    source: &dyn StreamSource,
    channel: &StreamChannelState,
    dry_run: bool,
    stats: &mut ImportStats,
) -> Result<()> {
    let cid = &channel.channel.cid;
    let mut member_ids: Vec<String> = channel
        .members
        .iter()
        .filter_map(|member| member.id().map(str::to_owned))
        .collect();
    member_ids.sort();
    member_ids.dedup();
    if member_ids.len() != 2 {
        stats.skip_channel(if member_ids.len() > 2 {
            "group"
        } else {
            "single_member"
        });
        return Ok(());
    }
    let known: Vec<String> = sqlx::query_scalar("SELECT id FROM users WHERE id=ANY($1)")
        .bind(&member_ids)
        .fetch_all(pool)
        .await?;
    if known.len() != 2 {
        stats.skip_channel("unknown_member");
        return Ok(());
    }

    // Newest page first, then older pages; Stream returns each page oldest first.
    let mut history: Vec<StreamMessage> = vec![];
    let mut before: Option<String> = None;
    loop {
        let page = source
            .messages(cid, before.as_deref(), MESSAGE_PAGE)
            .await?;
        let Some(oldest) = page.first() else { break };
        before = Some(oldest.id.clone());
        let full = page.len() >= MESSAGE_PAGE;
        history.splice(0..0, page);
        if !full {
            break;
        }
    }
    history.sort_by(|a, b| {
        a.created_at
            .cmp(&b.created_at)
            .then_with(|| a.id.cmp(&b.id))
    });

    let mut tx = pool.begin().await?;
    let (low, high) = (&member_ids[0], &member_ids[1]);
    let existing: Option<Uuid> = sqlx::query_scalar(
        "SELECT id FROM conversations
         WHERE legacy_stream_cid=$1 OR (direct_low=$2 AND direct_high=$3)
         ORDER BY legacy_stream_cid IS NOT DISTINCT FROM $1 DESC LIMIT 1",
    )
    .bind(cid)
    .bind(low)
    .bind(high)
    .fetch_optional(&mut *tx)
    .await?;
    let conversation_id = match existing {
        Some(id) => {
            sqlx::query(
                "UPDATE conversations SET legacy_stream_cid=coalesce(legacy_stream_cid,$2)
                 WHERE id=$1 AND NOT EXISTS(SELECT 1 FROM conversations WHERE legacy_stream_cid=$2)",
            )
            .bind(id)
            .bind(cid)
            .execute(&mut *tx)
            .await?;
            id
        }
        None => {
            let id = Uuid::new_v4();
            let creator = channel
                .channel
                .created_by
                .as_ref()
                .map(|user| user.id.clone())
                .filter(|creator| member_ids.contains(creator))
                .unwrap_or_else(|| low.clone());
            sqlx::query(
                "INSERT INTO conversations(id,direct_low,direct_high,created_by,created_at,frozen,legacy_stream_cid)
                 VALUES($1,$2,$3,$4,$5,$6,$7)",
            )
            .bind(id)
            .bind(low)
            .bind(high)
            .bind(&creator)
            .bind(channel.channel.created_at)
            .bind(channel.channel.frozen)
            .bind(cid)
            .execute(&mut *tx)
            .await?;
            sqlx::query(
                "INSERT INTO conversation_members(conversation_id,user_id,joined_at,sort_at)
                 VALUES($1,$2,$4,$4),($1,$3,$4,$4) ON CONFLICT DO NOTHING",
            )
            .bind(id)
            .bind(low)
            .bind(high)
            .bind(channel.channel.created_at)
            .execute(&mut *tx)
            .await?;
            id
        }
    };

    let ids: Vec<String> = history.iter().map(|message| message.id.clone()).collect();
    let already: HashSet<String> =
        sqlx::query_scalar("SELECT legacy_stream_id FROM messages WHERE legacy_stream_id=ANY($1)")
            .bind(&ids)
            .fetch_all(&mut *tx)
            .await?
            .into_iter()
            .collect();
    for message in &history {
        if already.contains(&message.id) {
            stats.messages_existing += 1;
            continue;
        }
        let visible_reply = message.kind == "reply" && message.show_in_channel == Some(true);
        if message.deleted_at.is_some() || message.kind == "deleted" {
            stats.skip_message("deleted");
            continue;
        }
        if message.kind != "regular" && !visible_reply {
            stats.skip_message(if message.kind == "reply" {
                "thread_reply"
            } else {
                "system"
            });
            continue;
        }
        if !member_ids.contains(&message.user.id) {
            stats.skip_message("non_member_author");
            continue;
        }
        let attachments = attachments(message);
        let text: String = message.text.chars().take(MAX_MESSAGE_CHARS).collect();
        if text.trim().is_empty() && attachments.is_empty() {
            stats.skip_message("empty");
            continue;
        }
        store::post(
            &mut tx,
            &NewMessage {
                id: legacy_message_id(&message.id),
                conversation_id,
                author_id: message.user.id.clone(),
                text,
                attachments,
            },
            &PostOptions {
                enforce_frozen: false,
                set_frozen: None,
                push: false,
                created_at: Some(message.created_at),
                legacy_stream_id: Some(message.id.clone()),
                notify: false,
            },
        )
        .await
        .map_err(|error| anyhow!("{error}"))?;
        stats.messages_imported += 1;
    }

    // Read through the newest message at or before Stream's last_read; never move a cursor back.
    for read in &channel.read {
        if !member_ids.contains(&read.user.id) {
            continue;
        }
        sqlx::query(
            "UPDATE conversation_members m SET last_read_seq=greatest(m.last_read_seq,r.seq),
               last_read_at=greatest(m.last_read_at,$3)
             FROM (SELECT coalesce(max(seq),0) AS seq FROM messages
                   WHERE conversation_id=$1 AND created_at<=$3) r
             WHERE m.conversation_id=$1 AND m.user_id=$2",
        )
        .bind(conversation_id)
        .bind(&read.user.id)
        .bind(read.last_read)
        .execute(&mut *tx)
        .await?;
    }
    sqlx::query("UPDATE conversations SET frozen=$2 WHERE id=$1 AND legacy_stream_cid=$3")
        .bind(conversation_id)
        .bind(channel.channel.frozen)
        .bind(cid)
        .execute(&mut *tx)
        .await?;
    if dry_run {
        tx.rollback().await?;
    } else {
        tx.commit().await?;
    }
    stats.channels_imported += 1;
    Ok(())
}
