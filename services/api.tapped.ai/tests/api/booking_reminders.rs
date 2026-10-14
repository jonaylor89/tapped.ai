use super::external_effects::{cleanup, database};
use tapped_api_rs::domain::booking_reminders::{deliver_one, schedule};

async fn fixture(pool: &sqlx::PgPool) {
    sqlx::query("INSERT INTO users(id,username,email) VALUES('requester','requester','requester@example.test'),('requestee','requestee','requestee@example.test')").execute(pool).await.unwrap();
    sqlx::query("INSERT INTO device_tokens(token,user_id) VALUES('token-a','requester'),('token-b','requestee')").execute(pool).await.unwrap();
    sqlx::query("INSERT INTO bookings(id,requester_id,requestee_id,status,start_time) VALUES('booking','requester','requestee','confirmed',now()+interval '8 days')").execute(pool).await.unwrap();
}
async fn schedule_booking(pool: &sqlx::PgPool) {
    let mut tx = pool.begin().await.unwrap();
    schedule(&mut tx, "booking").await.unwrap();
    tx.commit().await.unwrap();
}
async fn pending(pool: &sqlx::PgPool) -> i64 {
    sqlx::query_scalar(
        "SELECT count(*) FROM booking_reminders WHERE delivered_at IS NULL AND canceled_at IS NULL",
    )
    .fetch_one(pool)
    .await
    .unwrap()
}

