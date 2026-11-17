//! Postgres persistence for direct messages. Every write that clients should see live ends with a
//! `pg_notify` in the same transaction, so events are published exactly when the write commits.
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::{PgPool, Postgres, Row, Transaction, postgres::PgRow};
use utoipa::ToSchema;
use uuid::Uuid;

/// The NOTIFY channel the realtime hub listens on.
pub const NOTIFY_CHANNEL: &str = "direct_messages";
pub const MAX_MESSAGE_CHARS: usize = 5000;
pub const MAX_PAGE: i64 = 100;
/// Push bodies are previews; APNs caps the whole payload at 4 KB.
const PUSH_PREVIEW_CHARS: usize = 180;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
pub struct Attachment {
    #[serde(rename = "type")]
    pub kind: String,
    pub url: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Message {
    pub id: Uuid,
    pub conversation_id: Uuid,
    /// Gap-free per conversation; clients order by it and detect missed events with it.
    pub seq: i64,
    pub author_id: String,
    pub text: String,
    pub attachments: Vec<Attachment>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Member {
    pub id: String,
    /// Artist name, else username, else the ID.
    pub name: String,
    pub username: String,
    pub image_url: Option<String>,
    pub deleted: bool,
}

/// One conversation as seen by one member.
#[derive(Debug, Clone, PartialEq, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Conversation {
    pub id: Uuid,
    pub members: Vec<Member>,
    /// Only the server can post (e.g. an unclaimed venue that has not replied by email yet).
    pub frozen: bool,
    pub created_at: DateTime<Utc>,
    pub last_seq: i64,
    pub last_read_seq: i64,
    pub unread_count: i64,
    pub last_message: Option<Message>,
    pub last_message_at: Option<DateTime<Utc>>,
}

#[derive(Debug)]
pub enum DmError {
    NotFound,
    Frozen,
    /// A message ID reused for different content, or a recipient that can no longer receive.
    Conflict(&'static str),
    Invalid(&'static str),
    Database(sqlx::Error),
}

impl From<sqlx::Error> for DmError {
    fn from(error: sqlx::Error) -> Self {
        Self::Database(error)
    }
}

impl std::fmt::Display for DmError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotFound => f.write_str("conversation not found"),
            Self::Frozen => f.write_str("conversation is frozen"),
            Self::Conflict(reason) | Self::Invalid(reason) => f.write_str(reason),
            Self::Database(error) => write!(f, "database: {error}"),
        }
    }
}

impl std::error::Error for DmError {}

pub type DmResult<T> = Result<T, DmError>;

/// Who may post, and what a post does besides storing the message.
#[derive(Debug, Clone)]
pub struct PostOptions {
    /// Client sends respect `frozen`; server deliveries (email replies, venue mirrors) do not.
    pub enforce_frozen: bool,
    /// Server deliveries set the frozen flag as part of the post.
    pub set_frozen: Option<bool>,
    /// Push the other members' devices.
    pub push: bool,
}

impl PostOptions {
    pub fn client() -> Self {
        Self {
            enforce_frozen: true,
            set_frozen: None,
            push: true,
        }
    }

    pub fn server(frozen: bool) -> Self {
        Self {
            enforce_frozen: false,
            set_frozen: Some(frozen),
            ..Self::client()
        }
    }
}

#[derive(Debug, Clone)]
pub struct NewMessage {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub author_id: String,
    pub text: String,
    pub attachments: Vec<Attachment>,
}

#[derive(Debug, Clone)]
pub enum Posted {
    Created {
        message: Message,
        /// Members other than the author.
        recipients: Vec<String>,
    },
    /// The same message was already stored (a retried send). Nothing else happened.
    Duplicate(Message),
}

impl Posted {
    pub fn message(&self) -> &Message {
        match self {
            Self::Created { message, .. } | Self::Duplicate(message) => message,
        }
    }
}

pub fn validate_text(text: &str) -> DmResult<()> {
    validate(text, &[])
}

fn validate(text: &str, attachments: &[Attachment]) -> DmResult<()> {
    if text.trim().is_empty() && attachments.is_empty() {
        return Err(DmError::Invalid("message text must not be empty"));
    }
    if text.chars().count() > MAX_MESSAGE_CHARS {
        return Err(DmError::Invalid("message text is too long"));
    }
    Ok(())
}

