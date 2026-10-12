use super::helpers::{mock_state, spawn_app, spawn_app_with_state};
use serde_json::{Value, json};
use tapped_api_rs::data::postgres::connect;

#[tokio::test]
async fn public_map_requires_valid_bounds_and_has_no_fallback_database() {
    let app = spawn_app().await;
    for query in [
        "",
        "swLat=20&neLat=10&swLng=0&neLng=1",
        "swLat=0&neLat=91&swLng=0&neLng=1",
        "swLat=0&neLat=10&swLng=NaN&neLng=1",
    ] {
        let response = app
            .api_client
            .get(format!("{}/app/v1/public/map?{query}", app.address))
            .send()
            .await
            .unwrap();
        assert!(response.status().is_client_error());
    }
    let response = app
        .api_client
        .get(format!(
            "{}/app/v1/public/map?swLat=0&neLat=10&swLng=0&neLng=1",
            app.address
        ))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), 503);
    assert_eq!(response.headers()["cache-control"], "no-store");
}

#[tokio::test]
async fn postgres_map_bundles_only_referenced_public_profiles_and_bounds_results() {
    let Ok(url) = std::env::var("DATABASE_URL") else {
        eprintln!("DATABASE_URL unset; skipping map PostGIS test");
        return;
    };
    let pool = connect(&url).await.unwrap();
    let mut state = mock_state();
    state.postgres = Some(pool.clone());
    let app = spawn_app_with_state(state).await;
    let prefix = format!("map-{}-", uuid::Uuid::new_v4());
    let pid = |name: &str| format!("{prefix}{name}");
    // Referenced performers are deduplicated; private fields and deleted/banned users never leave Rust.
    for (name, occupation, lon, deleted, banned, profile) in [
        (
            "venue",
            "Venue",
            175.0,
            false,
            false,
            json!({"venueInfo":{"capacity":100,"genres":["rock"],"bookingEmail":"private","phoneNumber":"private","topPerformerIds":[pid("artist"),pid("artist"),pid("gone"),pid("banned"),pid("missing")]},"credentials":"secret"}),
        ),
        (
            "west",
            "venue",
            -175.0,
            false,
            false,
            json!({"venueInfo":{"genres":["rock"]}}),
        ),
        (
            "artist",
            "performer",
            0.0,
            false,
            false,
            json!({"performerInfo":{"category":"emerging"},"pushNotifications":{"private":true},"stripeCustomerId":"secret"}),
        ),
        ("gone", "performer", 0.0, true, false, json!({})),
        ("banned", "performer", 0.0, false, true, json!({})),
        ("unreferenced", "performer", 175.0, false, false, json!({})),
        ("gone-venue", "venue", 175.0, true, false, json!({})),
        ("banned-venue", "venue", 175.0, false, true, json!({})),
    ] {
        sqlx::query("INSERT INTO users(id,username,email,artist_name,occupations,location,deleted,shadow_banned,profile) VALUES($1,$1,'private@example.test',$1,ARRAY[$2],ST_SetSRID(ST_MakePoint($3,55),4326)::geography,$4,$5,$6)")
            .bind(pid(name)).bind(occupation).bind(lon).bind(deleted).bind(banned).bind(profile).execute(&pool).await.unwrap();
    }
    let response = app
        .api_client
        .get(format!(
            "{}/app/v1/public/map?swLat=54&neLat=56&swLng=170&neLng=-170",
            app.address
        ))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), 200);
    assert_eq!(response.headers()["cache-control"], "no-store");
    let bundle: Value = response.json().await.unwrap();
    assert_eq!(bundle["venues"].as_array().unwrap().len(), 2);
    assert_eq!(bundle["performers"].as_array().unwrap().len(), 1);
    assert_eq!(bundle["performers"][0]["id"], pid("artist"));
    assert_eq!(bundle["genres"]["rock"], 2);
    assert_eq!(bundle["venuesTruncated"], false);
    for row in bundle["venues"]
        .as_array()
        .unwrap()
        .iter()
        .chain(bundle["performers"].as_array().unwrap())
    {
        for field in [
            "email",
            "credentials",
            "stripeCustomerId",
            "pushNotifications",
        ] {
            assert!(row.get(field).is_none());
        }
        assert!(row["venueInfo"].get("bookingEmail").is_none());
        assert!(row["venueInfo"].get("phoneNumber").is_none());
    }
    // Standard (nonwrapped) and empty viewports.
    for (west, east, count) in [(170, 180, 1), (150, 160, 0)] {
        let response = app
            .api_client
            .get(format!(
                "{}/app/v1/public/map?swLat=54&neLat=56&swLng={west}&neLng={east}",
                app.address
            ))
            .send()
            .await
            .unwrap();
        let bundle: Value = response.json().await.unwrap();
        assert_eq!(bundle["venues"].as_array().unwrap().len(), count);
    }
    // 251 venues, 1255 distinct references: SQL limits both before JSON projection.
    sqlx::query("INSERT INTO users(id,username,artist_name,occupations,location,profile) SELECT $1||'dense-'||i,$1||'dense-'||i,'Dense venue',ARRAY['venue'],ST_SetSRID(ST_MakePoint(155,51),4326)::geography,jsonb_build_object('venueInfo',jsonb_build_object('topPerformerIds',(SELECT jsonb_agg($1||'p-'||(i*5+j)) FROM generate_series(1,5) j))) FROM generate_series(1,251) i")
        .bind(&prefix).execute(&pool).await.unwrap();
    sqlx::query("INSERT INTO users(id,username,artist_name,occupations,profile) SELECT $1||'p-'||i,$1||'p-'||i,'Performer',ARRAY['performer'],'{}'::jsonb FROM generate_series(1,1260) i")
        .bind(&prefix).execute(&pool).await.unwrap();
    let response = app
        .api_client
        .get(format!(
            "{}/app/v1/public/map?swLat=50&neLat=52&swLng=154&neLng=156",
            app.address
        ))
        .send()
        .await
        .unwrap();
    let capped: Value = response.json().await.unwrap();
    assert_eq!(capped["venues"].as_array().unwrap().len(), 250);
    assert_eq!(capped["performers"].as_array().unwrap().len(), 1000);
    assert_eq!(capped["venuesTruncated"], true);
    assert_eq!(capped["performersTruncated"], true);
    let index: String = sqlx::query_scalar(
        "SELECT indexdef FROM pg_indexes WHERE indexname='users_map_location_idx'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(index.contains("gist"));
    assert!(index.contains("geometry"));
    sqlx::query("DELETE FROM users WHERE starts_with(id,$1)")
        .bind(prefix)
        .execute(&pool)
        .await
        .unwrap();
}
