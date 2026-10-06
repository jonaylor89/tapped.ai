use crate::helpers::spawn_app;
use axum::http::StatusCode;

#[tokio::test]
async fn user_search_sync_requires_firebase_token() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .post(format!("{}/app/v1/search/users/sync", app.address))
        .send()
        .await
        .expect("Failed to execute request");

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn user_search_sync_rejects_malformed_token() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .post(format!("{}/app/v1/search/users/sync", app.address))
        .bearer_auth("not-a-jwt")
        .send()
        .await
        .expect("Failed to execute request");

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}
