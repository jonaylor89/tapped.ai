use crate::helpers::spawn_app;

#[tokio::test]
async fn place_details_are_public() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(format!("{}/app/v1/places/ChIJmockPlace", app.address))
        .header("Origin", "https://tapped.ai")
        .send()
        .await
        .expect("Failed to execute request");

    assert!(response.status().is_success());
    assert_eq!(
        response
            .headers()
            .get("access-control-allow-origin")
            .and_then(|v| v.to_str().ok()),
        Some("*")
    );
    let body: serde_json::Value = response.json().await.unwrap();
    assert_eq!(body["placeId"], "ChIJmockPlace");
    assert_eq!(body["name"], "Mock Place");
}

#[tokio::test]
async fn place_details_reject_unsafe_ids() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(format!("{}/app/v1/places/bad%3Fkey%3Dx", app.address))
        .send()
        .await
        .expect("Failed to execute request");

    assert_eq!(response.status(), reqwest::StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn other_places_endpoints_require_firebase_auth() {
    let app = spawn_app().await;

    for path in [
        "places/autocomplete?query=richmond",
        "places/photo?name=places/x/photos/y",
        "places/reverse-geocode?lat=37.5&lng=-77.4",
    ] {
        let response = app
            .api_client
            .get(format!("{}/app/v1/{path}", app.address))
            .send()
            .await
            .expect("Failed to execute request");

        assert_eq!(response.status(), reqwest::StatusCode::UNAUTHORIZED, "{path}");
    }
}
