use super::{
    external_effects::{cleanup, database},
    helpers::{mock_state, spawn_app_with_state},
};
use axum::{
    Json, Router,
    extract::State,
    http::{HeaderMap, StatusCode},
    routing::patch,
};
use serde_json::Value;
use std::sync::{Arc, Mutex};
use tapped_api_rs::domain::{
    app_functions::{revoke_stream_user_tokens, stream_user_token},
    firebase_auth::FirebaseUser,
    mail_bridge::StreamHttpGateway,
};

#[derive(Default)]
struct Provider {
    requests: Mutex<Vec<Value>>,
    failed: Mutex<bool>,
}
async fn revoke(
    State(provider): State<Arc<Provider>>,
    headers: HeaderMap,
    Json(body): Json<Value>,
) -> StatusCode {
    assert_eq!(headers["Stream-Auth-Type"], "jwt");
    assert!(headers.contains_key("Authorization"));
    provider.requests.lock().unwrap().push(body);
    if *provider.failed.lock().unwrap() {
        StatusCode::SERVICE_UNAVAILABLE
    } else {
        StatusCode::OK
    }
}
#[tokio::test]
async fn stream_revocation_is_uid_bound_and_waits_for_provider_acceptance() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let provider = Arc::new(Provider::default());
    let router = Router::new()
        .route("/users", patch(revoke))
        .with_state(provider.clone());
    let server = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
    let mut state = mock_state();
    state.mail.stream = Arc::new(
        StreamHttpGateway::new("test-app-key".into(), "test-server-secret")
            .unwrap()
            .with_base_url(format!("http://{address}")),
    );
    let app = spawn_app_with_state(state.clone()).await;
    assert_eq!(
        app.api_client
            .post(format!("{}/app/v1/stream-token/revoke", app.address))
            .send()
            .await
            .unwrap()
            .status(),
        401
    );
    assert!(provider.requests.lock().unwrap().is_empty());
    let user = FirebaseUser {
        uid: "authenticated-user".into(),
        email: None,
    };
    assert_eq!(
        revoke_stream_user_tokens(State(state.clone()), user.clone())
            .await
            .unwrap(),
        204
    );
    let body = provider.requests.lock().unwrap()[0].clone();
    assert_eq!(body["users"][0]["id"], user.uid);
    let before = chrono::DateTime::parse_from_rfc3339(
        body["users"][0]["set"]["revoke_tokens_issued_before"]
            .as_str()
            .unwrap(),
    )
    .unwrap();
    assert!(before.timestamp().abs_diff(chrono::Utc::now().timestamp()) <= 1);
    *provider.failed.lock().unwrap() = true;
    assert_eq!(
        revoke_stream_user_tokens(State(state), user)
            .await
            .unwrap_err()
            .status,
        502
    );
    server.abort();
}
#[tokio::test]
async fn stream_tokens_have_issue_times_and_deleted_auth_accounts_cannot_mint_again() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    let mut state = mock_state();
    state.postgres = Some(pool.clone());
    let user = FirebaseUser {
        uid: "account".into(),
        email: None,
    };
    let Json(token) = stream_user_token(State(state.clone()), user.clone())
        .await
        .unwrap();
    let mut validation = jsonwebtoken::Validation::new(jsonwebtoken::Algorithm::HS256);
    validation.validate_exp = false;
    let decoded = jsonwebtoken::decode::<Value>(
        &token.token,
        &jsonwebtoken::DecodingKey::from_secret(state.mail.stream_webhook_secret.as_bytes()),
        &validation,
    )
    .unwrap();
    assert_eq!(decoded.claims["user_id"], "account");
    assert_eq!(
        decoded.claims["exp"].as_i64().unwrap() - decoded.claims["iat"].as_i64().unwrap(),
        3600
    );
    sqlx::query("INSERT INTO firebase_identities(uid,created_at_ms,scan_id,deleted) VALUES('account',1,$1,true)").bind(uuid::Uuid::new_v4()).execute(&pool).await.unwrap();
    assert_eq!(
        stream_user_token(State(state), user)
            .await
            .unwrap_err()
            .status,
        401
    );
    cleanup(pool, admin, name).await;
}
