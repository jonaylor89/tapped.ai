use super::helpers::mock_state;
use async_trait::async_trait;
use axum::{
    Json,
    extract::{Path, State},
};
use serde_json::{Value, json};
use sqlx::{
    PgPool, Row,
    postgres::{PgConnectOptions, PgPoolOptions},
};
use std::{
    str::FromStr,
    sync::{Arc, Mutex},
};
use tapped_api_rs::{
    data::postgres::MIGRATOR,
    domain::{
        app_data::{self, DocumentPath},
        firebase_auth::FirebaseUser,
        founder_notifications::{
            self as notifications, DeliveryError, FounderMessage, FounderTransport,
        },
    },
};

// Every worker test owns a separate empty DB: other API tests can enqueue events concurrently.
struct TestDatabase {
    pool: PgPool,
    admin: PgPool,
    name: String,
}
impl TestDatabase {
    async fn new() -> Option<Self> {
        let Ok(url) = std::env::var("DATABASE_URL") else {
            eprintln!("DATABASE_URL unset; skipping founder notification PostGIS test");
            return None;
        };
        let options = PgConnectOptions::from_str(&url).unwrap();
        let admin = PgPoolOptions::new()
            .max_connections(1)
            .connect_with(options.clone())
            .await
            .unwrap();
        let name = format!("founders_{}", uuid::Uuid::new_v4().simple());
        sqlx::query(&format!("CREATE DATABASE {name}"))
            .execute(&admin)
            .await
            .unwrap();
        let pool = PgPoolOptions::new()
            .max_connections(5)
            .connect_with(options.database(&name))
            .await
            .unwrap();
        MIGRATOR.run(&pool).await.unwrap();
        Some(Self { pool, admin, name })
    }
    async fn cleanup(self) {
        self.pool.close().await;
        sqlx::query(&format!("DROP DATABASE {} WITH (FORCE)", self.name))
            .execute(&self.admin)
            .await
            .unwrap();
        self.admin.close().await;
    }
}
#[derive(Default)]
struct RecordingTransport {
    messages: Mutex<Vec<FounderMessage>>,
    failure: Mutex<Option<DeliveryError>>,
}
#[async_trait]
impl FounderTransport for RecordingTransport {
    async fn send(&self, message: &FounderMessage) -> Result<(), DeliveryError> {
        self.messages.lock().unwrap().push(message.clone());
        match self.failure.lock().unwrap().take() {
            Some(error) => Err(error),
            None => Ok(()),
        }
    }
}
async fn enqueue(pool: &PgPool, id: &str) {
    let mut tx = pool.begin().await.unwrap();
    notifications::enqueue(
        &mut tx,
        id,
        "booking",
        "test-booking",
        "test-actor",
        &FounderMessage {
            text: "test booking".into(),
        },
    )
    .await
    .unwrap();
    tx.commit().await.unwrap();
}

