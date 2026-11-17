//! `/app/v1/conversations…`: the in-house direct message API. Writes are plain idempotent HTTP;
//! live updates arrive on the SSE stream (`GET /app/v1/conversations/events`).
use axum::{
    Json,
    extract::{Path, Query, State},
    http::{HeaderValue, StatusCode},
    response::{
        IntoResponse, Response,
        sse::{Event, KeepAlive, Sse},
    },
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use std::{convert::Infallible, time::Duration};
use utoipa::{IntoParams, ToSchema};
use uuid::Uuid;

use super::store::{self, Conversation, DmError, Message, NewMessage, Page, PostOptions, Posted};
use crate::{
    domain::{firebase_auth::FirebaseUser, mail_bridge},
    errors::AppError,
    state::AppStateDyn,
};

/// Streams end after this long so a revoked or deleted account cannot keep listening on an old
/// ID token; clients reconnect with a fresh token. Jittered so reconnects do not synchronize.
const STREAM_LIFETIME: Duration = Duration::from_secs(25 * 60);
/// Below proxy idle timeouts (Cloudflare closes idle connections after 100 s).
const KEEP_ALIVE: Duration = Duration::from_secs(20);
const DEFAULT_PAGE: i64 = 30;

impl From<DmError> for AppError {
    fn from(error: DmError) -> Self {
        match error {
            DmError::NotFound => AppError::not_found("conversation not found"),
            DmError::Frozen => {
                AppError::new("conversation is frozen").with_status(StatusCode::CONFLICT)
            }
            DmError::Conflict(reason) => AppError::new(reason).with_status(StatusCode::CONFLICT),
            DmError::Invalid(reason) => AppError::bad_request(reason),
            DmError::Database(error) => database(error),
        }
    }
}

fn database(error: sqlx::Error) -> AppError {
    AppError::internal("direct messages", error).with_status(StatusCode::SERVICE_UNAVAILABLE)
}

fn bridge_unavailable(error: anyhow::Error) -> AppError {
    AppError::internal("mail bridge", error).with_status(StatusCode::SERVICE_UNAVAILABLE)
}

fn pool(state: &AppStateDyn) -> Result<&PgPool, AppError> {
    state
        .postgres
        .as_ref()
        .ok_or_else(|| AppError::from_status(StatusCode::SERVICE_UNAVAILABLE))
}

fn encode_cursor((at, id): (DateTime<Utc>, Uuid)) -> String {
    format!("{}_{id}", at.timestamp_micros())
}

fn decode_cursor(cursor: &str) -> Result<(DateTime<Utc>, Uuid), AppError> {
    let invalid = || AppError::bad_request("invalid cursor");
    let (micros, id) = cursor.split_once('_').ok_or_else(invalid)?;
    let at = DateTime::from_timestamp_micros(micros.parse().map_err(|_| invalid())?)
        .ok_or_else(invalid)?;
    Ok((at, id.parse().map_err(|_| invalid())?))
}

#[derive(Debug, Deserialize, IntoParams)]
#[into_params(parameter_in = Query)]
pub struct InboxQuery {
    /// `nextCursor` from the previous page.
    pub cursor: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct InboxResponse {
    pub conversations: Vec<Conversation>,
    pub next_cursor: Option<String>,
    /// Unread messages across every conversation (the app badge).
    pub unread_total: i64,
}

/// The signed-in user's conversations that have messages, most recent first.
#[utoipa::path(
    get,
    path = "/conversations",
    tag = "messages",
    params(InboxQuery),
    responses((status = 200, body = InboxResponse)),
    security(("FirebaseAuth" = []))
)]
pub async fn inbox(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Query(query): Query<InboxQuery>,
) -> Result<Json<InboxResponse>, AppError> {
    let pool = pool(&state)?;
    let before = query.cursor.as_deref().map(decode_cursor).transpose()?;
    let (page, unread_total) = tokio::try_join!(
        store::inbox(pool, &user.uid, before, query.limit.unwrap_or(DEFAULT_PAGE)),
        store::unread_total(pool, &user.uid),
    )
    .map_err(database)?;
    Ok(Json(InboxResponse {
        conversations: page.conversations,
        next_cursor: page.next.map(encode_cursor),
        unread_total,
    }))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct OpenDirect {
    pub user_id: String,
}

/// Returns the 1:1 conversation with `userId`, creating it if needed.
#[utoipa::path(
    post,
    path = "/conversations/direct",
    tag = "messages",
    request_body = OpenDirect,
    responses((status = 200, body = Conversation), (status = 404, description = "No such user")),
    security(("FirebaseAuth" = []))
)]
pub async fn open_direct(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Json(command): Json<OpenDirect>,
) -> Result<Json<Conversation>, AppError> {
    let pool = pool(&state)?;
    let mut tx = pool.begin().await.map_err(database)?;
    let id = store::ensure_direct(&mut tx, &user.uid, &command.user_id).await?;
    let conversation = store::conversation(&mut *tx, &user.uid, id)
        .await
        .map_err(database)?
        .ok_or(DmError::NotFound)?;
    tx.commit().await.map_err(database)?;
    Ok(Json(conversation))
}

