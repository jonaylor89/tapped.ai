use super::helpers::mock_state;
use axum::{
    Json,
    extract::{Path, Query, State},
};
use serde_json::{Value, json};
use tapped_api_rs::{
    data::{database::Database, pg_database::PostgresDatabase, postgres::connect},
    domain::{
        app_data::{self, DocumentPath, ListParams},
        firebase_auth::FirebaseUser,
    },
};

/// Real PostGIS repository/handler round trips, including mirrored legacy review IDs.
#[tokio::test]
async fn postgres_serves_owned_records_and_public_projections_without_firestore() {
    let Ok(url) = std::env::var("DATABASE_URL") else {
        eprintln!("DATABASE_URL unset; skipping PostGIS round trip");
        return;
    };
    let pool = connect(&url).await.unwrap();
    let mut state = mock_state();
    state.postgres = Some(pool.clone());
    let repository = PostgresDatabase::new(pool.clone());
    state.database = std::sync::Arc::new(repository.clone());
    let suffix = uuid::Uuid::new_v4().to_string();
    let a = FirebaseUser {
        uid: format!("artist-{suffix}"),
        email: Some("artist@example.test".into()),
    };
    let b = FirebaseUser {
        uid: format!("booker-{suffix}"),
        email: Some("booker@example.test".into()),
    };
    let stranger = FirebaseUser {
        uid: format!("stranger-{suffix}"),
        email: None,
    };
    for user in [&a, &b] {
        let _ = app_data::create(State(state.clone()),user.clone(),Path("users".into()),Json(json!({
    "id":user.uid,"username":user.uid,"artistName":"test","location":{"lat":38.9,"lng":-77.0,"placeId":"place"},
    "performerInfo":{"genres":["rock"],"label":"Independent"}
  }))).await.unwrap();
    }
    assert_eq!(repository.get_user_by_id(&a.uid).await.unwrap().id, a.uid);
    let Json(public) = app_data::get_public(
        State(state.clone()),
        Path(DocumentPath::from(("users".into(), a.uid.clone()))),
        Query(ListParams::default()),
    )
    .await
    .unwrap();
    assert!(public.get("email").is_none());
    assert_eq!(public["location"]["lat"], 38.9);
    let Json(private) = app_data::get_private(
        State(state.clone()),
        a.clone(),
        Path(DocumentPath::from(("users".into(), a.uid.clone()))),
        Query(ListParams::default()),
    )
    .await
    .unwrap();
    assert_eq!(private["email"], "artist@example.test");
    let _ = app_data::update(
        State(state.clone()),
        a.clone(),
        Path(DocumentPath::from(("users".into(), a.uid.clone()))),
        Json(json!({"bio":"from Postgres"})),
    )
    .await
    .unwrap();
    assert_eq!(
        serde_json::to_value(repository.get_user_by_id(&a.uid).await.unwrap()).unwrap()["bio"],
        "from Postgres"
    );
    assert!(
        app_data::update(
            State(state.clone()),
            b.clone(),
            Path(DocumentPath::from(("users".into(), a.uid.clone()))),
            Json(json!({"bio":"stolen"}))
        )
        .await
        .is_err()
    );
    let booking = format!("booking-{suffix}");
    let time = "2026-10-20T19:00:00.123Z";
    let _ = app_data::create(State(state.clone()),b.clone(),Path("bookings".into()),Json(json!({
  "id":booking,"requesterId":b.uid,"requesteeId":a.uid,"status":"pending","startTime":time,"endTime":"2026-10-20T20:00:00Z",
  "timestamp":time,"rate":100,"name":"show","note":"private"
 }))).await.unwrap();
    assert!(
        app_data::get_public(
            State(state.clone()),
            Path(DocumentPath::from(("bookings".into(), booking.clone()))),
            Query(ListParams::default())
        )
        .await
        .is_err()
    );
    let _ = app_data::update(
        State(state.clone()),
        a.clone(),
        Path(DocumentPath::from(("bookings".into(), booking.clone()))),
        Json(json!({"status":"confirmed"})),
    )
    .await
    .unwrap();
    let played = repository
        .get_bookings_by_performer_id(&a.uid)
        .await
        .unwrap();
    assert_eq!(played.len(), 1);
    assert_eq!(played[0].note, "private");
    let Json(public) = app_data::get_public(
        State(state.clone()),
        Path(DocumentPath::from(("bookings".into(), booking.clone()))),
        Query(ListParams::default()),
    )
    .await
    .unwrap();
    assert!(public.get("note").is_none());
    assert!(public.get("rate").is_none());
    let review = format!("review-{suffix}");
    for (kind, user) in [("performer", &b), ("booker", &a)] {
        let _ = app_data::create(State(state.clone()),user.clone(),Path("reviews".into()),Json(json!({
   "id":review,"type":kind,"bookerId":b.uid,"performerId":a.uid,"bookingId":booking,"timestamp":time,"overallRating":5,"overallReview":"great"
  }))).await.unwrap();
    }
    assert_eq!(
        repository
            .get_reviews_by_performer_id(&a.uid)
            .await
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        repository
            .get_reviews_by_booker_id(&b.uid)
            .await
            .unwrap()
            .len(),
        1
    );
    let Json(reviews) = app_data::list_public(
        State(state.clone()),
        Path("reviews".into()),
        Query(ListParams {
            user_id: Some(a.uid.clone()),
            review_type: Some("performer".into()),
            ..Default::default()
        }),
    )
    .await
    .unwrap();
    assert_eq!(reviews.as_array().unwrap().len(), 1);
    // Exercise every list SQL branch (including timestamp and cursor ordering).
    for table in ["services", "activities", "opportunities"] {
        let query = ListParams {
            user_id: Some(a.uid.clone()),
            ..Default::default()
        };
        let _ = app_data::list_private(
            State(state.clone()),
            a.clone(),
            Path(table.into()),
            Query(query),
        )
        .await
        .unwrap();
    }
    let Json(rows) = app_data::list_public(
        State(state.clone()),
        Path("bookings".into()),
        Query(ListParams {
            requestee_id: Some(a.uid.clone()),
            order: Some("timestamp".into()),
            ..Default::default()
        }),
    )
    .await
    .unwrap();
    assert_eq!(rows.as_array().unwrap().len(), 1);
    assert!(
        app_data::list_private(
            State(state.clone()),
            stranger,
            Path("activities".into()),
            Query(ListParams {
                user_id: Some(a.uid.clone()),
                ..Default::default()
            })
        )
        .await
        .is_err()
    );
    let service = format!("service-{suffix}");
    let _ = app_data::create(
        State(state.clone()),
        a.clone(),
        Path("services".into()),
        Json(json!({"id":service,"userId":a.uid,"title":"DJ","rate":100})),
    )
    .await
    .unwrap();
    assert!(
        app_data::update(
            State(state.clone()),
            b.clone(),
            Path(DocumentPath::from(("services".into(), service.clone()))),
            Json(json!({"userId":b.uid}))
        )
        .await
        .is_err()
    );
    let opportunity = format!("opportunity-{suffix}");
    let _ = app_data::create(State(state.clone()),b.clone(),Path("opportunities".into()),Json(json!({
  "id":opportunity,"userId":b.uid,"title":"gig","startTime":time,"endTime":"2026-10-20T20:00:00Z","timestamp":time
 }))).await.unwrap();
    let _ = app_data::set_interest(
        State(state.clone()),
        a.clone(),
        Path(opportunity.clone()),
        Json(json!({"action":"apply","userComment":"private comment"})),
    )
    .await
    .unwrap();
    let Json(interested) = app_data::interests(State(state.clone()), Path(opportunity.clone()))
        .await
        .unwrap();
    assert_eq!(interested[0]["id"], a.uid);
    assert!(interested[0].get("email").is_none());
    let _ = app_data::list_private(
        State(state.clone()),
        a.clone(),
        Path("opportunities".into()),
        Query(ListParams {
            user_id: Some(a.uid.clone()),
            mode: Some("applied".into()),
            ..Default::default()
        }),
    )
    .await
    .unwrap();
    let credential = format!("test-device-{suffix}");
    let _ = app_data::register_token(
        State(state.clone()),
        a.clone(),
        Json(json!({"token":credential,"platform":"ios"})),
    )
    .await
    .unwrap();
    let owner: String = sqlx::query_scalar("SELECT user_id FROM device_tokens WHERE token=$1")
        .bind(&credential)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(owner, a.uid);
    let hash = tapped_api_rs::domain::models::api_key::hash_api_key(&credential);
    sqlx::query("INSERT INTO api_keys(key_hash,user_id) VALUES($1,$2)")
        .bind(&hash)
        .bind(&a.uid)
        .execute(&pool)
        .await
        .unwrap();
    assert_eq!(
        repository.get_user_from_api_key(&credential).await.unwrap(),
        Some(a.uid.clone())
    );
    // Search must see an API write immediately, with no Firestore/Typesense indexer.
    use tapped_api_rs::data::pg_search::{PostgresSearch, SearchParams, documents};
    use tapped_api_rs::data::search::{Search, UserSearchOptionsBuilder};
    let params = SearchParams {
        q: a.uid.clone(),
        lat: Some(38.9),
        lng: Some(-77.0),
        genres: vec!["rock".into()],
        labels: vec!["Independent".into()],
        ..Default::default()
    };
    let result = documents(&pool, "users", &params, None).await.unwrap();
    assert!(result.iter().any(|v| v["id"] == a.uid));
    let Json(public_search) =
        app_data::search_public(State(state.clone()), Path("users".into()), Json(params))
            .await
            .unwrap();
    assert!(public_search[0].get("email").is_none());
    assert!(repository.get_user_by_id(&b.uid).await.is_ok());
    app_data::update(
        State(state.clone()),
        a.clone(),
        Path(DocumentPath::from(("users".into(), a.uid.clone()))),
        Json(json!({"performerInfo":null})),
    )
    .await
    .unwrap();
    let Json(protected) = app_data::get_private(
        State(state.clone()),
        a.clone(),
        Path(DocumentPath::from(("users".into(), a.uid.clone()))),
        Query(ListParams::default()),
    )
    .await
    .unwrap();
    assert_eq!(protected["performerInfo"]["reviewCount"], 1);
    assert_eq!(protected["performerInfo"]["rating"], 5);
    // Legacy non-finite metadata remains raw in storage, but not in serving models.
    sqlx::query("UPDATE users SET profile=jsonb_set(profile,'{performerInfo,rating}','\"NaN\"'::jsonb) WHERE id=$1").bind(&a.uid).execute(&pool).await.unwrap();
    assert!(repository.get_user_by_id(&a.uid).await.is_ok());
    let options = UserSearchOptionsBuilder::default()
        .hits_per_page(Some(5))
        .build()
        .unwrap();
    let users = PostgresSearch::new(pool.clone())
        .search_users(a.uid.clone(), options)
        .await
        .unwrap();
    assert_eq!(users[0].id, a.uid);
    let bounds = SearchParams {
        q: a.uid.clone(),
        sw_lat: Some(38.0),
        sw_lng: Some(-78.0),
        ne_lat: Some(40.0),
        ne_lng: Some(-76.0),
        ..Default::default()
    };
    assert!(
        documents(&pool, "users", &bounds, None)
            .await
            .unwrap()
            .iter()
            .any(|v| v["id"] == a.uid)
    );
    let invalid = SearchParams {
        lat: Some(91.0),
        lng: Some(0.0),
        ..Default::default()
    };
    assert!(invalid.validate().is_err());
    let invalid = SearchParams {
        sw_lat: Some(38.0),
        ..Default::default()
    };
    assert!(invalid.validate().is_err());
    let book = SearchParams {
        q: "show".into(),
        ..Default::default()
    };
    assert!(
        !documents(&pool, "bookings", &book, None)
            .await
            .unwrap()
            .is_empty()
    );
    let opportunities = SearchParams::default();
    assert!(
        !documents(&pool, "opportunities", &opportunities, None)
            .await
            .unwrap()
            .is_empty()
    );
    let Json(_) = app_data::remove(
        State(state.clone()),
        a.clone(),
        Path(DocumentPath::from(("users".into(), a.uid.clone()))),
    )
    .await
    .unwrap();
    assert!(repository.get_user_by_id(&a.uid).await.is_err());
    assert_eq!(
        repository.get_user_from_api_key(&credential).await.unwrap(),
        None
    );
    for (table, column, value) in [
        ("api_keys", "key_hash", hash),
        ("device_tokens", "token", credential),
        (
            "opportunity_interested_users",
            "opportunity_id",
            opportunity.clone(),
        ),
        ("opportunities", "id", opportunity),
        ("services", "id", service),
        ("reviews", "id", review),
        ("bookings", "id", booking),
        ("users", "id", a.uid),
        ("users", "id", b.uid),
    ] {
        sqlx::query(&format!("DELETE FROM {table} WHERE {column}=$1"))
            .bind(value)
            .execute(&pool)
            .await
            .unwrap();
    }
    let _: Value = public;
}