#[tokio::test]
async fn real_mutations_queue_founder_events_once_and_preserve_legacy_filters() {
    let Some(db) = TestDatabase::new().await else {
        return;
    };
    let mut state = mock_state();
    state.postgres = Some(db.pool.clone());
    let artist = FirebaseUser {
        uid: "artist".into(),
        email: Some("artist@example.test".into()),
    };
    let booker = FirebaseUser {
        uid: "booker".into(),
        email: Some("booker@example.test".into()),
    };
    for (user, name) in [(&artist, "Artist"), (&booker, "Booker")] {
        let _ = app_data::create(
            State(state.clone()),
            user.clone(),
            Path("users".into()),
            Json(json!({"id":user.uid,"username":user.uid,"artistName":name})),
        )
        .await
        .unwrap();
    }
    let _ = app_data::update(
        State(state.clone()),
        artist.clone(),
        Path(DocumentPath::from(("users".into(), artist.uid.clone()))),
        Json(json!({"bio":"updated"})),
    )
    .await
    .unwrap();
    // One-time/raw imports bypass mutation hooks; starting the worker must not replay history.
    sqlx::query("INSERT INTO users(id,username) VALUES('imported','imported')")
        .execute(&db.pool)
        .await
        .unwrap();
    for (id, extra) in [
        ("normal", json!({})),
        ("past", json!({"addedByUser":true})),
        ("scraped", json!({"scraperInfo":{}})),
        ("crawled", json!({"crawlerInfo":{}})),
    ] {
        let mut booking = json!({"id":id,"requesterId":booker.uid,"requesteeId":artist.uid,"status":"pending","startTime":"2040-01-01T19:00:00Z","endTime":"2040-01-01T20:00:00Z"});
        for (k, v) in extra.as_object().unwrap() {
            booking[k] = v.clone();
        }
        let _ = app_data::create(
            State(state.clone()),
            booker.clone(),
            Path("bookings".into()),
            Json(booking),
        )
        .await
        .unwrap();
    }
    let _ = app_data::update(
        State(state.clone()),
        artist.clone(),
        Path(DocumentPath::from(("bookings".into(), "normal".into()))),
        Json(json!({"status":"confirmed"})),
    )
    .await
    .unwrap();
    let _ = app_data::create(State(state.clone()),artist.clone(),Path("bookings".into()),Json(json!({"id":"no-venue","requesterId":null,"requesteeId":artist.uid,"addedByUser":true,"status":"confirmed","startTime":"2040-01-01T19:00:00Z","endTime":"2040-01-01T20:00:00Z"}))).await.unwrap();
    let _ = app_data::create(State(state.clone()),booker.clone(),Path("opportunities".into()),Json(json!({"id":"opportunity","userId":booker.uid,"title":"Show","startTime":"2040-01-01T19:00:00Z","endTime":"2040-01-01T20:00:00Z"}))).await.unwrap();
    for comment in ["initial comment", "updated comment"] {
        let _ = app_data::set_interest(
            State(state.clone()),
            artist.clone(),
            Path("opportunity".into()),
            Json(json!({"action":"apply","userComment":comment})),
        )
        .await
        .unwrap();
    }
    let (a, b) = tokio::join!(
        app_data::set_interest(
            State(state.clone()),
            artist.clone(),
            Path("opportunity".into()),
            Json(json!({"action":"apply","userComment":"again"}))
        ),
        app_data::set_interest(
            State(state.clone()),
            artist.clone(),
            Path("opportunity".into()),
            Json(json!({"action":"apply","userComment":"again"}))
        )
    );
    let _ = a.unwrap();
    let _ = b.unwrap();
    let rows: Vec<(String, Value)> = sqlx::query_as(
        "SELECT event_id,payload FROM founder_notification_outbox ORDER BY event_id",
    )
    .fetch_all(&db.pool)
    .await
    .unwrap();
    assert_eq!(rows.len(), 5);
    let application = &rows
        .iter()
        .find(|r| r.0 == "application:opportunity:artist")
        .unwrap()
        .1;
    assert!(
        application["text"]
            .as_str()
            .unwrap()
            .contains("initial comment")
    );
    assert!(
        !application["text"]
            .as_str()
            .unwrap()
            .contains("updated comment")
    );
    assert!(
        rows.iter().find(|r| r.0 == "booking:normal").unwrap().1["text"]
            .as_str()
            .unwrap()
            .contains("Booker booked Artist")
    );
    assert!(
        rows.iter().find(|r| r.0 == "booking:no-venue").unwrap().1["text"]
            .as_str()
            .unwrap()
            .contains("booking without location")
    );
    let transport = RecordingTransport::default();
    for _ in 0..5 {
        assert!(
            notifications::deliver_one(&db.pool, &transport)
                .await
                .unwrap()
        );
    }
    assert!(
        !notifications::deliver_one(&db.pool, &transport)
            .await
            .unwrap()
    );
    assert_eq!(transport.messages.lock().unwrap().len(), 5);
    db.cleanup().await;
}

#[tokio::test]
async fn queue_failures_roll_back_the_business_mutation_and_rollback_never_leaks_events() {
    let Some(db) = TestDatabase::new().await else {
        return;
    };
    let mut tx = db.pool.begin().await.unwrap();
    notifications::enqueue(
        &mut tx,
        "rollback",
        "booking",
        "b",
        "a",
        &FounderMessage {
            text: "not committed".into(),
        },
    )
    .await
    .unwrap();
    tx.rollback().await.unwrap();
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM founder_notification_outbox")
            .fetch_one(&db.pool)
            .await
            .unwrap(),
        0
    );
    sqlx::query("CREATE FUNCTION reject_notification() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'test outbox unavailable'; END $$").execute(&db.pool).await.unwrap();
    sqlx::query("CREATE TRIGGER reject_notification BEFORE INSERT ON founder_notification_outbox FOR EACH ROW EXECUTE FUNCTION reject_notification()").execute(&db.pool).await.unwrap();
    let mut state = mock_state();
    state.postgres = Some(db.pool.clone());
    let user = FirebaseUser {
        uid: "rollback-user".into(),
        email: Some("test@example.test".into()),
    };
    assert!(
        app_data::create(
            State(state),
            user.clone(),
            Path("users".into()),
            Json(json!({"id":user.uid,"username":user.uid}))
        )
        .await
        .is_err()
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM users")
            .fetch_one(&db.pool)
            .await
            .unwrap(),
        0
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM services")
            .fetch_one(&db.pool)
            .await
            .unwrap(),
        0
    );
    db.cleanup().await;
}