#[utoipa::path(
    get,
    path = "/conversations/{id}",
    tag = "messages",
    params(("id" = Uuid, Path)),
    responses((status = 200, body = Conversation), (status = 404, description = "Not a member")),
    security(("FirebaseAuth" = []))
)]
pub async fn get_conversation(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(id): Path<Uuid>,
) -> Result<Json<Conversation>, AppError> {
    store::conversation(pool(&state)?, &user.uid, id)
        .await
        .map_err(database)?
        .map(Json)
        .ok_or_else(|| DmError::NotFound.into())
}

#[derive(Debug, Deserialize, IntoParams)]
#[into_params(parameter_in = Query)]
pub struct MessagesQuery {
    /// Messages before this `seq` (default: the newest page).
    pub before: Option<i64>,
    /// Messages after this `seq`, oldest first (gap fill after a reconnect).
    pub after: Option<i64>,
    pub limit: Option<i64>,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct MessagesResponse {
    /// Ascending `seq`.
    pub messages: Vec<Message>,
    /// More messages exist in the requested direction.
    pub has_more: bool,
}

#[utoipa::path(
    get,
    path = "/conversations/{id}/messages",
    tag = "messages",
    params(("id" = Uuid, Path), MessagesQuery),
    responses((status = 200, body = MessagesResponse)),
    security(("FirebaseAuth" = []))
)]
pub async fn list_messages(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(id): Path<Uuid>,
    Query(query): Query<MessagesQuery>,
) -> Result<Json<MessagesResponse>, AppError> {
    let page = match (query.before, query.after) {
        (Some(_), Some(_)) => return Err(AppError::bad_request("use either before or after")),
        (_, Some(after)) => Page::After(after),
        (before, None) => Page::Before(before),
    };
    let (messages, has_more) = store::messages(
        pool(&state)?,
        &user.uid,
        id,
        page,
        query.limit.unwrap_or(DEFAULT_PAGE),
    )
    .await?;
    Ok(Json(MessagesResponse { messages, has_more }))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct SendMessage {
    /// Client-generated; resending the same ID returns the stored message instead of a duplicate.
    pub id: Uuid,
    pub text: String,
}

/// Sends a message. Recipients get a realtime event and an APNs push; a venue reached through an
/// email thread (or a member who opted into DM emails) also gets the message by email.
#[utoipa::path(
    post,
    path = "/conversations/{id}/messages",
    tag = "messages",
    params(("id" = Uuid, Path)),
    request_body = SendMessage,
    responses(
        (status = 201, body = Message, description = "Sent"),
        (status = 200, body = Message, description = "Already sent (retry)"),
        (status = 409, description = "Frozen conversation or reused message ID"),
    ),
    security(("FirebaseAuth" = []))
)]
pub async fn send_message(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(id): Path<Uuid>,
    Json(command): Json<SendMessage>,
) -> Result<Response, AppError> {
    let pool = pool(&state)?;
    let message_id = command.id.to_string();
    // Email lookups happen before the transaction so it holds exactly one pooled connection.
    let mut plans = vec![];
    for receiver in store::other_members(pool, id, &user.uid)
        .await
        .map_err(database)?
    {
        let plan = mail_bridge::plan_direct_message_email(
            &state,
            "dm",
            &message_id,
            &user.uid,
            &receiver,
            &command.text,
            vec![],
        )
        .await
        .map_err(bridge_unavailable)?;
        plans.extend(plan);
    }
    let mut tx = pool.begin().await.map_err(database)?;
    let posted = store::post(
        &mut tx,
        &NewMessage {
            id: command.id,
            conversation_id: id,
            author_id: user.uid.clone(),
            text: command.text,
            attachments: vec![],
        },
        &PostOptions::client(),
    )
    .await?;
    let mut venue_contacts = vec![];
    if let Posted::Created { recipients, .. } = &posted {
        // Enqueued before commit (idempotent by message ID), so an accepted message is never
        // missing its email; a failed enqueue rolls the message back and the client retries.
        for plan in plans
            .into_iter()
            .filter(|plan| recipients.contains(&plan.receiver_id))
        {
            let receiver = plan.receiver_id.clone();
            if mail_bridge::enqueue_bridged(&state, plan)
                .await
                .map_err(bridge_unavailable)?
                == mail_bridge::Bridged::VenueThread
            {
                venue_contacts.push(receiver);
            }
        }
    }
    tx.commit().await.map_err(database)?;
    for receiver in venue_contacts {
        let slack = state.mail.slack_webhook_url.clone();
        let sender = user.uid.clone();
        tokio::spawn(async move {
            mail_bridge::notify_slack(
                slack.as_deref(),
                "new venue contact email",
                &format!("{sender} => {receiver}"),
            )
            .await;
        });
    }
    let status = match posted {
        Posted::Created { .. } => StatusCode::CREATED,
        Posted::Duplicate(_) => StatusCode::OK,
    };
    Ok((status, Json(posted.message().clone())).into_response())
}

