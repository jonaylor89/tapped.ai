//! In-house direct messages against real Postgres (skipped without `DATABASE_URL`).
use super::{
    external_effects::{cleanup, database},
    helpers::{mock_state, spawn_app_with_state},
};
use async_trait::async_trait;
use axum::{
    Json,
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use chrono::{DateTime, Duration, Utc};
use serde_json::{Value, json};
use sqlx::PgPool;
use std::{collections::HashMap, sync::Arc};
use tapped_api_rs::{
    data::pg_database::PostgresDatabase,
    domain::{
        direct_messages::{
            Hub,
            http::{self, InboxQuery, MarkRead, MessagesQuery, OpenDirect, SendMessage},
            import::{self, StreamChannelState, StreamMessage, StreamSource},
            store::{self, NewMessage, PostOptions},
        },
        firebase_auth::FirebaseUser,
        mail_bridge::{EmailThread, InMemoryMailStore, MailBridge, MailStore},
    },
    state::AppStateDyn,
};
use uuid::Uuid;

async fn users(pool: &PgPool, ids: &[&str]) {
    for id in ids {
        sqlx::query("INSERT INTO users(id,username,artist_name,email) VALUES($1,$1,initcap($1),$1||'@example.test')")
            .bind(id)
            .execute(pool)
            .await
            .unwrap();
    }
}

fn user(uid: &str) -> FirebaseUser {
    FirebaseUser {
        uid: uid.into(),
        email: None,
    }
}

fn state(pool: &PgPool) -> (AppStateDyn, Arc<InMemoryMailStore>) {
    let store = Arc::new(InMemoryMailStore::default());
    let mut mail = MailBridge::disabled();
    mail.store = store.clone();
    (
        AppStateDyn {
            database: Arc::new(PostgresDatabase::new(pool.clone())),
            postgres: Some(pool.clone()),
            mail,
            ..mock_state()
        },
        store,
    )
}

async fn open(state: &AppStateDyn, from: &str, to: &str) -> Uuid {
    http::open_direct(
        State(state.clone()),
        user(from),
        Json(OpenDirect { user_id: to.into() }),
    )
    .await
    .unwrap()
    .0
    .id
}

async fn send(
    state: &AppStateDyn,
    from: &str,
    conversation: Uuid,
    id: Uuid,
    text: &str,
) -> (StatusCode, Value) {
    let response = match http::send_message(
        State(state.clone()),
        user(from),
        Path(conversation),
        Json(SendMessage {
            id,
            text: text.into(),
        }),
    )
    .await
    {
        Ok(response) => response,
        Err(error) => error.into_response(),
    };
    let status = response.status();
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    (status, serde_json::from_slice(&body).unwrap_or(Value::Null))
}

async fn inbox(state: &AppStateDyn, uid: &str) -> http::InboxResponse {
    http::inbox(
        State(state.clone()),
        user(uid),
        Query(InboxQuery {
            cursor: None,
            limit: None,
        }),
    )
    .await
    .unwrap()
    .0
}

#[tokio::test]
async fn sends_are_idempotent_gap_free_and_drive_unread_counts() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    users(&pool, &["ana", "ben"]).await;
    let (state, _) = state(&pool);
    let conversation = open(&state, "ana", "ben").await;
    assert_eq!(
        open(&state, "ben", "ana").await,
        conversation,
        "one conversation per pair"
    );
    assert!(
        inbox(&state, "ana").await.conversations.is_empty(),
        "empty conversations stay out of the inbox"
    );

    let first = Uuid::new_v4();
    let (status, sent) = send(&state, "ana", conversation, first, "hi ben").await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(sent["seq"], 1);
    let (status, retried) = send(&state, "ana", conversation, first, "hi ben").await;
    assert_eq!(
        status,
        StatusCode::OK,
        "a retried send returns the stored message"
    );
    assert_eq!(retried, sent);
    let (status, _) = send(&state, "ana", conversation, first, "different text").await;
    assert_eq!(
        status,
        StatusCode::CONFLICT,
        "a reused ID with other content is rejected"
    );
    send(&state, "ana", conversation, Uuid::new_v4(), "you around?").await;

    let ben = inbox(&state, "ben").await;
    assert_eq!(ben.unread_total, 2);
    assert_eq!(ben.conversations[0].unread_count, 2);
    assert_eq!(
        ben.conversations[0].last_message.as_ref().unwrap().text,
        "you around?"
    );
    assert_eq!(ben.conversations[0].members[0].name, "Ana");
    assert_eq!(
        inbox(&state, "ana").await.unread_total,
        0,
        "own messages are never unread"
    );

    let (_, reply) = send(&state, "ben", conversation, Uuid::new_v4(), "yes!").await;
    assert_eq!(reply["seq"], 3);
    assert_eq!(
        inbox(&state, "ben").await.unread_total,
        0,
        "replying reads the conversation"
    );
    assert_eq!(inbox(&state, "ana").await.unread_total, 1);

    let read = http::mark_read(
        State(state.clone()),
        user("ana"),
        Path(conversation),
        Some(Json(MarkRead {
            through_seq: Some(99),
        })),
    )
    .await
    .unwrap();
    assert_eq!(
        read.last_read_seq, 3,
        "read cursors clamp to the newest message"
    );
    assert_eq!(read.unread_total, 0);
    let again = http::mark_read(
        State(state.clone()),
        user("ana"),
        Path(conversation),
        Some(Json(MarkRead {
            through_seq: Some(1),
        })),
    )
    .await
    .unwrap();
    assert_eq!(again.last_read_seq, 3, "read cursors never move back");
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn concurrent_opens_and_sends_stay_unique_and_sequenced() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    users(&pool, &["ana", "ben"]).await;
    let (state, _) = state(&pool);
    let opens = futures::future::join_all((0..8).map(|i| {
        let state = state.clone();
        async move {
            if i % 2 == 0 {
                open(&state, "ana", "ben").await
            } else {
                open(&state, "ben", "ana").await
            }
        }
    }))
    .await;
    assert!(opens.iter().all(|id| *id == opens[0]));
    let conversation = opens[0];
    futures::future::join_all((0..20).map(|i| {
        let state = state.clone();
        async move {
            let from = if i % 2 == 0 { "ana" } else { "ben" };
            assert_eq!(
                send(&state, from, conversation, Uuid::new_v4(), &format!("m{i}"))
                    .await
                    .0,
                StatusCode::CREATED
            );
        }
    }))
    .await;
    let seqs: Vec<i64> =
        sqlx::query_scalar("SELECT seq FROM messages WHERE conversation_id=$1 ORDER BY seq")
            .bind(conversation)
            .fetch_all(&pool)
            .await
            .unwrap();
    assert_eq!(seqs, (1..=20).collect::<Vec<i64>>());
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn mixed_case_firebase_ids_pair_in_byte_order_whatever_the_database_collation() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    // Firebase UIDs mix cases; en_US collation sorts "apple" before "Zebra", byte order after.
    users(&pool, &["Zebra9", "apple1"]).await;
    let (state, _) = state(&pool);
    let conversation = open(&state, "apple1", "Zebra9").await;
    assert_eq!(open(&state, "Zebra9", "apple1").await, conversation);
    let (low, high): (String, String) =
        sqlx::query_as("SELECT direct_low, direct_high FROM conversations WHERE id=$1")
            .bind(conversation)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!((low.as_str(), high.as_str()), ("Zebra9", "apple1"));
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn outsiders_frozen_conversations_and_deleted_recipients_are_refused() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    users(&pool, &["ana", "ben", "eve"]).await;
    let (state, _) = state(&pool);
    let conversation = open(&state, "ana", "ben").await;
    assert_eq!(
        send(&state, "eve", conversation, Uuid::new_v4(), "hi")
            .await
            .0,
        StatusCode::NOT_FOUND
    );
    let messages = http::list_messages(
        State(state.clone()),
        user("eve"),
        Path(conversation),
        Query(MessagesQuery {
            before: None,
            after: None,
            limit: None,
        }),
    )
    .await;
    assert_eq!(
        messages.unwrap_err().into_response().status(),
        StatusCode::NOT_FOUND
    );
    assert!(
        http::open_direct(
            State(state.clone()),
            user("ana"),
            Json(OpenDirect {
                user_id: "ana".into()
            })
        )
        .await
        .is_err()
    );
    assert!(
        http::open_direct(
            State(state.clone()),
            user("ana"),
            Json(OpenDirect {
                user_id: "ghost".into()
            })
        )
        .await
        .is_err()
    );
    assert_eq!(
        send(&state, "ana", conversation, Uuid::new_v4(), "   ")
            .await
            .0,
        StatusCode::BAD_REQUEST
    );

    // A server delivery freezes (the venue mirror) and a later one unfreezes (the venue replied).
    let mut tx = pool.begin().await.unwrap();
    store::post(
        &mut tx,
        &NewMessage {
            id: Uuid::new_v4(),
            conversation_id: conversation,
            author_id: "ana".into(),
            text: "contact".into(),
            attachments: vec![],
        },
        &PostOptions::server(true),
    )
    .await
    .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(
        send(&state, "ana", conversation, Uuid::new_v4(), "hello?")
            .await
            .0,
        StatusCode::CONFLICT
    );
    let mut tx = pool.begin().await.unwrap();
    store::post(
        &mut tx,
        &NewMessage {
            id: Uuid::new_v4(),
            conversation_id: conversation,
            author_id: "ben".into(),
            text: "reply".into(),
            attachments: vec![],
        },
        &PostOptions::server(false),
    )
    .await
    .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(
        send(&state, "ana", conversation, Uuid::new_v4(), "great")
            .await
            .0,
        StatusCode::CREATED
    );

    sqlx::query("UPDATE users SET deleted=true WHERE id='ben'")
        .execute(&pool)
        .await
        .unwrap();
    assert_eq!(
        send(&state, "ana", conversation, Uuid::new_v4(), "still there?")
            .await
            .0,
        StatusCode::CONFLICT
    );
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn history_pages_backwards_and_fills_gaps_forwards() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    users(&pool, &["ana", "ben"]).await;
    let (state, _) = state(&pool);
    let conversation = open(&state, "ana", "ben").await;
    for i in 1..=7 {
        send(
            &state,
            "ana",
            conversation,
            Uuid::new_v4(),
            &format!("m{i}"),
        )
        .await;
    }
    let page = |before, after, limit| {
        let state = state.clone();
        async move {
            http::list_messages(
                State(state),
                user("ben"),
                Path(conversation),
                Query(MessagesQuery {
                    before,
                    after,
                    limit: Some(limit),
                }),
            )
            .await
            .unwrap()
            .0
        }
    };
    let newest = page(None, None, 3).await;
    assert_eq!(
        newest.messages.iter().map(|m| m.seq).collect::<Vec<_>>(),
        vec![5, 6, 7]
    );
    assert!(newest.has_more);
    let older = page(Some(5), None, 3).await;
    assert_eq!(
        older.messages.iter().map(|m| m.seq).collect::<Vec<_>>(),
        vec![2, 3, 4]
    );
    let oldest = page(Some(2), None, 3).await;
    assert_eq!(
        oldest.messages.iter().map(|m| m.seq).collect::<Vec<_>>(),
        vec![1]
    );
    assert!(!oldest.has_more);
    let gap = page(None, Some(4), 2).await;
    assert_eq!(
        gap.messages.iter().map(|m| m.seq).collect::<Vec<_>>(),
        vec![5, 6]
    );
    assert!(gap.has_more);
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn messages_push_recipient_apns_devices_and_continue_venue_email_threads() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    users(&pool, &["ana", "venue"]).await;
    sqlx::query("INSERT INTO accounts(auth_uid) VALUES('venue'),('ana') ON CONFLICT DO NOTHING")
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO device_tokens(user_id,token,provider,apns_environment) VALUES
         ('venue','aa11','apns','production'),('venue','legacy-fcm','fcm',NULL),('ana','bb22','apns','development')",
    )
    .execute(&pool)
    .await
    .unwrap();
    let (state, mail) = state(&pool);
    mail.upsert_thread(EmailThread {
        id: "thread-1".into(),
        performer_id: "ana".into(),
        performer_username: "ana".into(),
        venue_id: "venue".into(),
        recipients: vec!["booking@venue.example.test".into()],
        subject: "Booking inquiry".into(),
        latest_message_id: "<first@booking.tapped.ai>".into(),
    })
    .await
    .unwrap();
    let conversation = open(&state, "ana", "venue").await;
    let id = Uuid::new_v4();
    send(
        &state,
        "ana",
        conversation,
        id,
        "are you booking for march?",
    )
    .await;
    send(
        &state,
        "ana",
        conversation,
        id,
        "are you booking for march?",
    )
    .await;

    let outbound = mail.outbound();
    assert_eq!(outbound.len(), 1, "a retried send is emailed once");
    assert_eq!(outbound[0].event_id, format!("dm:{id}"));
    assert_eq!(outbound[0].to, vec!["booking@venue.example.test"]);
    assert_eq!(outbound[0].in_reply_to, "<first@booking.tapped.ai>");
    assert_eq!(outbound[0].text_body, "are you booking for march?");

    let pushes: Vec<Value> = sqlx::query_scalar(
        "SELECT payload FROM external_effect_outbox WHERE kind='push' ORDER BY id",
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    assert_eq!(pushes.len(), 1, "only the recipient's APNs token, once");
    assert_eq!(pushes[0]["uid"], "venue");
    assert_eq!(pushes[0]["title"], "Ana");
    assert_eq!(pushes[0]["conversationId"], conversation.to_string());
    cleanup(pool, admin, name).await;
}