pub(crate) fn decode_message(row: &PgRow) -> Result<Message, sqlx::Error> {
    let attachments: Value = row.try_get("attachments")?;
    Ok(Message {
        id: row.try_get("id")?,
        conversation_id: row.try_get("conversation_id")?,
        seq: row.try_get("seq")?,
        author_id: row.try_get("author_id")?,
        text: row.try_get("body")?,
        attachments: serde_json::from_value(attachments).unwrap_or_default(),
        created_at: row.try_get("created_at")?,
    })
}

/// Column lists as macros so every query stays a `&'static str` literal (sqlx rejects runtime SQL).
macro_rules! message_columns {
    () => {
        "id,conversation_id,seq,author_id,body,attachments,created_at"
    };
}

/// Sends `pg_notify` inside the caller's transaction; Postgres delivers it on commit only.
pub async fn notify(
    tx: &mut Transaction<'_, Postgres>,
    kind: &str,
    conversation_id: Uuid,
    seq: i64,
    users: &[String],
) -> Result<(), sqlx::Error> {
    // A 1:1 payload is ~150 bytes, far below the 8000 byte NOTIFY limit.
    let payload = json!({"k": kind, "c": conversation_id, "s": seq, "u": users}).to_string();
    sqlx::query("SELECT pg_notify($1,$2)")
        .bind(NOTIFY_CHANNEL)
        .bind(payload)
        .execute(&mut **tx)
        .await?;
    Ok(())
}

/// Returns the 1:1 conversation between `a` and `b`, creating it if needed. Idempotent under
/// concurrency: the unordered pair is unique.
pub async fn ensure_direct(
    tx: &mut Transaction<'_, Postgres>,
    creator: &str,
    other: &str,
) -> DmResult<Uuid> {
    if creator == other {
        return Err(DmError::Invalid("cannot message yourself"));
    }
    let (low, high) = if creator < other {
        (creator, other)
    } else {
        (other, creator)
    };
    let present: i64 =
        sqlx::query_scalar("SELECT count(*) FROM users WHERE id IN ($1,$2) AND NOT deleted")
            .bind(low)
            .bind(high)
            .fetch_one(&mut **tx)
            .await?;
    if present != 2 {
        return Err(DmError::NotFound);
    }
    let inserted: Option<Uuid> = sqlx::query_scalar(
        "INSERT INTO conversations(id,direct_low,direct_high,created_by) VALUES($1,$2,$3,$4)
         ON CONFLICT (direct_low,direct_high) DO NOTHING RETURNING id",
    )
    .bind(Uuid::new_v4())
    .bind(low)
    .bind(high)
    .bind(creator)
    .fetch_optional(&mut **tx)
    .await?;
    let id = match inserted {
        Some(id) => {
            sqlx::query(
                "INSERT INTO conversation_members(conversation_id,user_id) VALUES($1,$2),($1,$3)
                 ON CONFLICT DO NOTHING",
            )
            .bind(id)
            .bind(low)
            .bind(high)
            .execute(&mut **tx)
            .await?;
            id
        }
        // ON CONFLICT DO NOTHING waits for a concurrent creator to commit, so the row is visible.
        None => {
            sqlx::query_scalar(
                "SELECT id FROM conversations WHERE direct_low=$1 AND direct_high=$2",
            )
            .bind(low)
            .bind(high)
            .fetch_one(&mut **tx)
            .await?
        }
    };
    Ok(id)
}

/// Stable message ID for a server-authored message, so a retried delivery (webhook, email
/// redelivery, worker retry) is stored once.
pub fn server_message_id(key: &str) -> Uuid {
    let digest = Sha256::digest(format!("server-message:{key}").as_bytes());
    let mut bytes = [0u8; 16];
    bytes.copy_from_slice(&digest[..16]);
    uuid::Builder::from_random_bytes(bytes).into_uuid()
}