#[derive(Debug, Default, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct MarkRead {
    /// Read through this `seq` (default: the newest message).
    pub through_seq: Option<i64>,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ReadResponse {
    pub last_read_seq: i64,
    pub unread_total: i64,
}

#[utoipa::path(
    post,
    path = "/conversations/{id}/read",
    tag = "messages",
    params(("id" = Uuid, Path)),
    request_body = MarkRead,
    responses((status = 200, body = ReadResponse)),
    security(("FirebaseAuth" = []))
)]
pub async fn mark_read(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(id): Path<Uuid>,
    body: Option<Json<MarkRead>>,
) -> Result<Json<ReadResponse>, AppError> {
    let pool = pool(&state)?;
    let through = body.and_then(|Json(body)| body.through_seq);
    let last_read_seq = store::mark_read(pool, &user.uid, id, through).await?;
    let unread_total = store::unread_total(pool, &user.uid)
        .await
        .map_err(database)?;
    Ok(Json(ReadResponse {
        last_read_seq,
        unread_total,
    }))
}

/// Server-sent events for the signed-in user. Every `data:` line is one JSON object:
/// `ready` (on connect, with `unreadTotal`), `message`, `read`, and `resync` (events may have
/// been missed: refetch). `message`/`read` also carry the member's `unreadCount`, `lastReadSeq`,
/// `unreadTotal` and the conversation's `frozen`. Messages carry `seq`; a gap means refetch with
/// `?after=`.
pub async fn events(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
) -> Result<Response, AppError> {
    let pool = pool(&state)?;
    let subscription = state
        .dm_hub
        .subscribe(&user.uid)
        .ok_or_else(|| AppError::from_status(StatusCode::SERVICE_UNAVAILABLE))?;
    // Subscribed before reading the total, so no update can fall between the two.
    let unread_total = store::unread_total(pool, &user.uid)
        .await
        .map_err(database)?;
    let ready = serde_json::json!({"type": "ready", "unreadTotal": unread_total}).to_string();
    let jitter = Duration::from_secs(u64::from(rand_jitter(&user.uid)) % 300);
    let deadline = tokio::time::Instant::now() + STREAM_LIFETIME + jitter;
    let stream = futures::stream::unfold(
        (Some(ready), subscription),
        move |(first, mut subscription)| async move {
            if let Some(first) = first {
                return Some((
                    Ok::<_, Infallible>(Event::default().data(first)),
                    (None, subscription),
                ));
            }
            match tokio::time::timeout_at(deadline, subscription.receiver.recv()).await {
                Ok(Some(payload)) => {
                    Some((Ok(Event::default().data(&*payload)), (None, subscription)))
                }
                // Closed (shutdown, stalled, replaced) or expired: the client reconnects.
                _ => None,
            }
        },
    );
    let mut response = Sse::new(stream)
        .keep_alive(KeepAlive::new().interval(KEEP_ALIVE))
        .into_response();
    // Disable response buffering in reverse proxies that honor it.
    response
        .headers_mut()
        .insert("x-accel-buffering", HeaderValue::from_static("no"));
    Ok(response)
}

fn rand_jitter(uid: &str) -> u32 {
    let nanos = Utc::now().timestamp_subsec_nanos();
    uid.bytes()
        .fold(nanos, |hash, byte| hash.rotate_left(5) ^ u32::from(byte))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cursors_round_trip_and_reject_garbage() {
        let at = DateTime::from_timestamp_micros(1_763_400_000_123_456).unwrap();
        let id = Uuid::new_v4();
        assert_eq!(decode_cursor(&encode_cursor((at, id))).unwrap(), (at, id));
        assert!(decode_cursor("nope").is_err());
        assert!(decode_cursor("12_not-a-uuid").is_err());
    }
}
