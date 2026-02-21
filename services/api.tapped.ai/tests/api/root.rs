use crate::helpers::spawn_app;

#[tokio::test]
async fn root_returns_ok() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(&format!("{}/", &app.address))
        .send()
        .await
        .expect("Failed to execute request");

    assert!(response.status().is_success());
}

#[tokio::test]
async fn version_returns_ok() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(&format!("{}/version", &app.address))
        .send()
        .await
        .expect("Failed to execute request");

    assert!(response.status().is_success());
    let body: serde_json::Value = response.json().await.unwrap();
    assert!(body.get("version").is_some());
}