/// The next `data:` payload from an SSE response (keep-alive comments are skipped).
async fn next_event(response: &mut reqwest::Response, buffer: &mut String) -> Value {
    loop {
        if let Some(end) = buffer.find("\n\n") {
            let frame: String = buffer.drain(..end + 2).collect();
            if let Some(data) = frame.lines().find_map(|line| line.strip_prefix("data: ")) {
                return serde_json::from_str(data).unwrap();
            }
            continue;
        }
        let chunk = tokio::time::timeout(std::time::Duration::from_secs(10), response.chunk())
            .await
            .expect("event in time")
            .unwrap()
            .expect("stream open");
        buffer.push_str(std::str::from_utf8(&chunk).unwrap());
    }
}

fn emulator_token(uid: &str) -> String {
    let header = URL_SAFE_NO_PAD.encode(br#"{"alg":"none","typ":"JWT"}"#);
    let claims = URL_SAFE_NO_PAD.encode(
        json!({
            "sub": uid, "aud": "demo-dm", "iss": "https://securetoken.google.com/demo-dm",
            "exp": Utc::now().timestamp() + 3600,
        })
        .to_string(),
    );
    format!("{header}.{claims}.")
}

/// Over real HTTP: the SSE stream outlives the request timeout layer, and a committed message
/// reaches both members with their own unread counts.
#[tokio::test]
async fn realtime_events_reach_connected_members_over_sse() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    users(&pool, &["ana", "ben"]).await;
    let (mut state, _) = state(&pool);
    state.firebase_project_id = "demo-dm".into();
    state.firebase_auth_emulator = true;
    state.dm_hub = Hub::default();
    let listener = state.dm_hub.spawn_listener(pool.clone());
    let app = spawn_app_with_state(state.clone()).await;
    let client = reqwest::Client::new();
    let conversation: Value = client
        .post(format!("{}/app/v1/conversations/direct", app.address))
        .bearer_auth(emulator_token("ana"))
        .json(&json!({"userId": "ben"}))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let conversation_id = conversation["id"].as_str().unwrap().to_owned();

    let events = client
        .get(format!("{}/app/v1/conversations/events", app.address))
        .bearer_auth(emulator_token("ben"))
        .send()
        .await
        .unwrap();
    assert_eq!(events.status(), StatusCode::OK);
    assert_eq!(events.headers()["content-type"], "text/event-stream");
    let mut events = events;
    let mut buffer = String::new();
    assert_eq!(next_event(&mut events, &mut buffer).await["type"], "ready");
    // The listener announces itself once connected; tolerate that resync either way.
    let sent = client
        .post(format!(
            "{}/app/v1/conversations/{conversation_id}/messages",
            app.address
        ))
        .bearer_auth(emulator_token("ana"))
        .json(&json!({"id": Uuid::new_v4(), "text": "live?"}))
        .send()
        .await
        .unwrap();
    assert_eq!(sent.status(), StatusCode::CREATED);
    let mut event = next_event(&mut events, &mut buffer).await;
    while event["type"] == "resync" {
        event = next_event(&mut events, &mut buffer).await;
    }
    assert_eq!(event["type"], "message");
    assert_eq!(event["conversationId"], conversation_id);
    assert_eq!(event["message"]["text"], "live?");
    assert_eq!(event["message"]["seq"], 1);
    assert_eq!(event["unreadCount"], 1);
    assert_eq!(event["unreadTotal"], 1);
    assert_eq!(event["frozen"], false);

    client
        .post(format!(
            "{}/app/v1/conversations/{conversation_id}/read",
            app.address
        ))
        .bearer_auth(emulator_token("ben"))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap();
    let read = next_event(&mut events, &mut buffer).await;
    assert_eq!(read["type"], "read");
    assert_eq!(read["unreadTotal"], 0);
    assert_eq!(read["lastReadSeq"], 1);

    state.dm_hub.close();
    listener.abort();
    cleanup(pool, admin, name).await;
}