/// A message Tapped posts on someone's behalf: venue auto-replies and email mirrors, inbound
/// email replies, founder welcome messages.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ServerMessage {
    /// Idempotency key (see `server_message_id`).
    pub event_id: String,
    /// Mail-store bookkeeping only (the email thread an inbound reply belongs to).
    #[serde(default)]
    pub thread_id: String,
    pub sender_id: String,
    pub receiver_id: String,
    pub text: String,
    /// The conversation's frozen state after this message (only Tapped may post while frozen).
    #[serde(default)]
    pub frozen: bool,
}

/// Opens the pair's conversation if needed and posts `message` into it, bypassing `frozen`.
/// Text over the message limit (long email replies) is cut rather than rejected, so a redelivery
/// cannot fail forever on content.
pub async fn post_server_message(
    tx: &mut Transaction<'_, Postgres>,
    message: &ServerMessage,
) -> DmResult<Posted> {
    let conversation_id = ensure_direct(tx, &message.sender_id, &message.receiver_id).await?;
    let text = match message.text.char_indices().nth(MAX_MESSAGE_CHARS) {
        Some((cut, _)) => {
            let kept: String = message.text[..cut]
                .chars()
                .take(MAX_MESSAGE_CHARS - 1)
                .collect();
            format!("{kept}…")
        }
        None => message.text.clone(),
    };
    post(
        tx,
        &NewMessage {
            id: server_message_id(&message.event_id),
            conversation_id,
            author_id: message.sender_id.clone(),
            text,
            attachments: vec![],
        },
        &PostOptions::server(message.frozen),
    )
    .await
}

/// Stores a message. Serialized per conversation by the row lock, which makes `seq` gap-free.
pub async fn post(
    tx: &mut Transaction<'_, Postgres>,
    message: &NewMessage,
    options: &PostOptions,
) -> DmResult<Posted> {
    validate(&message.text, &message.attachments)?;
    let conversation = sqlx::query("SELECT frozen FROM conversations WHERE id=$1 FOR UPDATE")
        .bind(message.conversation_id)
        .fetch_optional(&mut **tx)
        .await?
        .ok_or(DmError::NotFound)?;
    let frozen: bool = conversation.try_get("frozen")?;
    let members: Vec<(String, bool)> = sqlx::query_as(
        "SELECT m.user_id,u.deleted FROM conversation_members m JOIN users u ON u.id=m.user_id
         WHERE m.conversation_id=$1 ORDER BY m.user_id",
    )
    .bind(message.conversation_id)
    .fetch_all(&mut **tx)
    .await?;
    if !members.iter().any(|(id, _)| id == &message.author_id) {
        return Err(DmError::NotFound);
    }
    // Checked under the conversation lock, so a concurrent retry sees the first attempt's row.
    if let Some(row) = sqlx::query(concat!(
        "SELECT ",
        message_columns!(),
        " FROM messages WHERE id=$1"
    ))
    .bind(message.id)
    .fetch_optional(&mut **tx)
    .await?
    {
        let existing = decode_message(&row)?;
        if existing.conversation_id != message.conversation_id
            || existing.author_id != message.author_id
            || existing.text != message.text
        {
            return Err(DmError::Conflict("message id already used"));
        }
        return Ok(Posted::Duplicate(existing));
    }
    if options.enforce_frozen && frozen {
        return Err(DmError::Frozen);
    }
    if options.enforce_frozen
        && members
            .iter()
            .any(|(id, deleted)| id != &message.author_id && *deleted)
    {
        return Err(DmError::Conflict("recipient is no longer on tapped"));
    }
    let row = sqlx::query(
        "UPDATE conversations SET last_seq=last_seq+1,frozen=coalesce($2,frozen)
         WHERE id=$1 RETURNING last_seq",
    )
    .bind(message.conversation_id)
    .bind(options.set_frozen)
    .fetch_one(&mut **tx)
    .await?;
    let seq: i64 = row.try_get("last_seq")?;
    let stored = decode_message(
        &sqlx::query(concat!(
            "INSERT INTO messages(id,conversation_id,seq,author_id,body,attachments)
             VALUES($1,$2,$3,$4,$5,$6) RETURNING ",
            message_columns!()
        ))
        .bind(message.id)
        .bind(message.conversation_id)
        .bind(seq)
        .bind(&message.author_id)
        .bind(&message.text)
        .bind(serde_json::to_value(&message.attachments).unwrap_or_else(|_| json!([])))
        .fetch_one(&mut **tx)
        .await?,
    )?;
    // The newest message stays the preview even if a concurrent send commits first.
    sqlx::query(
        "UPDATE conversations SET last_message_id=$2,last_message_at=$3
         WHERE id=$1 AND (last_message_at IS NULL OR last_message_at<=$3)",
    )
    .bind(message.conversation_id)
    .bind(stored.id)
    .bind(stored.created_at)
    .execute(&mut **tx)
    .await?;
    // Sending reads everything before it, so unread stays `last_seq - last_read_seq`.
    sqlx::query(
        "UPDATE conversation_members SET sort_at=greatest(sort_at,$3),
           last_read_seq=CASE WHEN user_id=$2 THEN $4 ELSE last_read_seq END,
           last_read_at=CASE WHEN user_id=$2 THEN now() ELSE last_read_at END
         WHERE conversation_id=$1",
    )
    .bind(message.conversation_id)
    .bind(&message.author_id)
    .bind(stored.created_at)
    .bind(seq)
    .execute(&mut **tx)
    .await?;
    let recipients: Vec<String> = members
        .into_iter()
        .filter(|(id, deleted)| id != &message.author_id && !deleted)
        .map(|(id, _)| id)
        .collect();
    let mut everyone = recipients.clone();
    everyone.push(message.author_id.clone());
    notify(tx, "message", message.conversation_id, seq, &everyone).await?;
    if options.push {
        enqueue_pushes(tx, &stored, &recipients).await?;
    }
    Ok(Posted::Created {
        message: stored,
        recipients,
    })
}

