use serde_json::Value;
use sqlx::postgres::{PgConnectOptions, PgPoolOptions};
use std::str::FromStr;
use tapped_api_rs::data::postgres::MIGRATOR;
#[tokio::test]
async fn populated_postgres_first_migration_preserves_legacy_provenance_without_replay() {
    let Ok(url) = std::env::var("DATABASE_URL") else {
        return;
    };
    let options = PgConnectOptions::from_str(&url).unwrap();
    let admin = PgPoolOptions::new()
        .max_connections(1)
        .connect_with(options.clone())
        .await
        .unwrap();
    let name = format!("first_{}", uuid::Uuid::new_v4().simple());
    sqlx::query(sqlx::AssertSqlSafe(format!("CREATE DATABASE {name}")))
        .execute(&admin)
        .await
        .unwrap();
    let pool = PgPoolOptions::new()
        .max_connections(2)
        .connect_with(options.database(&name))
        .await
        .unwrap();
    for migration in MIGRATOR.iter().filter(|m| m.version < 20261024000000) {
        sqlx::raw_sql(migration.sql.clone())
            .execute(&pool)
            .await
            .unwrap();
    }
    sqlx::raw_sql("INSERT INTO firebase_identities(uid,email,display_name,created_at_ms,scan_id) VALUES('real','','',1000,gen_random_uuid()); INSERT INTO users(id,username,profile) VALUES('real','real','{\"performerInfo\":{\"genres\":[\"Jazz\",7],\"label\":\"Independent\",\"bookingCount\":777,\"rating\":5}}'); INSERT INTO bookings(id,requester_id,requestee_id,status,start_time,end_time) VALUES('broken','missing-venue','missing-performer','unknown',now(),now()-interval '1 hour'),('confirmed','real','real','confirmed',now()-interval '2 hours',now()-interval '1 hour'); INSERT INTO reviews(id,review_type,reviewee_id,booker_id,performer_id,booking_id,overall_rating,occurred_at) VALUES('old','performer','real','real','real','confirmed',4,now()-interval '1 hour'),('new','performer','real','real','real','confirmed',5,now()); INSERT INTO device_tokens(token,user_id) VALUES('legacy-token','account-only');").execute(&pool).await.unwrap();
    let mut tx = pool.begin().await.unwrap();
    for migration in MIGRATOR.iter().filter(|m| m.version >= 20261024000000) {
        sqlx::raw_sql(migration.sql.clone())
            .execute(&mut *tx)
            .await
            .unwrap();
    }
    tx.commit().await.unwrap();
    let original: Value =
        sqlx::query_scalar("SELECT profile FROM legacy_profile_archive WHERE profile_id='real'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(original["performerInfo"]["bookingCount"], 777);
    assert_eq!(original["performerInfo"]["genres"][1], 7);
    let doc: Value = sqlx::query_scalar("SELECT doc FROM api_users WHERE id='real'")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(doc["performerInfo"]["bookingCount"], 1);
    assert_eq!(doc["performerInfo"]["completedBookingCount"], 1);
    assert_eq!(doc["performerInfo"]["rating"], 5);
    assert_eq!(doc["performerInfo"]["reviewCount"], 1);
    assert_eq!(doc["performerInfo"]["genres"], serde_json::json!(["Jazz"]));
    let valid: (String, bool) = sqlx::query_as(
        "SELECT status,start_time IS NULL AND end_time IS NULL FROM bookings WHERE id='broken'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(valid, ("canceled".into(), true));
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM users WHERE deleted AND unclaimed")
            .fetch_one(&pool)
            .await
            .unwrap(),
        2
    );
    assert!(
        sqlx::query_scalar::<_, bool>(
            "SELECT disabled FROM accounts WHERE auth_uid='account-only'"
        )
        .fetch_one(&pool)
        .await
        .unwrap()
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM users WHERE id='account-only'")
            .fetch_one(&pool)
            .await
            .unwrap(),
        0
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM reviews")
            .fetch_one(&pool)
            .await
            .unwrap(),
        2
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM api_reviews")
            .fetch_one(&pool)
            .await
            .unwrap(),
        1
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM legacy_invalid_records")
            .fetch_one(&pool)
            .await
            .unwrap(),
        2
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM external_effect_outbox")
            .fetch_one(&pool)
            .await
            .unwrap(),
        0
    );
    super::external_effects::cleanup(pool, admin, name).await;
}
