use crate::helpers::spawn_app;
use axum::http::StatusCode;
use serde_json::Value;

async fn json_error(response: reqwest::Response, status: StatusCode) -> Value {
    assert_eq!(response.status(), status);
    assert_eq!(
        response.headers()["content-type"].to_str().unwrap(),
        "application/json"
    );
    let body: Value = response.json().await.unwrap();
    assert!(body["error"].is_string(), "{body}");
    assert!(body["error_id"].is_string(), "{body}");
    body
}

#[tokio::test]
async fn unknown_routes_return_a_json_404() {
    let app = spawn_app().await;
    let response = app
        .api_client
        .get(format!("{}/nope", app.address))
        .send()
        .await
        .unwrap();
    json_error(response, StatusCode::NOT_FOUND).await;
}

#[tokio::test]
async fn missing_api_key_is_a_json_401() {
    let app = spawn_app().await;
    let response = app
        .api_client
        .get(format!("{}/v1/performer/test-id", app.address))
        .send()
        .await
        .unwrap();
    let body = json_error(response, StatusCode::UNAUTHORIZED).await;
    assert!(body["error"].as_str().unwrap().contains("tapped-api-key"));
}

#[tokio::test]
async fn unknown_and_malformed_api_keys_are_rejected() {
    let app = spawn_app().await;
    for key in ["invalid-key", "../users/someone"] {
        let response = app
            .api_client
            .get(format!("{}/v1/performer/test-id", app.address))
            .header("tapped-api-key", key)
            .send()
            .await
            .unwrap();
        json_error(response, StatusCode::UNAUTHORIZED).await;
    }
}

#[tokio::test]
async fn malformed_coordinates_are_a_400_not_a_panic() {
    let app = spawn_app().await;
    for latlng in ["abc", "37.5", "1,2,3", "91,0"] {
        let response = app
            .api_client
            .get(format!("{}/v1/location/{latlng}", app.address))
            .header("tapped-api-key", "test-key")
            .send()
            .await
            .unwrap();
        json_error(response, StatusCode::BAD_REQUEST).await;
    }
}

#[tokio::test]
async fn extractor_rejections_are_json() {
    let app = spawn_app().await;
    let response = app
        .api_client
        .get(format!("{}/app/v1/places/autocomplete", app.address))
        .send()
        .await
        .unwrap();
    let body = json_error(response, StatusCode::BAD_REQUEST).await;
    assert!(body["error"].as_str().unwrap().contains("query"), "{body}");
}

#[tokio::test]
async fn validation_errors_explain_the_problem() {
    let app = spawn_app().await;
    let response = app
        .api_client
        .get(format!(
            "{}/app/v1/places/autocomplete?query=rich&types=a,b,c,d,e,f",
            app.address
        ))
        .send()
        .await
        .unwrap();
    let body = json_error(response, StatusCode::BAD_REQUEST).await;
    assert!(body["error"].as_str().unwrap().contains("types"), "{body}");
}

#[tokio::test]
async fn readiness_reports_each_dependency() {
    let app = spawn_app().await;
    let response = app
        .api_client
        .get(format!("{}/health/ready", app.address))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body: Value = response.json().await.unwrap();
    assert_eq!(body["status"], "ok");
    for check in ["firestore", "typesense", "mail_store"] {
        assert_eq!(body["checks"][check], "ok", "{body}");
    }
}

#[tokio::test]
async fn public_routes_are_rate_limited_per_client_ip() {
    let app = spawn_app().await;
    let url = format!("{}/app/v1/users/username/someone", app.address);
    let get = |ip: &'static str| {
        app.api_client
            .get(&url)
            .header("cf-connecting-ip", ip)
            .send()
    };

    let mut limited = None;
    for _ in 0..150 {
        let response = get("198.51.100.1").await.unwrap();
        if response.status() == StatusCode::TOO_MANY_REQUESTS {
            limited = Some(response);
            break;
        }
    }
    let response = limited.expect("expected a 429 within 150 requests");
    assert!(response.headers().contains_key("retry-after"));
    json_error(response, StatusCode::TOO_MANY_REQUESTS).await;

    let other_client = get("198.51.100.2").await.unwrap();
    assert_ne!(other_client.status(), StatusCode::TOO_MANY_REQUESTS);
}
