use crate::helpers::spawn_app;
use axum::http::StatusCode;

#[tokio::test]
async fn public_user_by_username_omits_private_fields() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(format!("{}/app/v1/users/username/dj_nova", app.address))
        .send()
        .await
        .expect("Failed to execute request");

    assert!(response.status().is_success());
    let body: serde_json::Value = response.json().await.unwrap();
    assert_eq!(body["username"], "dj_nova");
    assert_eq!(body["artistName"], "Mock Artist");
    assert!(body.get("email").is_none());
    assert!(body.get("stripeCustomerId").is_none());
    assert!(body.get("_firestore_id").is_none());
    assert_eq!(body["venueInfo"]["capacity"], 100);
    assert!(body["venueInfo"].get("bookingEmail").is_none());
}

#[tokio::test]
async fn public_opportunity_by_id() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(format!("{}/app/v1/opportunities/opp-1", app.address))
        .send()
        .await
        .expect("Failed to execute request");

    assert!(response.status().is_success());
    let body: serde_json::Value = response.json().await.unwrap();
    assert_eq!(body["id"], "opp-1");
    assert_eq!(body["title"], "Mock Opportunity");
}

const CACHE_CONTROL_200: &str = "public, max-age=60, s-maxage=300, stale-while-revalidate=600";
const CACHE_CONTROL_404: &str = "public, max-age=30, s-maxage=60";

async fn get(path: &str) -> reqwest::Response {
    let app = spawn_app().await;
    app.api_client
        .get(format!("{}{path}", app.address))
        .send()
        .await
        .expect("Failed to execute request")
}

fn cache_control(response: &reqwest::Response) -> Option<&str> {
    response
        .headers()
        .get("cache-control")
        .map(|value| value.to_str().unwrap())
}

#[tokio::test]
async fn found_public_docs_are_edge_cacheable() {
    for path in ["/app/v1/users/username/dj_nova"] {
        let response = get(path).await;
        assert_eq!(response.status(), StatusCode::OK, "{path}");
        assert_eq!(cache_control(&response), Some(CACHE_CONTROL_200), "{path}");
    }
}

#[tokio::test]
async fn missing_public_docs_are_negatively_cached_briefly() {
    // A second read is served from the process cache and must carry the same header.
    for path in ["/app/v1/users/username/missing"] {
        let app = spawn_app().await;
        for _ in 0..2 {
            let response = app
                .api_client
                .get(format!("{}{path}", app.address))
                .send()
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::NOT_FOUND, "{path}");
            assert_eq!(cache_control(&response), Some(CACHE_CONTROL_404), "{path}");
            let body: serde_json::Value = response.json().await.unwrap();
            assert!(body["error_id"].is_string(), "{body}");
        }
    }
}

#[tokio::test]
async fn public_opportunities_are_never_cached() {
    for (path, status) in [
        ("/app/v1/opportunities/opp-1", StatusCode::OK),
        ("/app/v1/opportunities/missing", StatusCode::NOT_FOUND),
        ("/app/v1/opportunities/bad%20id", StatusCode::BAD_REQUEST),
    ] {
        let response = get(path).await;
        assert_eq!(response.status(), status);
        assert_eq!(cache_control(&response), Some("no-store"));
    }
}

#[tokio::test]
async fn public_opportunities_ignore_stale_process_snapshots() {
    let state = crate::helpers::mock_state();
    state.response_cache.insert(
        "public-opportunity:opp-1".into(),
        serde_json::json!({"id":"opp-1","title":"stale snapshot"}),
        std::time::Duration::from_secs(300),
    );
    // The authoritative row is now absent, as after deletion; a cached positive must not survive.
    state.response_cache.insert(
        "public-opportunity:missing".into(),
        serde_json::json!({"id":"missing","title":"deleted opportunity"}),
        std::time::Duration::from_secs(300),
    );
    let app = crate::helpers::spawn_app_with_state(state).await;
    let response = app
        .api_client
        .get(format!("{}/app/v1/opportunities/opp-1", app.address))
        .send()
        .await
        .unwrap();
    assert_eq!(cache_control(&response), Some("no-store"));
    let doc: serde_json::Value = response.json().await.unwrap();
    assert_eq!(doc["title"], "Mock Opportunity");
    let missing = app
        .api_client
        .get(format!("{}/app/v1/opportunities/missing", app.address))
        .send()
        .await
        .unwrap();
    assert_eq!(missing.status(), StatusCode::NOT_FOUND);
    assert_eq!(cache_control(&missing), Some("no-store"));
}

#[tokio::test]
async fn invalid_public_doc_ids_are_not_cached() {
    let response = get("/app/v1/users/username/bad%20name").await;
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    assert_eq!(cache_control(&response), None);
}