#[tokio::test]
async fn durable_events_retry_rate_limits_and_parallel_workers_do_not_share_a_lease() {
    let Some(db) = TestDatabase::new().await else {
        return;
    };
    enqueue(&db.pool, "retry").await;
    enqueue(&db.pool, "retry").await;
    let transport = RecordingTransport::default();
    *transport.failure.lock().unwrap() = Some(DeliveryError::Http(429, Some(120)));
    assert!(
        notifications::deliver_one(&db.pool, &transport)
            .await
            .unwrap()
    );
    let row=sqlx::query("SELECT attempts,delivered_at IS NULL AS pending,lease_token IS NULL AS unlocked,available_at>now()+interval '110 seconds' AS delayed,last_error FROM founder_notification_outbox WHERE event_id='retry'").fetch_one(&db.pool).await.unwrap();
    assert_eq!(row.get::<i32, _>("attempts"), 1);
    assert!(row.get::<bool, _>("pending"));
    assert!(row.get::<bool, _>("unlocked"));
    assert!(row.get::<bool, _>("delayed"));
    assert_eq!(row.get::<String, _>("last_error"), "http");
    assert!(
        !notifications::deliver_one(&db.pool, &transport)
            .await
            .unwrap()
    );
    sqlx::query("UPDATE founder_notification_outbox SET available_at=now()")
        .execute(&db.pool)
        .await
        .unwrap();
    let (a, b) = tokio::join!(
        notifications::deliver_one(&db.pool, &transport),
        notifications::deliver_one(&db.pool, &transport)
    );
    assert_eq!(usize::from(a.unwrap()) + usize::from(b.unwrap()), 1);
    assert_eq!(transport.messages.lock().unwrap().len(), 2);
    assert_eq!(
        sqlx::query_scalar::<_, i32>("SELECT attempts FROM founder_notification_outbox")
            .fetch_one(&db.pool)
            .await
            .unwrap(),
        2
    );
    assert!(
        !notifications::deliver_one(&db.pool, &transport)
            .await
            .unwrap()
    );
    db.cleanup().await;
}

/// Explicit manual check: sends one clearly labelled message to the configured founder Slack.
#[tokio::test]
#[ignore = "manual Slack delivery; requires SLACK_WEBHOOK_URL and an isolated test Postgres"]
async fn configured_slack_receives_one_rust_outbox_smoke_message() {
    let db = TestDatabase::new().await.expect("DATABASE_URL required");
    let transport = notifications::SlackWebhook::new(
        &std::env::var("SLACK_WEBHOOK_URL").expect("SLACK_WEBHOOK_URL required"),
    )
    .unwrap();
    let mut tx = db.pool.begin().await.unwrap();
    notifications::enqueue(&mut tx, "manual-smoke", "booking", "migration-smoke", "migration-smoke", &FounderMessage {
        text: "Tapped migration test: Rust/Postgres founder notification delivery verified. This is a test, not a real booking, signup or application.".into()
    }).await.unwrap();
    tx.commit().await.unwrap();
    assert!(
        notifications::deliver_one(&db.pool, &transport)
            .await
            .unwrap()
    );
    let delivered: bool = sqlx::query_scalar("SELECT delivered_at IS NOT NULL FROM founder_notification_outbox WHERE event_id='manual-smoke'")
        .fetch_one(&db.pool).await.unwrap();
    assert!(
        delivered,
        "Slack must accept the message, not merely enqueue it"
    );
    db.cleanup().await;
}

struct BlockingTransport {
    started: tokio::sync::Notify,
    release: tokio::sync::Notify,
}
#[async_trait]
impl FounderTransport for BlockingTransport {
    async fn send(&self, _message: &FounderMessage) -> Result<(), DeliveryError> {
        self.started.notify_one();
        self.release.notified().await;
        Ok(())
    }
}
#[tokio::test]
async fn expired_leases_recover_and_stale_workers_cannot_acknowledge_newer_attempts() {
    let Some(db) = TestDatabase::new().await else {
        return;
    };
    enqueue(&db.pool, "lease").await;
    let blocking = Arc::new(BlockingTransport {
        started: Default::default(),
        release: Default::default(),
    });
    let pool = db.pool.clone();
    let sender = blocking.clone();
    let old =
        tokio::spawn(async move { notifications::deliver_one(&pool, &*sender).await.unwrap() });
    blocking.started.notified().await;
    let other = RecordingTransport::default();
    assert!(!notifications::deliver_one(&db.pool, &other).await.unwrap());
    sqlx::query("UPDATE founder_notification_outbox SET locked_until=now()-interval '1 second'")
        .execute(&db.pool)
        .await
        .unwrap();
    *other.failure.lock().unwrap() = Some(DeliveryError::Network);
    assert!(notifications::deliver_one(&db.pool, &other).await.unwrap());
    blocking.release.notify_one();
    assert!(old.await.unwrap());
    let row=sqlx::query("SELECT delivered_at IS NULL AS pending,last_error,attempts FROM founder_notification_outbox").fetch_one(&db.pool).await.unwrap();
    assert!(row.get::<bool, _>("pending"));
    assert_eq!(row.get::<String, _>("last_error"), "network");
    assert_eq!(row.get::<i32, _>("attempts"), 2);
    sqlx::query("UPDATE founder_notification_outbox SET available_at=now()")
        .execute(&db.pool)
        .await
        .unwrap();
    assert!(notifications::deliver_one(&db.pool, &other).await.unwrap());
    db.cleanup().await;
}
