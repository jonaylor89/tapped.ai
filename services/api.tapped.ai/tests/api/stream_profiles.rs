use super::{
    external_effects::{cleanup, database},
    helpers::mock_state,
};
use axum::{
    Json, Router,
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    routing::{delete, post},
};
use serde_json::{Value, json};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, AtomicU16, Ordering},
};
use tapped_api_rs::{
    data::google_identity::{Account, GoogleIdentity},
    domain::{
        app_data::{self, DocumentPath},
        external_effects,
        firebase_auth::FirebaseUser,
        identity_worker::{ProviderWorker, capture_account, capture_deleted},
        mail_bridge::SqliteMailStore,
    },
};
use tokio::sync::{Notify, Semaphore};

struct Provider {
    first: AtomicBool,
    started: Notify,
    release: Semaphore,
    requests: Mutex<Vec<Value>>,
    applied: Mutex<Option<Value>>,
    delete_missing: AtomicBool,
    lookup_status: AtomicU16,
    lookup_override: Mutex<Option<Value>>,
}
impl Provider {
    fn new() -> Self {
        Self {
            first: AtomicBool::new(true),
            started: Notify::new(),
            release: Semaphore::new(0),
            requests: Mutex::new(vec![]),
            applied: Mutex::new(None),
            delete_missing: AtomicBool::new(false),
            lookup_status: AtomicU16::new(200),
            lookup_override: Mutex::new(None),
        }
    }
}
fn authenticated(headers: &HeaderMap) {
    assert_eq!(headers["Stream-Auth-Type"], "jwt");
    let token = headers["Authorization"]
        .to_str()
        .unwrap()
        .strip_prefix("Bearer ")
        .unwrap();
    let decoded = jsonwebtoken::decode::<Value>(
        token,
        &jsonwebtoken::DecodingKey::from_secret(b"test-stream-secret"),
        &jsonwebtoken::Validation::new(jsonwebtoken::Algorithm::HS256),
    )
    .unwrap();
    assert_eq!(decoded.claims["server"], true);
}
async fn upsert(
    State(provider): State<Arc<Provider>>,
    headers: HeaderMap,
    Json(body): Json<Value>,
) -> StatusCode {
    authenticated(&headers);
    provider.requests.lock().unwrap().push(body.clone());
    if provider.first.swap(false, Ordering::SeqCst) {
        provider.started.notify_one();
        provider.release.acquire().await.unwrap().forget();
    }
    *provider.applied.lock().unwrap() = Some(body);
    StatusCode::OK
}
async fn remove(
    State(provider): State<Arc<Provider>>,
    Path(uid): Path<String>,
    headers: HeaderMap,
) -> StatusCode {
    authenticated(&headers);
    assert_eq!(uid, "user");
    provider
        .requests
        .lock()
        .unwrap()
        .push(json!({"deleted":uid}));
    if provider.delete_missing.load(Ordering::SeqCst) {
        return StatusCode::NOT_FOUND;
    }
    *provider.applied.lock().unwrap() = None;
    StatusCode::OK
}
async fn query_users(
    State(provider): State<Arc<Provider>>,
    Query(query): Query<std::collections::HashMap<String, String>>,
    headers: HeaderMap,
) -> (StatusCode, Json<Value>) {
    authenticated(&headers);
    assert_eq!(query["api_key"], "test-key");
    let payload: Value = serde_json::from_str(&query["payload"]).unwrap();
    assert_eq!(payload["filter_conditions"]["id"], "user");
    provider
        .requests
        .lock()
        .unwrap()
        .push(json!({"lookup":"user"}));
    let snapshot = provider
        .lookup_override
        .lock()
        .unwrap()
        .clone()
        .unwrap_or_else(|| {
            let profiles = provider.applied.lock().unwrap().clone();
            let users: Vec<Value> = profiles
                .and_then(|value| {
                    value["users"]
                        .as_object()
                        .map(|users| users.values().cloned().collect())
                })
                .unwrap_or_default();
            json!({"users":users})
        });
    (
        StatusCode::from_u16(provider.lookup_status.load(Ordering::SeqCst)).unwrap(),
        Json(snapshot),
    )
}
async fn server(provider: Arc<Provider>) -> (String, tokio::task::JoinHandle<()>) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let router = Router::new()
        .route("/users", post(upsert).get(query_users))
        .route("/users/{uid}", delete(remove))
        .with_state(provider);
    (
        format!("http://{address}"),
        tokio::spawn(async move { axum::serve(listener, router).await.unwrap() }),
    )
}
fn worker(pool: sqlx::PgPool, url: String, temp: &std::path::Path) -> ProviderWorker {
    let key = temp.join("test.pem");
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
    let credentials = temp.join("credentials.json");
    std::fs::write(&credentials,serde_json::to_vec(&json!({"project_id":"test-project","client_email":"test@test-project.iam.gserviceaccount.com","private_key":std::fs::read_to_string(key).unwrap()})).unwrap()).unwrap();
    ProviderWorker {
        pool,
        google: GoogleIdentity::new(credentials.to_str().unwrap(), "test-project").unwrap(),
        mail: SqliteMailStore::open(temp.join("mail.sqlite3").to_str().unwrap()).unwrap(),
        client: reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(10))
            .build()
            .unwrap(),
        stream_key: "test-key".into(),
        stream_secret: "test-stream-secret".into(),
        stream_base_url: url,
        auth_effects: true,
        apns: None,
    }
}
async fn fixture(pool: &sqlx::PgPool) {
    sqlx::query("INSERT INTO users(id,username,email,artist_name) VALUES('user','user','old@example.test','Old')").execute(pool).await.unwrap();
    let mut tx = pool.begin().await.unwrap();
    external_effects::record_profile(&mut tx, &json!({"id":"user"}), false)
        .await
        .unwrap();
    tx.commit().await.unwrap();
}
#[tokio::test]
async fn concurrent_profile_workers_retry_contention_and_read_newest_profile_after_provider_lock() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    fixture(&pool).await;
    let temp = tempfile::tempdir().unwrap();
    let provider = Arc::new(Provider::new());
    let (url, server) = server(provider.clone()).await;
    let worker = Arc::new(worker(pool.clone(), url, temp.path()));
    let first = worker.clone();
    let first = tokio::spawn(async move { first.deliver_one().await });
    tokio::time::timeout(
        std::time::Duration::from_secs(3),
        provider.started.notified(),
    )
    .await
    .unwrap();
    let mut state = mock_state();
    state.postgres = Some(pool.clone());
    // API mutations must stay responsive while provider I/O is in progress.
    let _ = tokio::time::timeout(
        std::time::Duration::from_secs(2),
        app_data::update(
            State(state),
            FirebaseUser {
                uid: "user".into(),
                email: Some("old@example.test".into()),
            },
            Path(DocumentPath::from(("users".into(), "user".into()))),
            Json(json!({"artistName":"New","profilePicture":"https://example.test/new.png"})),
        ),
    )
    .await
    .unwrap()
    .unwrap();
    assert!(worker.deliver_one().await.unwrap());
    assert_eq!(
        provider.requests.lock().unwrap().len(),
        1,
        "a second worker must not publish out of order"
    );
    assert_eq!(sqlx::query_scalar::<_,i64>("SELECT count(*) FROM external_effect_outbox WHERE available_at>now() AND delivered_at IS NULL AND lock_token IS NULL").fetch_one(&pool).await.unwrap(),1,"contention is retained for retry, never acknowledged");
    provider.release.add_permits(1);
    first.await.unwrap().unwrap();
    sqlx::query("UPDATE external_effect_outbox SET available_at=now() WHERE delivered_at IS NULL")
        .execute(&pool)
        .await
        .unwrap();
    assert!(worker.deliver_one().await.unwrap());
    let final_profile = provider.applied.lock().unwrap().clone().unwrap();
    assert_eq!(final_profile["users"]["user"]["name"], "New");
    assert_eq!(
        final_profile["users"]["user"]["image"],
        "https://example.test/new.png"
    );
    assert!(!worker.deliver_one().await.unwrap());
    server.abort();
    cleanup(pool, admin, name).await;
}
#[tokio::test]
async fn auth_deletion_is_captured_without_waiting_for_stream_and_serialized_after_inflight_profile()
 {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    fixture(&pool).await;
    capture_account(
        &pool,
        &Account {
            local_id: "user".into(),
            email: "old@example.test".into(),
            display_name: "Old".into(),
            created_at: "1234".into(),
        },
        uuid::Uuid::new_v4(),
        false,
    )
    .await
    .unwrap();
    let temp = tempfile::tempdir().unwrap();
    let provider = Arc::new(Provider::new());
    let (url, server) = server(provider.clone()).await;
    let worker = Arc::new(worker(pool.clone(), url, temp.path()));
    let first = worker.clone();
    let first = tokio::spawn(async move { first.deliver_one().await });
    tokio::time::timeout(
        std::time::Duration::from_secs(3),
        provider.started.notified(),
    )
    .await
    .unwrap();
    tokio::time::timeout(
        std::time::Duration::from_secs(2),
        capture_deleted(&pool, "user"),
    )
    .await
    .unwrap()
    .unwrap();
    assert!(worker.deliver_one().await.unwrap());
    assert_eq!(provider.requests.lock().unwrap().len(), 1);
    provider.release.add_permits(1);
    first.await.unwrap().unwrap();
    sqlx::query("UPDATE external_effect_outbox SET available_at=now() WHERE delivered_at IS NULL")
        .execute(&pool)
        .await
        .unwrap();
    assert!(worker.deliver_one().await.unwrap());
    assert!(provider.applied.lock().unwrap().is_none());
    assert_eq!(provider.requests.lock().unwrap().len(), 2);
    assert!(!worker.deliver_one().await.unwrap());
    server.abort();
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn delete_404_requires_authenticated_evidence_of_absence_and_failures_remain_retryable() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    let temp = tempfile::tempdir().unwrap();
    let provider = Arc::new(Provider::new());
    provider.delete_missing.store(true, Ordering::SeqCst);
    let (url, server) = server(provider.clone()).await;
    let worker = worker(pool.clone(), format!("{url}/"), temp.path());
    let cases = [
        (json!({"users":[{"id":"user"}]}), 200, false),
        (json!({"invalid":true}), 200, false),
        (json!({"users":[]}), 503, false),
        (json!({"users":[]}), 200, true),
        (
            json!({"users":[{"id":"user","deleted_at":"2026-01-01T00:00:00Z"}]}),
            200,
            true,
        ),
        (
            json!({"users":[{"id":"user","deleted_at":"invalid"}]}),
            200,
            false,
        ),
        (
            json!({"users":[{"id":"someone-else","deleted_at":"2026-01-01T00:00:00Z"}]}),
            200,
            false,
        ),
    ];
    for (index, (snapshot, status, confirmed)) in cases.into_iter().enumerate() {
        *provider.lookup_override.lock().unwrap() = Some(snapshot);
        provider.lookup_status.store(status, Ordering::SeqCst);
        let id = format!("verify-delete-{index}");
        let mut tx = pool.begin().await.unwrap();
        external_effects::enqueue(&mut tx,&id,"auth_delete",json!({"localId":"user","email":"test@tapped.ai","displayName":"Test","createdAt":"1234"})).await.unwrap();
        tx.commit().await.unwrap();
        assert!(worker.deliver_one().await.unwrap());
        let state:(bool,Option<String>,bool,bool)=sqlx::query_as("SELECT delivered_at IS NOT NULL,last_error,lock_token IS NULL,available_at>now() FROM external_effect_outbox WHERE id=$1").bind(&id).fetch_one(&pool).await.unwrap();
        assert_eq!(state.0, confirmed, "delete case {index}");
        assert!(state.2);
        if !confirmed {
            assert_eq!(state.1.as_deref(), Some("provider_error"));
            assert!(state.3);
        }
        // Keep this case's retry out of the next isolated provider-response scenario.
        sqlx::query("UPDATE external_effect_outbox SET available_at=now()+interval '1 day' WHERE id=$1 AND delivered_at IS NULL").bind(id).execute(&pool).await.unwrap();
    }
    assert_eq!(
        provider.requests.lock().unwrap().len(),
        14,
        "each 404 must perform a separate authenticated lookup"
    );
    server.abort();
    cleanup(pool, admin, name).await;
}
