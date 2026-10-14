use super::helpers::{mock_state, spawn_app_with_state};
use serde_json::Value;
use tapped_api_rs::data::postgres::connect;

#[tokio::test]
async fn postgres_profile_details_hide_private_and_pending_bookings_and_deleted_users() {
    let Ok(url) = std::env::var("DATABASE_URL") else {
        eprintln!("DATABASE_URL unset; skipping profile bundle test");
        return;
    };
    let pool = connect(&url).await.unwrap();
    let mut state = mock_state();
    state.postgres = Some(pool.clone());
    let app = spawn_app_with_state(state).await;
    let uid = format!("details-{}", uuid::Uuid::new_v4());
    sqlx::query("INSERT INTO users(id,username,email,artist_name,profile) VALUES($1,$1,'private@example.test','Artist','{\"stripeCustomerId\":\"secret\"}'::jsonb)").bind(&uid).execute(&pool).await.unwrap();
    let other = format!("{uid}-other");
    let deleted = format!("{uid}-deleted");
    sqlx::query("INSERT INTO users(id,username,email,deleted,profile) VALUES($1,$1,'private@example.test',false,'{\"ownerNotes\":\"secret\"}'::jsonb),($2,$2,'deleted@example.test',true,'{}')").bind(&other).bind(&deleted).execute(&pool).await.unwrap();
    sqlx::query("UPDATE users SET profile=profile||jsonb_build_object('venueInfo',jsonb_build_object('topPerformerIds',jsonb_build_array($2::text,$3::text))) WHERE id=$1").bind(&uid).bind(&other).bind(&deleted).execute(&pool).await.unwrap();
    for (suffix, status) in [
        ("confirmed", "confirmed"),
        ("pending", "pending"),
        ("canceled", "canceled"),
    ] {
        sqlx::query("INSERT INTO bookings(id,requestee_id,requester_id,status,name,note,rate,start_time,end_time,occurred_at) VALUES($1,$2,$2,$3,'Show','Private note',100,now(),now(),now())").bind(format!("{uid}-{suffix}")).bind(&uid).bind(status).execute(&pool).await.unwrap();
    }
    for (suffix, age) in [("older", 60), ("latest", 0)] {
        sqlx::query("INSERT INTO reviews(id,reviewee_id,review_type,booker_id,performer_id,booking_id,overall_rating,overall_review,occurred_at,profile) VALUES($1,$2,'performer',$5,$2,NULLIF($3,''),4,'Public review',now()-make_interval(mins=>$4),'{\"email\":\"private@example.test\",\"performerRating\":{\"privateContact\":\"secret\"},\"_firestore_path\":\"private\"}'::jsonb)")
            .bind(format!("{uid}-{suffix}")).bind(&uid).bind("").bind(age).bind(&other)
            .execute(&pool).await.unwrap();
    }
    let path = format!("{}/app/v1/public/users/{uid}/details", app.address);
    let response = app.api_client.get(&path).send().await.unwrap();
    assert_eq!(response.status(), 200);
    assert_eq!(response.headers()["cache-control"], "no-store");
    let bundle: Value = response.json().await.unwrap();
    assert!(bundle["user"].get("email").is_none());
    assert!(bundle["user"].get("stripeCustomerId").is_none());
    assert_eq!(bundle["bookingCount"], 1);
    assert_eq!(bundle["bookings"].as_array().unwrap().len(), 1); // self-booking deduplicated
    for field in ["note", "rate", "serviceId"] {
        assert!(bundle["bookings"][0].get(field).is_none());
    }
    assert_eq!(bundle["bookings"][0]["status"], "confirmed");
    assert_eq!(bundle["latestReview"]["id"], format!("{uid}-latest"));
    assert_eq!(bundle["latestReview"]["overallReview"], "Public review");
    for field in ["email", "performerRating", "_firestore_path"] {
        assert!(bundle["latestReview"].get(field).is_none());
    }
    let related = bundle["relatedUsers"].as_array().unwrap();
    assert_eq!(related.len(), 1); // reviewer/top performer deduplicated; deleted reference omitted
    assert_eq!(related[0]["id"], other);
    assert!(related[0].get("email").is_none());
    assert!(related[0].get("ownerNotes").is_none());
    sqlx::query("UPDATE users SET shadow_banned=true WHERE id=$1")
        .bind(&uid)
        .execute(&pool)
        .await
        .unwrap();
    assert_eq!(
        app.api_client.get(&path).send().await.unwrap().status(),
        404
    );
    sqlx::query("UPDATE users SET deleted=true,shadow_banned=false WHERE id=$1")
        .bind(&uid)
        .execute(&pool)
        .await
        .unwrap();
    let missing = app.api_client.get(path).send().await.unwrap();
    assert_eq!(missing.status(), 404);
    assert_eq!(missing.headers()["cache-control"], "no-store");
    sqlx::query("DELETE FROM reviews WHERE reviewee_id=$1")
        .bind(&uid)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("DELETE FROM bookings WHERE requestee_id=$1")
        .bind(&uid)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("DELETE FROM users WHERE id IN ($1,$2,$3)")
        .bind(uid)
        .bind(other)
        .bind(deleted)
        .execute(&pool)
        .await
        .unwrap();
}

