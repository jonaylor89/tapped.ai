use super::{
    external_effects::{cleanup, database},
    helpers::{mock_state, spawn_app_with_state},
};
use axum::{
    Json, Router,
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    routing::post,
};
use serde_json::{Value, json};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicU16, Ordering},
};
use tapped_api_rs::{
    data::{apns::Apns, google_identity::GoogleIdentity},
    domain::{
        app_data, external_effects, firebase_auth::FirebaseUser, identity_worker::ProviderWorker,
        mail_bridge::SqliteMailStore,
    },
};

const APNS_TOKEN: &str = "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90";

#[derive(Default)]
struct Apple {
    status: AtomicU16,
    requests: Mutex<Vec<(String, HeaderMap, Value)>>,
}

async fn send(
    State(apple): State<Arc<Apple>>,
    Path((env, token)): Path<(String, String)>,
    headers: HeaderMap,
    Json(body): Json<Value>,
) -> (StatusCode, Json<Value>) {
    apple
        .requests
        .lock()
        .unwrap()
        .push((format!("{env}:{token}"), headers, body));
    let status = StatusCode::from_u16(apple.status.load(Ordering::SeqCst)).unwrap();
    let reason = if status == StatusCode::GONE {
        json!({"reason":"Unregistered"})
    } else {
        json!({})
    };
    (status, Json(reason))
}

async fn apple() -> (Arc<Apple>, String) {
    let apple = Arc::new(Apple::default());
    apple.status.store(200, Ordering::SeqCst);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let router = Router::new()
        .route("/{env}/3/device/{token}", post(send))
        .with_state(apple.clone());
    tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
    (apple, format!("http://{address}"))
}

fn openssl(args: &[&str], out: &std::path::Path, stdin: Option<&[u8]>) -> Vec<u8> {
    use std::io::Write;
    let mut child = std::process::Command::new("openssl")
        .args(args)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    if let Some(input) = stdin {
        child.stdin.take().unwrap().write_all(input).unwrap();
    } else {
        drop(child.stdin.take());
    }
    let output = child.wait_with_output().unwrap();
    assert!(output.status.success());
    std::fs::write(out, &output.stdout).unwrap();
    output.stdout
}

fn worker(pool: sqlx::PgPool, temp: &std::path::Path, apple: &str) -> ProviderWorker {
    let rsa = temp.join("rsa.pem");
    openssl(&["genrsa", "2048"], &rsa, None);
    let credentials = temp.join("credentials.json");
    std::fs::write(&credentials,serde_json::to_vec(&json!({"project_id":"test-project","client_email":"test@test-project.iam.gserviceaccount.com","private_key":std::fs::read_to_string(rsa).unwrap()})).unwrap()).unwrap();
    // The same PKCS#8 P-256 shape as an App Store Connect `.p8` key.
    let ec = temp.join("ec.pem");
    let raw = openssl(
        &["ecparam", "-name", "prime256v1", "-genkey", "-noout"],
        &ec,
        None,
    );
    let p8 = temp.join("AuthKey_TEST.p8");
    openssl(&["pkcs8", "-topk8", "-nocrypt"], &p8, Some(&raw));
    let apns = Apns::new(
        p8.to_str().unwrap(),
        "KEYID12345",
        "TEAMID1234",
        "com.intheloopstudio",
    )
    .unwrap()
    .with_base_urls(
        &format!("{apple}/production"),
        &format!("{apple}/development"),
    );
    ProviderWorker {
        pool,
        google: GoogleIdentity::new(credentials.to_str().unwrap(), "test-project").unwrap(),
        mail: SqliteMailStore::open(temp.join("mail.sqlite3").to_str().unwrap()).unwrap(),
        client: reqwest::Client::new(),
        stream_key: String::new(),
        stream_secret: String::new(),
        stream_base_url: "https://chat.stream-io-api.com".into(),
        auth_effects: false,
        apns: Some(apns),
    }
}

async fn register(pool: &sqlx::PgPool, input: Value) -> Result<(), StatusCode> {
    let mut state = mock_state();
    state.postgres = Some(pool.clone());
    let user = FirebaseUser {
        uid: "artist".into(),
        email: None,
    };
    app_data::register_token(State(state), user, Json(input))
        .await
        .map(|_| ())
        .map_err(|error| axum::response::IntoResponse::into_response(error).status())
}

async fn seed_artist(pool: &sqlx::PgPool) {
    sqlx::query(
        "INSERT INTO users(id,username,email) VALUES('artist','artist','artist@example.test')",
    )
    .execute(pool)
    .await
    .unwrap();
    sqlx::query("INSERT INTO accounts(auth_uid) VALUES('artist') ON CONFLICT DO NOTHING")
        .execute(pool)
        .await
        .unwrap();
}

