use serde_json::json;
use sqlx::{
    PgPool,
    postgres::{PgConnectOptions, PgPoolOptions},
};
use std::str::FromStr;
use tapped_api_rs::{
    data::{
        google_identity::{Account, GoogleIdentity},
        postgres::MIGRATOR,
    },
    domain::{
        external_effects,
        identity_worker::{ProviderWorker, capture_account, capture_deleted},
        mail_bridge::SqliteMailStore,
    },
};

async fn database() -> Option<(PgPool, PgPool, String)> {
    let Ok(url) = std::env::var("DATABASE_URL") else {
        return None;
    };
    let options = PgConnectOptions::from_str(&url).unwrap();
    let admin = PgPoolOptions::new()
        .max_connections(1)
        .connect_with(options.clone())
        .await
        .unwrap();
    let name = format!("effects_{}", uuid::Uuid::new_v4().simple());
    sqlx::query(sqlx::AssertSqlSafe(format!("CREATE DATABASE {name}")))
        .execute(&admin)
        .await
        .unwrap();
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect_with(options.database(&name))
        .await
        .unwrap();
    MIGRATOR.run(&pool).await.unwrap();
    Some((pool, admin, name))
}
async fn cleanup(pool: PgPool, admin: PgPool, name: String) {
    pool.close().await;
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "DROP DATABASE {name} WITH (FORCE)"
    )))
    .execute(&admin)
    .await
    .unwrap();
    admin.close().await;
}