#[tokio::test]
async fn migration_baselines_only_future_offsets_without_replaying_historical_effects() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    // Execute the exact deployed migration SQL against a populated, isolated database.
    sqlx::query("DROP TABLE booking_reminders")
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO users(id,username,email,unclaimed,deleted) VALUES('a','a','a@example.test',false,false),('b','b','b@example.test',false,false),('unclaimed','unclaimed','unclaimed@example.test',true,false),('deleted','deleted','deleted@example.test',false,true)").execute(&pool).await.unwrap();
    sqlx::query("INSERT INTO bookings(id,requester_id,requestee_id,status,start_time) VALUES('future','a','b','confirmed',now()+interval '8 days'),('near','a','unclaimed','confirmed',now()+interval '2 hours'),('past','a','b','confirmed',now()-interval '1 day'),('pending','a','b','pending',now()+interval '8 days'),('empty-requester','','b','confirmed',now()+interval '8 days'),('inactive','unclaimed','deleted','confirmed',now()+interval '8 days')").execute(&pool).await.unwrap();
    sqlx::raw_sql(include_str!(
        "../../migrations/20261018000000_booking_reminders.sql"
    ))
    .execute(&pool)
    .await
    .unwrap();
    let counts:(i64,i64,i64,i64)=sqlx::query_as("SELECT (SELECT count(*) FROM booking_reminders),(SELECT count(*) FROM activities),(SELECT count(*) FROM external_effect_outbox),(SELECT count(*) FROM founder_notification_outbox)").fetch_one(&pool).await.unwrap();
    assert_eq!(counts, (7, 0, 0, 0));
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM booking_reminders WHERE due_at<=now()")
            .fetch_one(&pool)
            .await
            .unwrap(),
        0
    );
    assert_eq!(sqlx::query_scalar::<_,i64>("SELECT count(*) FROM booking_reminders WHERE booking_id='near' AND offset_seconds=3600 AND user_id='a'").fetch_one(&pool).await.unwrap(),1);
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn confirmation_schedules_all_offsets_once_and_parallel_delivery_is_atomic() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    fixture(&pool).await;
    schedule_booking(&pool).await;
    schedule_booking(&pool).await;
    assert_eq!(pending(&pool).await, 6);
    // Time is controlled in the private queue, with the authoritative booking still in future.
    sqlx::query("UPDATE booking_reminders SET due_at=now()-interval '1 second'")
        .execute(&pool)
        .await
        .unwrap();
    let (a, b) = tokio::join!(deliver_one(&pool), deliver_one(&pool));
    a.unwrap();
    b.unwrap();
    while deliver_one(&pool).await.unwrap() {}
    assert_eq!(pending(&pool).await, 0);
    assert_eq!(
        sqlx::query_scalar::<_, i64>(
            "SELECT count(*) FROM activities WHERE activity_type='bookingReminder'"
        )
        .fetch_one(&pool)
        .await
        .unwrap(),
        6
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>(
            "SELECT count(*) FROM external_effect_outbox WHERE kind='push'"
        )
        .fetch_one(&pool)
        .await
        .unwrap(),
        6
    );
    schedule_booking(&pool).await;
    assert_eq!(
        pending(&pool).await,
        0,
        "an API retry cannot replay delivered reminders"
    );
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn rescheduling_cancellation_and_unclaimed_deleted_recipients_do_not_deliver_stale_jobs() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    fixture(&pool).await;
    schedule_booking(&pool).await;
    sqlx::query("UPDATE bookings SET start_time=start_time+interval '1 day' WHERE id='booking'")
        .execute(&pool)
        .await
        .unwrap();
    schedule_booking(&pool).await;
    assert_eq!(pending(&pool).await, 6);
    assert_eq!(
        sqlx::query_scalar::<_, i64>(
            "SELECT count(*) FROM booking_reminders WHERE canceled_at IS NOT NULL"
        )
        .fetch_one(&pool)
        .await
        .unwrap(),
        6
    );
    // Canceled booking is checked at delivery even if a producer failed to reconcile its queue.
    sqlx::query("UPDATE bookings SET status='canceled' WHERE id='booking'")
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("UPDATE booking_reminders SET due_at=now()-interval '1 second'")
        .execute(&pool)
        .await
        .unwrap();
    while deliver_one(&pool).await.unwrap() {}
    assert_eq!(pending(&pool).await, 0);
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM activities")
            .fetch_one(&pool)
            .await
            .unwrap(),
        0
    );
    sqlx::query("UPDATE bookings SET status='confirmed' WHERE id='booking'")
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("UPDATE users SET deleted=(id='requester'),unclaimed=(id='requestee')")
        .execute(&pool)
        .await
        .unwrap();
    schedule_booking(&pool).await;
    assert_eq!(pending(&pool).await, 0);
    // Past bookings must not replay missed reminders.
    sqlx::query("UPDATE users SET deleted=false,unclaimed=false")
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("UPDATE bookings SET start_time=now()-interval '1 second' WHERE id='booking'")
        .execute(&pool)
        .await
        .unwrap();
    schedule_booking(&pool).await;
    assert_eq!(pending(&pool).await, 0);
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn overdue_pending_bookings_expire_once_without_historical_notification_replay() {
    use tapped_api_rs::domain::booking_reminders::expire_one;
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    fixture(&pool).await;
    sqlx::query("UPDATE bookings SET status='pending',start_time=now()-interval '2 days' WHERE id='booking'").execute(&pool).await.unwrap();
    assert!(expire_one(&pool).await.unwrap());
    assert!(!expire_one(&pool).await.unwrap());
    assert_eq!(
        sqlx::query_scalar::<_, String>("SELECT status FROM bookings WHERE id='booking'")
            .fetch_one(&pool)
            .await
            .unwrap(),
        "canceled"
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM external_effect_outbox")
            .fetch_one(&pool)
            .await
            .unwrap(),
        0
    );
    sqlx::query("UPDATE bookings SET status='pending',start_time=now()-interval '12 hours' WHERE id='booking'").execute(&pool).await.unwrap();
    assert!(!expire_one(&pool).await.unwrap());
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn unrelated_booking_edit_keeps_due_reminders_without_replaying_missed_offsets() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    fixture(&pool).await;
    sqlx::query("UPDATE bookings SET start_time=now()+interval '30 minutes' WHERE id='booking'")
        .execute(&pool)
        .await
        .unwrap();
    // These hour reminders were scheduled earlier; their due time has passed but the booking
    // is still in future. Day/week offsets already missed must not be newly replayed.
    sqlx::query("INSERT INTO booking_reminders(booking_id,user_id,start_time,offset_seconds,due_at) SELECT b.id,u.id,b.start_time,3600,b.start_time-interval '1 hour' FROM bookings b JOIN users u ON u.id IN (b.requester_id,b.requestee_id)").execute(&pool).await.unwrap();
    sqlx::query("UPDATE bookings SET note='note-only edit' WHERE id='booking'")
        .execute(&pool)
        .await
        .unwrap();
    schedule_booking(&pool).await;
    assert_eq!(pending(&pool).await, 2);
    assert_eq!(
        sqlx::query_scalar::<_, i64>(
            "SELECT count(*) FROM booking_reminders WHERE due_at<=now() AND canceled_at IS NULL"
        )
        .fetch_one(&pool)
        .await
        .unwrap(),
        2
    );
    while deliver_one(&pool).await.unwrap() {}
    schedule_booking(&pool).await;
    assert_eq!(pending(&pool).await, 0);
    assert_eq!(
        sqlx::query_scalar::<_, i64>(
            "SELECT count(*) FROM activities WHERE activity_type='bookingReminder'"
        )
        .fetch_one(&pool)
        .await
        .unwrap(),
        2
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM booking_reminders")
            .fetch_one(&pool)
            .await
            .unwrap(),
        2
    );
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn failed_push_enqueue_rolls_back_the_activity_and_reminder_completion() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    fixture(&pool).await;
    let mut tx = pool.begin().await.unwrap();
    schedule(&mut tx, "booking").await.unwrap();
    tx.rollback().await.unwrap();
    assert_eq!(pending(&pool).await, 0);
    schedule_booking(&pool).await;
    sqlx::query("UPDATE booking_reminders SET due_at=now()-interval '1 second'")
        .execute(&pool)
        .await
        .unwrap();
    sqlx::raw_sql("CREATE FUNCTION fail_reminder_push() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'test'; END $$; CREATE TRIGGER fail_push BEFORE INSERT ON external_effect_outbox FOR EACH ROW EXECUTE FUNCTION fail_reminder_push();").execute(&pool).await.unwrap();
    assert!(deliver_one(&pool).await.is_err());
    assert_eq!(pending(&pool).await, 6);
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM activities")
            .fetch_one(&pool)
            .await
            .unwrap(),
        0
    );
    sqlx::query("DROP TRIGGER fail_push ON external_effect_outbox")
        .execute(&pool)
        .await
        .unwrap();
    assert!(deliver_one(&pool).await.unwrap());
    assert_eq!(pending(&pool).await, 5);
    cleanup(pool, admin, name).await;
}