#[tokio::test]
async fn profile_details_are_bounded_and_validate_ids_without_a_database_fallback() {
    let app = super::helpers::spawn_app().await;
    let response = app
        .api_client
        .get(format!("{}/app/v1/public/users/user/details", app.address))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), 503);
    assert_eq!(response.headers()["cache-control"], "no-store");
    let response = app
        .api_client
        .get(format!("{}/app/v1/public/users/bad!/details", app.address))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), 400);

    let Ok(url) = std::env::var("DATABASE_URL") else {
        return;
    };
    let pool = connect(&url).await.unwrap();
    let mut state = mock_state();
    state.postgres = Some(pool.clone());
    let app = spawn_app_with_state(state).await;
    let uid = format!("bounded-{}", uuid::Uuid::new_v4());
    let other = format!("{uid}-other");
    sqlx::query("INSERT INTO users(id,username) VALUES($1,$1),($2,$2)")
        .bind(&uid)
        .bind(&other)
        .execute(&pool)
        .await
        .unwrap();
    for incoming in [true, false] {
        let (requester, requestee, suffix) = if incoming {
            (&other, &uid, "in")
        } else {
            (&uid, &other, "out")
        };
        sqlx::query("INSERT INTO bookings(id,requester_id,requestee_id,status,start_time,end_time,occurred_at) SELECT $1||i,$2,$3,'confirmed',now()+i*interval '1 day',now()+i*interval '1 day',now()+i*interval '1 second' FROM generate_series(0,89) i")
            .bind(format!("{uid}-{suffix}-")).bind(requester).bind(requestee).execute(&pool).await.unwrap();
    }
    sqlx::query("INSERT INTO bookings(id,requester_id,requestee_id,status,start_time,end_time,occurred_at) VALUES($1,$2,$2,'confirmed',now()+interval '900 days',now()+interval '900 days',now()+interval '1 day')")
        .bind(format!("{uid}-self")).bind(&uid).execute(&pool).await.unwrap();
    let response = app
        .api_client
        .get(format!("{}/app/v1/public/users/{uid}/details", app.address))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), 200);
    let bundle: Value = response.json().await.unwrap();
    assert_eq!(bundle["bookingCount"], 91);
    let bookings = bundle["bookings"].as_array().unwrap();
    assert_eq!(bookings.len(), 79); // 40 per role minus the duplicate self-booking
    assert_eq!(bookings[0]["id"], format!("{uid}-self"));
    assert!(
        bookings
            .windows(2)
            .all(|pair| pair[0]["startTime"].as_str() >= pair[1]["startTime"].as_str())
    );
    sqlx::query("DELETE FROM bookings WHERE $1 IN (requester_id,requestee_id)")
        .bind(&uid)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("DELETE FROM users WHERE id IN ($1,$2)")
        .bind(&uid)
        .bind(&other)
        .execute(&pool)
        .await
        .unwrap();
}
