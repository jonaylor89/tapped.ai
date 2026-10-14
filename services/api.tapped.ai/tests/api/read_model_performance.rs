use super::external_effects::{cleanup, database};
use serde_json::Value;
use tapped_api_rs::data::{
    database::Database,
    pg_database::{PostgresDatabase, USERNAME_LOOKUP_SQL},
};

fn assert_bounded_statistics(node: &Value, bound: u64) {
    if node["Relation Name"] == "bookings" || node["Relation Name"] == "reviews" {
        assert!(
            node["Actual Loops"].as_u64().unwrap() <= bound,
            "statistics scanned unrelated profiles: {node}"
        );
    }
    for child in node["Plans"].as_array().into_iter().flatten() {
        assert_bounded_statistics(child, bound);
    }
}

#[tokio::test]
async fn normalized_username_and_bounded_id_reads_do_not_aggregate_unrelated_profiles() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    sqlx::query("INSERT INTO users(id,username,profile) SELECT 'profile-'||i,'Profile-'||i,'{\"performerInfo\":{}}'::jsonb FROM generate_series(1,2000) i")
        .execute(&pool).await.unwrap();
    sqlx::query("INSERT INTO bookings(id,requestee_id,status,start_time,end_time) SELECT 'history-'||i,'profile-'||i,'confirmed',now()+interval '1 hour',now()+interval '2 hours' FROM generate_series(1,2000) i")
        .execute(&pool).await.unwrap();
    for table in ["users", "bookings", "reviews"] {
        sqlx::query(sqlx::AssertSqlSafe(format!("ANALYZE {table}")))
            .execute(&pool)
            .await
            .unwrap();
    }
    let repository = PostgresDatabase::new(pool.clone());
    let doc = repository
        .get_user_doc_by_username("pRoFiLe-1")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(doc["id"], "profile-1");
    assert_eq!(doc["performerInfo"]["bookingCount"], 1);
    assert_eq!(doc["performerInfo"]["completedBookingCount"], 0);
    assert_eq!(
        repository
            .get_user_by_username("PROFILE-1")
            .await
            .unwrap()
            .id,
        "profile-1"
    );
    for username in ["", "missing"] {
        assert!(
            repository
                .get_user_doc_by_username(username)
                .await
                .unwrap()
                .is_none()
        );
    }
    let explain = format!("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) {USERNAME_LOOKUP_SQL}");
    let plan: Value = sqlx::query_scalar(sqlx::AssertSqlSafe(explain))
        .bind("PROFILE-1")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_bounded_statistics(&plan[0]["Plan"], 1);
    assert!(plan.to_string().contains("users_username_unique_ci_idx"));
    // Keep the materialized map/search ID selection bounded through view expansion too.
    let plan: Value = sqlx::query_scalar("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) WITH selected AS MATERIALIZED (SELECT id FROM users ORDER BY id LIMIT 10) SELECT v.doc FROM selected s JOIN api_users v USING(id)")
        .fetch_one(&pool).await.unwrap();
    assert_bounded_statistics(&plan[0]["Plan"], 10);
    // A burst larger than the unchanged five-connection pool must not enumerate all profiles.
    let mut readers = tokio::task::JoinSet::new();
    for i in 1..=25 {
        let repository = repository.clone();
        readers.spawn(async move {
            let username = format!("PROFILE-{i}");
            let doc = repository
                .get_user_doc_by_username(&username)
                .await
                .unwrap()
                .unwrap();
            assert_eq!(doc["performerInfo"]["bookingCount"], 1);
        });
    }
    while let Some(result) = readers.join_next().await {
        result.unwrap();
    }
    sqlx::query("UPDATE users SET deleted=true WHERE id='profile-1'")
        .execute(&pool)
        .await
        .unwrap();
    assert!(
        repository
            .get_user_doc_by_username("PROFILE-1")
            .await
            .unwrap()
            .is_none()
    );
    assert!(repository.get_user_by_username("PROFILE-1").await.is_err());
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn idle_pending_expiry_uses_its_partial_index_not_confirmed_history() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    sqlx::query("INSERT INTO users(id) VALUES('artist')")
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO bookings(id,requestee_id,status,start_time,end_time) SELECT 'history-'||i,'artist','confirmed',now()-interval '2 days',now()-interval '1 day' FROM generate_series(1,2000) i")
        .execute(&pool).await.unwrap();
    sqlx::query("ANALYZE bookings")
        .execute(&pool)
        .await
        .unwrap();
    let plan: Value = sqlx::query_scalar("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT id FROM bookings WHERE status='pending' AND start_time+interval '1 day'<now() ORDER BY start_time,id LIMIT 1")
        .fetch_one(&pool).await.unwrap();
    assert!(plan.to_string().contains("bookings_pending_expiry_idx"));
    assert!(!plan.to_string().contains("Seq Scan"));
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn booker_reviews_expose_booker_info_for_requesters_without_a_booker_section() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    sqlx::query("INSERT INTO users(id,username,profile) VALUES('venue','venue','{\"venueInfo\":{}}'),('unreviewed','unreviewed','{\"bookerInfo\":null}')")
        .execute(&pool).await.unwrap();
    sqlx::query("INSERT INTO reviews(id,review_type,reviewee_id,overall_rating) VALUES('review','booker','venue',4)")
        .execute(&pool).await.unwrap();
    let docs: Vec<(String, Value)> =
        sqlx::query_as("SELECT id,doc->'bookerInfo' FROM api_users ORDER BY id")
            .fetch_all(&pool)
            .await
            .unwrap();
    assert_eq!(docs[0].0, "unreviewed");
    assert!(
        docs[0].1.is_null(),
        "no booker reviews keeps bookerInfo absent"
    );
    assert_eq!(docs[1].0, "venue");
    assert_eq!(docs[1].1["reviewCount"], 1);
    assert_eq!(docs[1].1["rating"].as_f64(), Some(4.0));
    cleanup(pool, admin, name).await;
}