#[derive(Default)]
struct FakeStream {
    channels: Vec<Value>,
    messages: HashMap<String, Vec<Value>>,
}

#[async_trait]
impl StreamSource for FakeStream {
    async fn channels(
        &self,
        since: Option<DateTime<Utc>>,
        limit: usize,
    ) -> anyhow::Result<Vec<StreamChannelState>> {
        let mut channels: Vec<StreamChannelState> = self
            .channels
            .iter()
            .map(|channel| serde_json::from_value(channel.clone()).unwrap())
            .filter(|channel: &StreamChannelState| {
                since.is_none_or(|since| channel.channel.created_at >= since)
            })
            .collect();
        channels.sort_by_key(|channel| channel.channel.created_at);
        channels.truncate(limit);
        Ok(channels)
    }

    async fn messages(
        &self,
        cid: &str,
        before_id: Option<&str>,
        limit: usize,
    ) -> anyhow::Result<Vec<StreamMessage>> {
        let all: Vec<StreamMessage> = self
            .messages
            .get(cid)
            .cloned()
            .unwrap_or_default()
            .into_iter()
            .map(|m| serde_json::from_value(m).unwrap())
            .collect();
        let end = before_id.map_or(all.len(), |id| all.iter().position(|m| m.id == id).unwrap());
        Ok(all[end.saturating_sub(limit)..end].to_vec())
    }
}

