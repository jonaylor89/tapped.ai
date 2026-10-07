use chrono::{DateTime, Utc};
use sqlx::Row;
use tapped_api_rs::data::postgres::{MIGRATOR, connect};

/// Runs against `DATABASE_URL` (a PostGIS database; CI provides one) and is skipped when unset.
#[tokio::test]
async fn migrations_create_a_geo_indexed_users_table() {
    let Ok(url) = std::env::var("DATABASE_URL") else {
        eprintln!("DATABASE_URL is not set; skipping");
        return;
    };
    let pool = connect(&url).await.expect("connect and migrate");
    MIGRATOR
        .run(&pool)
        .await
        .expect("migrations are re-runnable");

    let id = format!("test-{}", uuid::Uuid::new_v4());
    sqlx::query(
        "INSERT INTO users (id, username, location, profile)
         VALUES ($1, 'tester', ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography, $4)",
    )
    .bind(&id)
    .bind(-77.0369_f64)
    .bind(38.9072_f64)
    .bind(serde_json::json!({ "performerInfo": { "label": "Independent" } }))
    .execute(&pool)
    .await
    .expect("insert user");

    let row = sqlx::query(
        "SELECT profile -> 'performerInfo' ->> 'label' AS label, updated_at FROM users
         WHERE id = $1 AND ST_DWithin(location, ST_MakePoint(-77.03, 38.90)::geography, 5000)",
    )
    .bind(&id)
    .fetch_one(&pool)
    .await
    .expect("geo query finds the user");
    assert_eq!(row.get::<String, _>("label"), "Independent");
    let created: DateTime<Utc> = row.get("updated_at");

    let updated: DateTime<Utc> =
        sqlx::query_scalar("UPDATE users SET bio = 'hi' WHERE id = $1 RETURNING updated_at")
            .bind(&id)
            .fetch_one(&pool)
            .await
            .expect("update user");
    assert!(updated > created, "updated_at trigger bumps the timestamp");

    sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(&id)
        .execute(&pool)
        .await
        .expect("clean up");
}