/// One APNs effect per recipient device, delivered by the identity worker's outbox.
async fn enqueue_pushes(
    tx: &mut Transaction<'_, Postgres>,
    message: &Message,
    recipients: &[String],
) -> Result<(), sqlx::Error> {
    if recipients.is_empty() {
        return Ok(());
    }
    let author: String = sqlx::query_scalar(
        "SELECT coalesce(nullif(artist_name,''),nullif(username,''),id) FROM users WHERE id=$1",
    )
    .bind(&message.author_id)
    .fetch_one(&mut **tx)
    .await?;
    let mut body: String = message.text.chars().take(PUSH_PREVIEW_CHARS).collect();
    if body.len() < message.text.len() {
        body.push('…');
    }
    if body.trim().is_empty() {
        body = "sent an attachment".into();
    }
    // Only APNs: legacy FCM tokens belong to builds still on Stream, and FCM data must be strings.
    let tokens: Vec<(String, String, Option<String>)> = sqlx::query_as(
        "SELECT user_id,token,apns_environment FROM device_tokens
         WHERE user_id=ANY($1) AND provider='apns'",
    )
    .bind(recipients)
    .fetch_all(&mut **tx)
    .await?;
    for (uid, token, environment) in tokens {
        let key = format!(
            "push:dm:{}:{}",
            message.id,
            hex::encode(Sha256::digest(token.as_bytes()))
        );
        crate::domain::external_effects::enqueue(
            tx,
            &key,
            "push",
            json!({
                "token": token, "provider": "apns", "environment": environment, "uid": uid,
                "title": author, "body": body,
                "conversationId": message.conversation_id, "messageId": message.id,
            }),
        )
        .await?;
    }
    Ok(())
}

macro_rules! members_json {
    () => {
        "(SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',u.id,'name',coalesce(nullif(u.artist_name,''),nullif(u.username,''),u.id),
    'username',u.username,'imageUrl',u.profile_picture,'deleted',u.deleted) ORDER BY u.id),'[]'::jsonb)
  FROM conversation_members x JOIN users u ON u.id=x.user_id WHERE x.conversation_id=c.id) AS members"
    };
}

macro_rules! summary_columns {
    () => {
        "c.id,c.frozen,c.created_at,c.last_seq,c.last_message_at,
  me.last_read_seq,me.sort_at,
  lm.id AS lm_id,lm.seq AS lm_seq,lm.author_id AS lm_author,lm.body AS lm_body,
  lm.attachments AS lm_attachments,lm.created_at AS lm_created_at"
    };
}

