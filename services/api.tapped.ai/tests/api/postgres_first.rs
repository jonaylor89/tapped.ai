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
async fn restricted_ingestion_is_atomic_retryable_and_never_creates_accounts_or_notifications() {
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
    let mut payload = json!({"isMusicEvent":true,"performers":["Nova","Nova","Echo"],"startTime":"2026-12-01T20:00:00Z","endTime":"2026-12-01T22:00:00Z","title":"Show","ticketPrice":25});
    let mut event = String::new();
    for _ in 0..2 {
        event = sqlx::query_scalar("SELECT ingest_scraped_event('test','event','venue',$1)")
            .bind(&payload)
            .fetch_one(&mut *conn)
            .await
            .unwrap();
    }
    let mut invalid = payload.clone();
    invalid["performers"] = json!(["Should Roll Back", ""]);
    assert!(
        sqlx::query("SELECT ingest_scraped_event('test','bad-event','venue',$1)")
            .bind(invalid)
            .execute(&mut *conn)
            .await
            .is_err()
    );
    payload["performers"] = json!(["Nova"]);
    sqlx::query("SELECT ingest_scraped_event('test','event','venue',$1)")
        .bind(&payload)
        .execute(&mut *conn)
        .await
        .unwrap();
    sqlx::query("RESET ROLE").execute(&mut *conn).await.unwrap();
    drop(conn);
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM bookings WHERE status='confirmed'")
            .fetch_one(&pool)
            .await
            .unwrap(),
        1
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM bookings WHERE reference_event_id=$1")
            .bind(event)
            .fetch_one(&pool)
            .await
            .unwrap(),
        2
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM scraped_event_revisions")
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
        sqlx::query_scalar::<_, i64>(
            "SELECT count(*) FROM users WHERE artist_name='Should Roll Back'"
        )
        .fetch_one(&pool)
        .await
        .unwrap(),
        0
    );
    // A member cannot cause ingestion to overwrite a native booking with a guessed reserved ID.
    let collision:String=sqlx::query_scalar("SELECT \'scraped-booking-\'||md5((\'scraped-\'||md5(\'test:native-collision\'))||\':\'||id) FROM users WHERE username=\'nova\'").fetch_one(&pool).await.unwrap();
    sqlx::query("INSERT INTO bookings(id,requester_id,requestee_id,status,note) SELECT $1,\'venue\',id,\'pending\',\'native note\' FROM users WHERE username=\'nova\'").bind(&collision).execute(&pool).await.unwrap();
    assert!(
        sqlx::query("SELECT ingest_scraped_event(\'test\',\'native-collision\',\'venue\',$1)")
            .bind(&payload)
            .execute(&pool)
            .await
            .is_err()
    );
    assert_eq!(
        sqlx::query_scalar::<_, String>("SELECT note FROM bookings WHERE id=$1")
            .bind(collision)
            .fetch_one(&pool)
            .await
            .unwrap(),
        "native note"
    );
    payload["isMusicEvent"] = json!(false);
    sqlx::query("SELECT ingest_scraped_event('test','event','venue',$1)")
        .bind(payload)
        .execute(&pool)
        .await
        .unwrap();
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM bookings WHERE status='confirmed'")
            .fetch_one(&pool)
            .await
            .unwrap(),
        0
    );
    cleanup(pool, admin, name).await;
}
