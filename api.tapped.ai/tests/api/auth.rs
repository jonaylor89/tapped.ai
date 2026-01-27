use crate::helpers::spawn_app;
use axum::http::StatusCode;

#[tokio::test]
async fn v1_routes_reject_missing_api_key() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(&format!("{}/v1/performer/test-id", &app.address))
        .send()
        .await
        .expect("Failed to execute request");

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn v1_routes_accept_valid_api_key() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(&format!("{}/v1/performer/test-id", &app.address))
        .header("tapped-api-key", "any-key-works-with-mock")
        .send()
        .await
        .expect("Failed to execute request");

    assert!(response.status().is_success());
}

#[tokio::test]
async fn search_performers_requires_api_key() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(&format!("{}/v1/performer/search", &app.address))
        .send()
        .await
        .expect("Failed to execute request");

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn search_performers_works_with_api_key() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(&format!("{}/v1/performer/search", &app.address))
        .header("tapped-api-key", "test-key")
        .send()
        .await
        .expect("Failed to execute request");

    assert!(response.status().is_success());
}