fn decode_summary(row: &PgRow) -> Result<Conversation, sqlx::Error> {
    let id: Uuid = row.try_get("id")?;
    let last_seq: i64 = row.try_get("last_seq")?;
    let last_read_seq: i64 = row.try_get("last_read_seq")?;
    let members: Value = row.try_get("members")?;
    let last_message = match row.try_get::<Option<Uuid>, _>("lm_id")? {
        Some(message_id) if row.try_get::<Option<String>, _>("lm_body")?.is_some() => {
            let attachments: Value = row.try_get("lm_attachments")?;
            Some(Message {
                id: message_id,
                conversation_id: id,
                seq: row.try_get("lm_seq")?,
                author_id: row.try_get("lm_author")?,
                text: row.try_get("lm_body")?,
                attachments: serde_json::from_value(attachments).unwrap_or_default(),
                created_at: row.try_get("lm_created_at")?,
            })
        }
        _ => None,
    };
    Ok(Conversation {
        id,
        members: serde_json::from_value(members).unwrap_or_default(),
        frozen: row.try_get("frozen")?,
        created_at: row.try_get("created_at")?,
        last_seq,
        last_read_seq,
        unread_count: (last_seq - last_read_seq).max(0),
        last_message,
        last_message_at: row.try_get("last_message_at")?,
    })
}

/// `before` is the previous page's last `(sort_at, id)`.
pub struct InboxPage {
    pub conversations: Vec<Conversation>,
    pub next: Option<(DateTime<Utc>, Uuid)>,
}

/// Conversations with at least one message, most recent first. One index range scan per page.
pub async fn inbox(
    pool: &PgPool,
    uid: &str,
    before: Option<(DateTime<Utc>, Uuid)>,
    limit: i64,
) -> Result<InboxPage, sqlx::Error> {
    let limit = limit.clamp(1, MAX_PAGE);
    let (before_at, before_id) = before.unzip();
    let rows = sqlx::query(concat!(
        "SELECT ",
        summary_columns!(),
        ",",
        members_json!(),
        "
         FROM conversation_members me
         JOIN conversations c ON c.id=me.conversation_id
         LEFT JOIN messages lm ON lm.id=c.last_message_id AND lm.deleted_at IS NULL
         WHERE me.user_id=$1 AND c.last_seq>0
           AND ($2::timestamptz IS NULL OR (me.sort_at,me.conversation_id)<($2,$3))
         ORDER BY me.sort_at DESC,me.conversation_id DESC LIMIT $4"
    ))
    .bind(uid)
    .bind(before_at)
    .bind(before_id)
    .bind(limit + 1)
    .fetch_all(pool)
    .await?;
    let mut conversations = Vec::with_capacity(rows.len());
    let mut cursors = Vec::with_capacity(rows.len());
    for row in &rows {
        cursors.push((row.try_get("sort_at")?, row.try_get("id")?));
        conversations.push(decode_summary(row)?);
    }
    let next = if conversations.len() as i64 > limit {
        conversations.truncate(limit as usize);
        cursors.get(limit as usize - 1).copied()
    } else {
        None
    };
    Ok(InboxPage {
        conversations,
        next,
    })
}

/// The conversation as `uid` sees it; `None` when it does not exist or `uid` is not a member.
pub async fn conversation(
    executor: impl sqlx::PgExecutor<'_>,
    uid: &str,
    id: Uuid,
) -> Result<Option<Conversation>, sqlx::Error> {
    sqlx::query(concat!(
        "SELECT ",
        summary_columns!(),
        ",",
        members_json!(),
        "
         FROM conversation_members me
         JOIN conversations c ON c.id=me.conversation_id
         LEFT JOIN messages lm ON lm.id=c.last_message_id AND lm.deleted_at IS NULL
         WHERE me.user_id=$1 AND me.conversation_id=$2"
    ))
    .bind(uid)
    .bind(id)
    .fetch_optional(executor)
    .await?
    .as_ref()
    .map(decode_summary)
    .transpose()
}

/// The other (non-deleted) members, or nothing when `uid` is not a member.
pub async fn other_members(pool: &PgPool, id: Uuid, uid: &str) -> Result<Vec<String>, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT m.user_id FROM conversation_members m JOIN users u ON u.id=m.user_id
         WHERE m.conversation_id=$1 AND m.user_id<>$2 AND NOT u.deleted
           AND EXISTS(SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2)",
    )
    .bind(id)
    .bind(uid)
    .fetch_all(pool)
    .await
}