#[tokio::test]
async fn feedback_is_private_escaped_and_idempotent_per_authenticated_sender() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    let mut state = super::helpers::mock_state();
    state.postgres = Some(pool.clone());
    let user = tapped_api_rs::domain::firebase_auth::FirebaseUser {
        uid: "feedback-user".into(),
        email: Some("test@example.test".into()),
    };
    let id = uuid::Uuid::new_v4();
    for _ in 0..2 {
        let _ = tapped_api_rs::domain::feedback::submit(
            axum::extract::State(state.clone()),
            user.clone(),
            axum::Json(tapped_api_rs::domain::feedback::Feedback {
                id,
                text: "<@everyone> migration test".into(),
            }),
        )
        .await
        .unwrap();
    }
    let rows: Vec<serde_json::Value> = sqlx::query_scalar(
        "SELECT payload FROM founder_notification_outbox WHERE event_type='feedback'",
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    assert_eq!(rows.len(), 1);
    assert!(
        rows[0]["text"]
            .as_str()
            .unwrap()
            .contains("&lt;@everyone&gt;")
    );
    assert!(
        tapped_api_rs::domain::feedback::submit(
            axum::extract::State(state),
            user,
            axum::Json(tapped_api_rs::domain::feedback::Feedback {
                id,
                text: " ".into()
            })
        )
        .await
        .is_err()
    );
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn identity_baseline_does_not_replay_history_and_lifecycle_events_are_atomic_and_unique() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    let scan = uuid::Uuid::new_v4();
    let old = Account {
        local_id: "old".into(),
        email: "old@example.test".into(),
        display_name: "Old".into(),
        created_at: "1".into(),
    };
    capture_account(&pool, &old, scan, false).await.unwrap();
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM external_effect_outbox")
            .fetch_one(&pool)
            .await
            .unwrap(),
        0
    );
    let new = Account {
        local_id: "new".into(),
        email: "new@example.test".into(),
        display_name: "New".into(),
        created_at: "2".into(),
    };
    sqlx::query("INSERT INTO users(id,username,email) VALUES('new','new','stale@example.test')")
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO services(id,user_id,title) VALUES('service','new','Set')")
        .execute(&pool)
        .await
        .unwrap();
    for _ in 0..2 {
        capture_account(&pool, &new, scan, true).await.unwrap();
    }
    assert_eq!(
        sqlx::query_scalar::<_, String>("SELECT email FROM users WHERE id='new'")
            .fetch_one(&pool)
            .await
            .unwrap(),
        "new@example.test"
    );
    for _ in 0..2 {
        capture_deleted(&pool, "new").await.unwrap();
    }
    let counts:(i64,i64)=sqlx::query_as("SELECT count(*) FILTER(WHERE kind='auth_signup'),count(*) FILTER(WHERE kind='auth_delete') FROM external_effect_outbox").fetch_one(&pool).await.unwrap();
    assert_eq!(counts, (1, 1));
    let removed: bool = sqlx::query_scalar("SELECT deleted FROM users WHERE id='new'")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(removed);
    let removed: bool = sqlx::query_scalar("SELECT deleted FROM services WHERE id='service'")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(removed);
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn push_events_are_per_device_and_transactional_without_replaying_imported_activities() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    sqlx::query(
        "INSERT INTO users(id,username,email) VALUES('artist','artist','artist@example.test')",
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query("INSERT INTO device_tokens(token,user_id) VALUES('device-a','artist'),('device-b','artist')").execute(&pool).await.unwrap();
    let mut tx = pool.begin().await.unwrap();
    external_effects::record_activity(&mut tx, "activity", "artist", "bookingRequest", "booking")
        .await
        .unwrap();
    external_effects::record_activity(&mut tx, "activity", "artist", "bookingRequest", "booking")
        .await
        .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(
        sqlx::query_scalar::<_, i64>(
            "SELECT count(*) FROM external_effect_outbox WHERE kind='push'"
        )
        .fetch_one(&pool)
        .await
        .unwrap(),
        2
    );
    let mut tx = pool.begin().await.unwrap();
    external_effects::record_activity(&mut tx, "rollback", "artist", "bookingUpdate", "booking")
        .await
        .unwrap();
    tx.rollback().await.unwrap();
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM external_effect_outbox")
            .fetch_one(&pool)
            .await
            .unwrap(),
        2
    );
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn mail_handoff_is_idempotent_and_failed_provider_jobs_remain_retryable() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    let temp = tempfile::tempdir().unwrap();
    let key = temp.path().join("test.pem");
    assert!(
        std::process::Command::new("openssl")
            .args(["genrsa", "-out"])
            .arg(&key)
            .arg("2048")
            .output()
            .unwrap()
            .status
            .success()
    );
    let credentials = temp.path().join("credentials.json");
    std::fs::write(&credentials,serde_json::to_vec(&json!({"project_id":"test-project","client_email":"test@test-project.iam.gserviceaccount.com","private_key":std::fs::read_to_string(key).unwrap()})).unwrap()).unwrap();
    let worker = ProviderWorker {
        pool: pool.clone(),
        google: GoogleIdentity::new(credentials.to_str().unwrap(), "test-project").unwrap(),
        mail: SqliteMailStore::open(temp.path().join("mail.sqlite3").to_str().unwrap()).unwrap(),
        client: reqwest::Client::new(),
        stream_key: String::new(),
        stream_secret: String::new(),
        auth_effects: false,
    };
    sqlx::query(
        "INSERT INTO email_templates(name,subject,text_body) VALUES('test','Test','Hello')",
    )
    .execute(&pool)
    .await
    .unwrap();
    let mut tx = pool.begin().await.unwrap();
    external_effects::enqueue(&mut tx, "held", "auth_signup", json!({}))
        .await
        .unwrap();
    external_effects::enqueue(
        &mut tx,
        "mail",
        "mail",
        json!({"to":"test@example.test","template":"test"}),
    )
    .await
    .unwrap();
    external_effects::enqueue(
        &mut tx,
        "bad",
        "mail",
        json!({"to":"test@example.test","template":"missing"}),
    )
    .await
    .unwrap();
    tx.commit().await.unwrap();
    assert!(worker.deliver_one().await.unwrap());
    assert!(worker.deliver_one().await.unwrap());
    assert!(!worker.deliver_one().await.unwrap());
    assert_eq!(worker.mail.claim_outbound(10).unwrap().len(), 1);
    worker
        .deliver(
            "mail",
            "mail",
            json!({"to":"test@example.test","template":"test"}),
        )
        .await
        .unwrap();
    assert_eq!(worker.mail.claim_outbound(10).unwrap().len(), 0);
    let states:(bool,bool,bool)=sqlx::query_as("SELECT (SELECT delivered_at IS NOT NULL FROM external_effect_outbox WHERE id='mail'),(SELECT available_at>now() AND delivered_at IS NULL AND lock_token IS NULL FROM external_effect_outbox WHERE id='bad'),(SELECT attempts=0 FROM external_effect_outbox WHERE id='held')").fetch_one(&pool).await.unwrap();
    assert_eq!(states, (true, true, true));
    cleanup(pool, admin, name).await;
}
