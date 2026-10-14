use super::{
    external_effects::{cleanup, database},
    helpers::mock_state,
};
use axum::{
    Json,
    extract::{Path, State},
};
use serde_json::{Value, json};
use tapped_api_rs::domain::{
    app_data::{self, DocumentPath},
    firebase_auth::FirebaseUser,
};

fn request(id: &str) -> Value {
    let start = chrono::Utc::now() + chrono::Duration::days(2);
    json!({"id":id,"requesterId":"requester","requesteeId":"requestee","status":"pending","startTime":start,"endTime":start+chrono::Duration::hours(2)})
}

#[tokio::test]
async fn booking_mutations_enqueue_exact_role_templates_once_and_not_for_imports_or_updates() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    sqlx::query("INSERT INTO users(id,username,email) VALUES('requester','requester','requester@example.test'),('requestee','requestee','requestee@example.test')").execute(&pool).await.unwrap();
    // Imported historical records never replay email.
    sqlx::query("INSERT INTO bookings(id,requester_id,requestee_id,status) VALUES('imported','requester','requestee','pending')").execute(&pool).await.unwrap();
    let mut state = mock_state();
    state.postgres = Some(pool.clone());
    let requester = FirebaseUser {
        uid: "requester".into(),
        email: Some("requester@example.test".into()),
    };
    let input = request("request");
    let _ = app_data::create(
        State(state.clone()),
        requester.clone(),
        Path("bookings".into()),
        Json(input.clone()),
    )
    .await
    .unwrap();
    let rows:Vec<(String,String,String)>=sqlx::query_as("SELECT id,payload->>'to',payload->>'template' FROM external_effect_outbox WHERE kind='mail' ORDER BY id").fetch_all(&pool).await.unwrap();
    assert_eq!(
        rows,
        vec![
            (
                "booking-mail:request:bookingRequestReceived".into(),
                "requestee@example.test".into(),
                "bookingRequestReceived".into()
            ),
            (
                "booking-mail:request:bookingRequestSent".into(),
                "requester@example.test".into(),
                "bookingRequestSent".into()
            )
        ]
    );
    assert_eq!(
        app_data::create(
            State(state.clone()),
            requester.clone(),
            Path("bookings".into()),
            Json(input)
        )
        .await
        .unwrap_err()
        .status,
        409
    );
    let _ = app_data::update(
        State(state),
        requester,
        Path(DocumentPath::from(("bookings".into(), "request".into()))),
        Json(json!({"note":"edited"})),
    )
    .await
    .unwrap();
    assert_eq!(
        sqlx::query_scalar::<_, i64>(
            "SELECT count(*) FROM external_effect_outbox WHERE kind='mail'"
        )
        .fetch_one(&pool)
        .await
        .unwrap(),
        2
    );
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn booking_email_queue_failure_rolls_back_booking_activity_and_other_effects() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    sqlx::query("INSERT INTO users(id,username,email) VALUES('requester','requester','requester@example.test'),('requestee','requestee','requestee@example.test')").execute(&pool).await.unwrap();
    sqlx::query(
        "ALTER TABLE external_effect_outbox ADD CONSTRAINT fail_mail_for_test CHECK(kind<>'mail')",
    )
    .execute(&pool)
    .await
    .unwrap();
    let mut state = mock_state();
    state.postgres = Some(pool.clone());
    let user = FirebaseUser {
        uid: "requester".into(),
        email: Some("requester@example.test".into()),
    };
    assert_eq!(
        app_data::create(
            State(state),
            user,
            Path("bookings".into()),
            Json(request("rolled-back"))
        )
        .await
        .unwrap_err()
        .status,
        500
    );
    let counts:(i64,i64,i64,i64)=sqlx::query_as("SELECT (SELECT count(*) FROM bookings),(SELECT count(*) FROM activities),(SELECT count(*) FROM external_effect_outbox),(SELECT count(*) FROM founder_notification_outbox)").fetch_one(&pool).await.unwrap();
    assert_eq!(counts, (0, 0, 0, 0));
    cleanup(pool, admin, name).await;
}