pub async fn is_member(
    executor: impl sqlx::PgExecutor<'_>,
    uid: &str,
    id: Uuid,
) -> Result<bool, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2)",
    )
    .bind(id)
    .bind(uid)
    .fetch_one(executor)
    .await
}

pub enum Page {
    /// Up to `limit` messages before this sequence number (or the newest messages).
    Before(Option<i64>),
    /// Up to `limit` messages after this sequence number, to fill a gap.
    After(i64),
}

/// Messages in ascending `seq`, and whether more exist in the requested direction.
pub async fn messages(
    pool: &PgPool,
    uid: &str,
    id: Uuid,
    page: Page,
    limit: i64,
) -> DmResult<(Vec<Message>, bool)> {
    if !is_member(pool, uid, id).await? {
        return Err(DmError::NotFound);
    }
    let limit = limit.clamp(1, MAX_PAGE);
    let rows = match page {
        Page::Before(before) => {
            sqlx::query(concat!(
                "SELECT ",
                message_columns!(),
                ",deleted_at FROM messages
                 WHERE conversation_id=$1 AND seq<coalesce($2,9223372036854775807)
                 ORDER BY seq DESC LIMIT $3"
            ))
            .bind(id)
            .bind(before)
            .bind(limit + 1)
            .fetch_all(pool)
            .await?
        }
        Page::After(after) => {
            sqlx::query(concat!(
                "SELECT ",
                message_columns!(),
                ",deleted_at FROM messages WHERE conversation_id=$1 AND seq>$2
                 ORDER BY seq LIMIT $3"
            ))
            .bind(id)
            .bind(after)
            .bind(limit + 1)
            .fetch_all(pool)
            .await?
        }
    };
    let more = rows.len() as i64 > limit;
    // Deleted messages keep their seq (no false gaps) but are not returned.
    let mut messages = Vec::with_capacity(rows.len());
    for row in rows.iter().take(limit as usize) {
        if row
            .try_get::<Option<DateTime<Utc>>, _>("deleted_at")?
            .is_none()
        {
            messages.push(decode_message(row)?);
        }
    }
    if matches!(page, Page::Before(_)) {
        messages.reverse();
    }
    Ok((messages, more))
}

/// Advances `uid`'s read cursor to `through` (default: the newest message). Never moves it back.
/// Returns the member's new `last_read_seq`.
pub async fn mark_read(pool: &PgPool, uid: &str, id: Uuid, through: Option<i64>) -> DmResult<i64> {
    let mut tx = pool.begin().await?;
    let advanced: Option<i64> = sqlx::query_scalar(
        "UPDATE conversation_members m
         SET last_read_seq=least(coalesce($3,c.last_seq),c.last_seq),last_read_at=now()
         FROM conversations c
         WHERE c.id=m.conversation_id AND m.conversation_id=$1 AND m.user_id=$2
           AND m.last_read_seq<least(coalesce($3,c.last_seq),c.last_seq)
         RETURNING m.last_read_seq",
    )
    .bind(id)
    .bind(uid)
    .bind(through)
    .fetch_optional(&mut *tx)
    .await?;
    let seq = match advanced {
        Some(seq) => {
            notify(&mut tx, "read", id, seq, &[uid.to_owned()]).await?;
            seq
        }
        None => sqlx::query_scalar(
            "SELECT last_read_seq FROM conversation_members WHERE conversation_id=$1 AND user_id=$2",
        )
        .bind(id)
        .bind(uid)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or(DmError::NotFound)?,
    };
    tx.commit().await?;
    Ok(seq)
}

/// Unread messages across all of `uid`'s conversations.
pub async fn unread_total(
    executor: impl sqlx::PgExecutor<'_>,
    uid: &str,
) -> Result<i64, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT coalesce(sum(greatest(c.last_seq-m.last_read_seq,0)),0)::bigint
         FROM conversation_members m JOIN conversations c ON c.id=m.conversation_id
         WHERE m.user_id=$1",
    )
    .bind(uid)
    .fetch_one(executor)
    .await
}
