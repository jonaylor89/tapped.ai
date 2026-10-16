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
    commands,
    firebase_auth::FirebaseUser,
};

#[tokio::test]
async fn domain_commands_use_canonical_facts_and_read_only_statistics() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    let mut state = mock_state();
    state.postgres = Some(pool.clone());
    let artist = FirebaseUser {
        uid: "artist".into(),
        email: None,
    };
    let venue = FirebaseUser {
        uid: "venue".into(),
        email: None,
    };
    for actor in [&artist, &venue] {
        let _ = commands::create_profile(State(state.clone()),actor.clone(),Json(json!({"id":actor.uid,"username":actor.uid,"performerInfo":{"genres":["Jazz"],"label":"Independent","bookingCount":999,"reviewCount":99,"rating":5},"venueInfo":{"capacity":100,"topPerformerIds":["fake"]}}))).await.unwrap();
    }
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM profile_owners")
            .fetch_one(&pool)
            .await
            .unwrap(),
        2
    );
    let (profile, genres): (Value, Vec<String>) =
        sqlx::query_as("SELECT profile,performer_genres FROM users WHERE id='artist'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert!(profile["performerInfo"].get("bookingCount").is_none());
    assert!(profile.get("username").is_none());
    assert_eq!(genres, vec!["Jazz"]);
    sqlx::query("INSERT INTO services(id,user_id,count) VALUES('service','artist',999)")
        .execute(&pool)
        .await
        .unwrap();
    let start = chrono::Utc::now() + chrono::Duration::days(2);
    let _ = commands::request_booking(State(state.clone()),venue.clone(),Json(json!({"id":"booking","requesterId":"venue","requesteeId":"artist","serviceId":"service","status":"pending","startTime":start,"endTime":start+chrono::Duration::hours(1)}))).await.unwrap();
    assert_eq!(
        commands::accept_booking(
            State(state.clone()),
            venue.clone(),
            Path("booking".into()),
            None
        )
        .await
        .unwrap_err()
        .status,
        403
    );
    let _ = commands::accept_booking(
        State(state.clone()),
        artist.clone(),
        Path("booking".into()),
        None,
    )
    .await
    .unwrap();
    let doc = app_data::document(&pool, "users", "artist")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(doc["performerInfo"]["bookingCount"], 1);
    assert_eq!(doc["performerInfo"]["completedBookingCount"], 0);
    assert_eq!(
        commands::profile_stats(State(state.clone()), Path("artist".into()))
            .await
            .unwrap()
            .0["confirmedBookingCount"],
        1
    );
    assert_eq!(
        app_data::document(&pool, "services", "service")
            .await
            .unwrap()
            .unwrap()["count"],
        1
    );
    let _ = commands::submit_review(State(state.clone()),venue.clone(),Json(json!({"id":"review","type":"performer","bookerId":"venue","performerId":"artist","bookingId":"booking","overallRating":4,"overallReview":"Great"}))).await.unwrap();
    assert_eq!(commands::submit_review(State(state.clone()),venue.clone(),Json(json!({"id":"duplicate","type":"performer","bookerId":"venue","performerId":"artist","bookingId":"booking","overallRating":5,"overallReview":"Duplicate"}))).await.unwrap_err().status,409);
    let doc = app_data::document(&pool, "users", "artist")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(doc["performerInfo"]["rating"], 4);
    assert_eq!(doc["performerInfo"]["reviewCount"], 1);
    let _ = commands::cancel_booking(
        State(state.clone()),
        venue.clone(),
        Path("booking".into()),
        None,
    )
    .await
    .unwrap();
    assert_eq!(
        app_data::document(&pool, "users", "artist")
            .await
            .unwrap()
            .unwrap()["performerInfo"]["bookingCount"],
        0
    );
    assert_eq!(
        app_data::document(&pool, "services", "service")
            .await
            .unwrap()
            .unwrap()["count"],
        0
    );
    let _ = app_data::update(
        State(state.clone()),
        artist.clone(),
        Path(DocumentPath::from(("services".into(), "service".into()))),
        Json(json!({"count":77})),
    )
    .await
    .unwrap();
    assert_eq!(
        sqlx::query_scalar::<_, i32>("SELECT count FROM services WHERE id='service'")
            .fetch_one(&pool)
            .await
            .unwrap(),
        999
    );
    sqlx::query("UPDATE accounts SET disabled=true WHERE auth_uid='artist'")
        .execute(&pool)
        .await
        .unwrap();
    assert_eq!(
        commands::update_profile(
            State(state),
            artist,
            Path("artist".into()),
            Json(json!({"bio":"Cannot resurrect"}))
        )
        .await
        .unwrap_err()
        .status,
        403
    );
    assert!(
        sqlx::query(
            "INSERT INTO bookings(id,requestee_id,status) VALUES('bad','missing','confirmed')"
        )
        .execute(&pool)
        .await
        .is_err()
    );
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn restricted_observations_are_retryable_and_never_create_profiles_bookings_or_effects() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    sqlx::query("INSERT INTO users(id,username,profile,email) VALUES('venue','venue','{\"venueInfo\":{\"genres\":[\"Jazz\"],\"capacity\":300}}','private@example.test')").execute(&pool).await.unwrap();
    let mut conn = pool.acquire().await.unwrap();
    sqlx::query("SET ROLE tapped_ingestion")
        .execute(&mut *conn)
        .await
        .unwrap();
    for statement in [
        "SELECT * FROM accounts",
        "UPDATE users SET unclaimed=false",
        "SELECT * FROM legacy_profile_archive",
        "INSERT INTO external_effect_outbox(id,kind,payload) VALUES('bad','auth_signup','{}')",
        "SELECT ingest_scraped_event('test','event','venue','{}')",
        "SELECT ingest_unclaimed_artist('Nova')",
        "UPDATE scrape_results SET payload='{}'",
        "UPDATE scraped_events SET publication_state='published'",
    ] {
        assert_eq!(
            sqlx::query(statement)
                .execute(&mut *conn)
                .await
                .unwrap_err()
                .as_database_error()
                .unwrap()
                .code()
                .unwrap(),
            "42501"
        );
    }
    let doc: Value = sqlx::query_scalar("SELECT doc FROM ingestion_profiles WHERE id='venue'")
        .fetch_one(&mut *conn)
        .await
        .unwrap();
    assert_eq!(doc["email"], "");
    let evidence = json!({
        "bucket":"tapped-scrape-private-test",
        "key":format!("archive/aa/{}.gz", "a".repeat(64)),
        "sha256":"a".repeat(64), "bytes":100,
        "contentType":"application/x-ndjson", "contentEncoding":"gzip"
    });
    let object_id: i64 = sqlx::query_scalar("SELECT register_scrape_object($1)")
        .bind(evidence)
        .fetch_one(&mut *conn)
        .await
        .unwrap();
    let payload = json!([{
        "source":"test", "sourceKey":"event", "deliveryKey":"first",
        "venueId":"venue", "parserVersion":"test-v1",
        "observedAt":"2020-01-02T00:00:00Z", "evidenceId":object_id, "errors":[],
        "facts":{
            "musicClassification":"music", "performers":["Nova","Echo"],
            "startTime":"2030-12-01T20:00:00Z", "endTime":null,
            "title":"Show", "prices":[{"kind":"ticket","amountMin":25,"currency":null}]
        }
    }]);
    let mut event = Value::Null;
    for expected in ["inserted", "duplicate"] {
        let result: Value =
            sqlx::query_scalar("SELECT to_jsonb(r) FROM record_scrape_observations($1) r")
                .bind(&payload)
                .fetch_one(&mut *conn)
                .await
                .unwrap();
        assert_eq!(result["action"], expected);
        event = result["event_id"].clone();
    }
    let mut invalid = payload.clone();
    invalid[0]["sourceKey"] = json!("bad-event");
    invalid[0]["deliveryKey"] = json!("bad-delivery");
    invalid[0]["facts"]["startTime"] = json!("not-a-time");
    let rejected: Value =
        sqlx::query_scalar("SELECT to_jsonb(r) FROM record_scrape_observations($1) r")
            .bind(invalid)
            .fetch_one(&mut *conn)
            .await
            .unwrap();
    assert_eq!(rejected["action"], "quarantined");
    assert!(rejected["event_id"].is_null());
    let mut older = payload.clone();
    older[0]["deliveryKey"] = json!("older");
    older[0]["observedAt"] = json!("2020-01-01T00:00:00Z");
    older[0]["facts"]["title"] = json!("Stale");
    let historical: Value =
        sqlx::query_scalar("SELECT to_jsonb(r) FROM record_scrape_observations($1) r")
            .bind(older)
            .fetch_one(&mut *conn)
            .await
            .unwrap();
    assert_eq!(historical["action"], "historical");
    sqlx::query("RESET ROLE").execute(&mut *conn).await.unwrap();
    drop(conn);
    assert_eq!(
        sqlx::query_scalar::<_, String>("SELECT title FROM scraped_events WHERE event_id=$1")
            .bind(event.as_str().unwrap())
            .fetch_one(&pool)
            .await
            .unwrap(),
        "Show"
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>(
            "SELECT count(*) FROM event_performers WHERE profile_id IS NULL"
        )
        .fetch_one(&pool)
        .await
        .unwrap(),
        2
    );
    for table in [
        "accounts",
        "profile_owners",
        "external_effect_outbox",
        "activities",
        "bookings",
    ] {
        assert_eq!(
            sqlx::query_scalar::<_, i64>(sqlx::AssertSqlSafe(format!(
                "SELECT count(*) FROM {table}"
            )))
            .fetch_one(&pool)
            .await
            .unwrap(),
            0
        );
    }
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM users")
            .fetch_one(&pool)
            .await
            .unwrap(),
        1
    );
    cleanup(pool, admin, name).await;
}