#[tokio::test]
async fn apns_tokens_register_with_their_environment_and_legacy_tokens_stay_fcm() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    seed_artist(&pool).await;
    register(&pool, json!({"token":"legacy-fcm-token","platform":"ios"}))
        .await
        .unwrap();
    register(
        &pool,
        json!({"token":APNS_TOKEN,"platform":"ios","provider":"apns","environment":"production"}),
    )
    .await
    .unwrap();
    for invalid in [
        json!({"token":"not-hex","provider":"apns","environment":"production"}),
        json!({"token":APNS_TOKEN,"provider":"apns"}),
        json!({"token":APNS_TOKEN,"provider":"apns","environment":"staging"}),
        json!({"token":"../../x","provider":"apns","environment":"production"}),
        json!({"token":APNS_TOKEN,"provider":"webpush"}),
    ] {
        assert_eq!(register(&pool, invalid).await, Err(StatusCode::BAD_REQUEST));
    }
    let rows: Vec<(String, String, Option<String>)> = sqlx::query_as(
        "SELECT token,provider,apns_environment FROM device_tokens ORDER BY provider",
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    assert_eq!(
        rows,
        vec![
            (APNS_TOKEN.into(), "apns".into(), Some("production".into())),
            ("legacy-fcm-token".into(), "fcm".into(), None),
        ]
    );
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn apns_pushes_are_signed_routed_by_environment_and_prune_unregistered_tokens() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    seed_artist(&pool).await;
    register(
        &pool,
        json!({"token":APNS_TOKEN,"platform":"ios","provider":"apns","environment":"development"}),
    )
    .await
    .unwrap();
    let mut tx = pool.begin().await.unwrap();
    external_effects::record_activity(&mut tx, "activity", "artist", "bookingRequest", "booking")
        .await
        .unwrap();
    tx.commit().await.unwrap();

    let (apple, url) = apple().await;
    let temp = tempfile::tempdir().unwrap();
    let worker = worker(pool.clone(), temp.path(), &url);
    assert!(worker.deliver_one().await.unwrap());
    {
        let requests = apple.requests.lock().unwrap();
        let (path, headers, body) = &requests[0];
        assert_eq!(path, &format!("development:{APNS_TOKEN}"));
        assert_eq!(headers["apns-topic"], "com.intheloopstudio");
        assert_eq!(headers["apns-push-type"], "alert");
        let bearer = headers["authorization"].to_str().unwrap();
        let header = jsonwebtoken::decode_header(bearer.strip_prefix("Bearer ").unwrap()).unwrap();
        assert_eq!(header.alg, jsonwebtoken::Algorithm::ES256);
        assert_eq!(header.kid.as_deref(), Some("KEYID12345"));
        assert_eq!(body["bookingId"], "booking");
        assert_eq!(body["activityId"], "activity");
        assert_eq!(body["aps"]["sound"], "default");
        assert!(body["aps"]["alert"]["title"].is_string());
    }

    apple.status.store(410, Ordering::SeqCst);
    let mut tx = pool.begin().await.unwrap();
    external_effects::record_activity(&mut tx, "second", "artist", "bookingUpdate", "booking")
        .await
        .unwrap();
    tx.commit().await.unwrap();
    assert!(worker.deliver_one().await.unwrap());
    let remaining: i64 = sqlx::query_scalar("SELECT count(*) FROM device_tokens")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        remaining, 0,
        "APNs 410 Unregistered removes the device token"
    );
    let undelivered: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM external_effect_outbox WHERE delivered_at IS NULL",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(undelivered, 0);
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn apns_pushes_wait_in_the_outbox_until_a_key_is_configured() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    seed_artist(&pool).await;
    register(
        &pool,
        json!({"token":APNS_TOKEN,"platform":"ios","provider":"apns","environment":"production"}),
    )
    .await
    .unwrap();
    let mut tx = pool.begin().await.unwrap();
    external_effects::record_activity(&mut tx, "activity", "artist", "bookingRequest", "booking")
        .await
        .unwrap();
    tx.commit().await.unwrap();
    let temp = tempfile::tempdir().unwrap();
    let mut worker = worker(pool.clone(), temp.path(), "http://127.0.0.1:9");
    worker.apns = None;
    assert!(worker.deliver_one().await.unwrap());
    let (retained, tokens): (i64, i64) = sqlx::query_as(
        "SELECT (SELECT count(*) FROM external_effect_outbox WHERE delivered_at IS NULL),(SELECT count(*) FROM device_tokens)",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!((retained, tokens), (1, 1));
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn app_config_serves_launch_gates_from_postgres() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    let mut state = mock_state();
    state.postgres = Some(pool.clone());
    let app = spawn_app_with_state(state).await;
    let url = format!("{}/app/v1/public/app-config", app.address);
    let response = app.api_client.get(&url).send().await.unwrap();
    assert_eq!(response.status(), 200);
    assert_eq!(
        response.headers()["cache-control"],
        "public, max-age=30, s-maxage=30"
    );
    assert_eq!(
        response.json::<Value>().await.unwrap(),
        json!({"downForMaintenance":false,"bookingFee":0.0,"iosMinimumAppVersion":"","iosLatestAppVersion":"","premiumWaitlistEnabled":false})
    );
    sqlx::query("UPDATE app_config SET down_for_maintenance=true,ios_minimum_app_version='2.0.0'")
        .execute(&pool)
        .await
        .unwrap();
    let config: Value = app
        .api_client
        .get(&url)
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(config["downForMaintenance"], true);
    assert_eq!(config["iosMinimumAppVersion"], "2.0.0");
    assert!(
        sqlx::query("INSERT INTO app_config(id) VALUES(false)")
            .execute(&pool)
            .await
            .is_err(),
        "app_config is a single row"
    );
    cleanup(pool, admin, name).await;
}
