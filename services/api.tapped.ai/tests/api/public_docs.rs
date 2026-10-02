use crate::helpers::spawn_app;

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