fn stream_message(id: &str, user: &str, text: &str, at: DateTime<Utc>) -> Value {
    json!({"id": id, "text": text, "type": "regular", "user": {"id": user}, "created_at": at})
}

#[tokio::test]
async fn stream_import_is_idempotent_and_preserves_order_reads_and_freezes() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    users(&pool, &["ana", "ben", "venue"]).await;
    let t0 = DateTime::parse_from_rfc3339("2026-03-01T12:00:00Z")
        .unwrap()
        .with_timezone(&Utc);
    let mut source = FakeStream {
        channels: vec![
            json!({"channel": {"cid": "messaging:!members-ab", "created_at": t0, "created_by": {"id": "ana"}},
               "members": [{"user_id": "ana"}, {"user_id": "ben"}],
               "read": [{"user": {"id": "ben"}, "last_read": t0 + Duration::minutes(2)}]}),
            json!({"channel": {"cid": "messaging:!members-av", "created_at": t0 + Duration::hours(1), "frozen": true},
               "members": [{"user_id": "ana"}, {"user_id": "venue"}]}),
            json!({"channel": {"cid": "messaging:!members-ghost", "created_at": t0 + Duration::hours(2)},
               "members": [{"user_id": "ana"}, {"user_id": "ghost"}]}),
            // Two formal members, but others post to it: a community room, not a DM.
            json!({"channel": {"cid": "messaging:community", "created_at": t0 + Duration::hours(3)},
               "members": [{"user_id": "ben"}, {"user_id": "venue"}]}),
        ],
        messages: HashMap::new(),
    };
    // More than one Stream page (300) so pagination is exercised.
    let mut history: Vec<Value> = (0..305)
        .map(|i| {
            stream_message(
                &format!("s{i:03}"),
                if i % 3 == 0 { "ben" } else { "ana" },
                &format!("message {i}"),
                t0 + Duration::minutes(i),
            )
        })
        .collect();
    history.push(json!({"id": "deleted", "text": "", "type": "deleted", "user": {"id": "ana"}, "created_at": t0 + Duration::days(1), "deleted_at": t0 + Duration::days(1)}));
    history.push(json!({"id": "photo", "text": "", "type": "regular", "user": {"id": "ben"}, "created_at": t0 + Duration::days(2),
                        "attachments": [{"type": "image", "image_url": "https://cdn.example.test/p.jpg"}]}));
    source
        .messages
        .insert("messaging:!members-ab".into(), history);
    source.messages.insert(
        "messaging:!members-av".into(),
        vec![stream_message(
            "v1",
            "ana",
            "venue contact",
            t0 + Duration::hours(1),
        )],
    );

    source.messages.insert(
        "messaging:community".into(),
        vec![
            stream_message("c1", "ben", "anyone free friday?", t0 + Duration::hours(3)),
            stream_message("c2", "ana", "me!", t0 + Duration::hours(4)),
        ],
    );

    let dry = import::run(&pool, &source, true).await.unwrap();
    assert_eq!(dry.messages_imported, 307);
    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM messages")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(count, 0, "a dry run writes nothing");

    let first = import::run(&pool, &source, false).await.unwrap();
    assert_eq!(first.channels_seen, 4);
    assert_eq!(first.channels_imported, 2);
    assert_eq!(first.channels_skipped["unknown_member"], 1);
    assert_eq!(first.channels_skipped["community"], 1);
    let community: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM conversations WHERE legacy_stream_cid='messaging:community'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(community, 0);
    assert_eq!(first.messages_imported, 307);
    assert_eq!(first.messages_skipped["deleted"], 1);

    let second = import::run(&pool, &source, false).await.unwrap();
    assert_eq!(
        second.messages_imported, 0,
        "re-running imports nothing new"
    );
    assert_eq!(second.messages_existing, 307);

    let (state, _) = state(&pool);
    let ben = inbox(&state, "ben").await;
    let ab = &ben.conversations[0];
    assert_eq!(ab.last_seq, 306);
    assert_eq!(
        ab.last_message.as_ref().unwrap().attachments[0].url,
        "https://cdn.example.test/p.jpg"
    );
    // Ben read through minute 2 (seq 3), then sent s003 (seq 4) and later messages: reading
    // advances with each of his sends, so only messages after his last one are unread.
    let ben_last_sent: i64 = sqlx::query_scalar(
        "SELECT max(seq) FROM messages WHERE conversation_id=$1 AND author_id='ben'",
    )
    .bind(ab.id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(ab.unread_count, 306 - ben_last_sent);
    let ordered: Vec<String> = sqlx::query_scalar(
        "SELECT legacy_stream_id FROM messages WHERE conversation_id=$1 ORDER BY seq LIMIT 3",
    )
    .bind(ab.id)
    .fetch_all(&pool)
    .await
    .unwrap();
    assert_eq!(ordered, vec!["s000", "s001", "s002"]);
    let venue = inbox(&state, "venue").await;
    assert!(venue.conversations[0].frozen);
    let pushes: i64 = sqlx::query_scalar("SELECT count(*) FROM external_effect_outbox")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(pushes, 0, "imports never notify anyone");

    // A delta after new Stream messages appends them after the existing history.
    source
        .messages
        .get_mut("messaging:!members-av")
        .unwrap()
        .push(stream_message(
            "v2",
            "venue",
            "we replied",
            t0 + Duration::hours(3),
        ));
    let delta = import::run(&pool, &source, false).await.unwrap();
    assert_eq!(delta.messages_imported, 1);
    let venue = inbox(&state, "venue").await;
    assert_eq!(
        venue.conversations[0].last_message.as_ref().unwrap().text,
        "we replied"
    );
    cleanup(pool, admin, name).await;
}
