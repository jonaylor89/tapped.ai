use crate::helpers::spawn_app;

#[tokio::test]
async fn get_performer_by_id_returns_performer() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(&format!("{}/v1/performer/user-123", &app.address))
        .header("tapped-api-key", "test-key")
        .send()
        .await
        .expect("Failed to execute request");

    assert!(response.status().is_success());
    let body: serde_json::Value = response.json().await.unwrap();
    assert_eq!(body.get("id").and_then(|v| v.as_str()), Some("user-123"));
}

#[tokio::test]
async fn get_performer_by_username_returns_performer() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(&format!("{}/v1/performer/username/testuser", &app.address))
        .header("tapped-api-key", "test-key")
        .send()
        .await
        .expect("Failed to execute request");

    assert!(response.status().is_success());
    let body: serde_json::Value = response.json().await.unwrap();
    assert_eq!(
        body.get("username").and_then(|v| v.as_str()),
        Some("testuser")
    );
}

#[tokio::test]
async fn search_performers_returns_empty_array() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(&format!("{}/v1/performer/search?query=test", &app.address))
        .header("tapped-api-key", "test-key")
        .send()
        .await
        .expect("Failed to execute request");

    assert!(response.status().is_success());
    let body: serde_json::Value = response.json().await.unwrap();
    assert!(body.is_array());
}
