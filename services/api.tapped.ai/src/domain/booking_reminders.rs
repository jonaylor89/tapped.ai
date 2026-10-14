//! Postgres-only scheduled reminders. Activity + push jobs + completion are one transaction.
use sqlx::{PgPool, Postgres, Row, Transaction};
use std::time::Duration;

pub async fn schedule(
    tx: &mut Transaction<'_, Postgres>,
    booking_id: &str,
) -> Result<(), sqlx::Error> {
    // Caller already holds the booking advisory lock. Cancel only obsolete jobs. A note-only
    // edit must not lose a valid due reminder that the worker has not delivered yet.
    sqlx::query("UPDATE booking_reminders r SET canceled_at=now() WHERE booking_id=$1 AND delivered_at IS NULL AND canceled_at IS NULL AND NOT EXISTS(SELECT 1 FROM bookings b JOIN users u ON u.id=r.user_id WHERE b.id=r.booking_id AND b.status='confirmed' AND b.start_time=r.start_time AND b.start_time>now() AND b.requester_id IS NOT NULL AND b.requester_id<>'' AND u.id IN (b.requester_id,b.requestee_id) AND NOT u.deleted AND NOT u.unclaimed)")
        .bind(booking_id).execute(&mut **tx).await?;
    sqlx::query(
        "INSERT INTO booking_reminders(booking_id,user_id,start_time,offset_seconds,due_at)
        SELECT DISTINCT b.id,u.id,b.start_time,o.seconds,b.start_time-make_interval(secs=>o.seconds)
        FROM bookings b JOIN users u ON u.id IN (b.requester_id,b.requestee_id)
        CROSS JOIN (VALUES (3600),(86400),(604800)) o(seconds)
        WHERE b.id=$1 AND b.status='confirmed' AND b.requester_id IS NOT NULL AND b.requester_id<>''
        AND NOT u.deleted AND NOT u.unclaimed AND b.start_time-make_interval(secs=>o.seconds)>now()
        ON CONFLICT(booking_id,user_id,start_time,offset_seconds) DO UPDATE SET canceled_at=NULL
        WHERE booking_reminders.delivered_at IS NULL",
    )
    .bind(booking_id)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

pub async fn deliver_one(pool: &PgPool) -> Result<bool, sqlx::Error> {
    // Lock ordering matches API writes: booking advisory lock before reminder row lock.
    let candidate: Option<(i64, String)> = sqlx::query_as("SELECT id,booking_id FROM booking_reminders WHERE due_at<=now() AND delivered_at IS NULL AND canceled_at IS NULL ORDER BY due_at,id LIMIT 1")
        .fetch_optional(pool).await?;
    let Some((id, booking_id)) = candidate else {
        return Ok(false);
    };
    let mut tx = pool.begin().await?;
    let locked: bool =
        sqlx::query_scalar("SELECT pg_try_advisory_xact_lock(hashtextextended($1,0))")
            .bind(format!("bookings:{booking_id}"))
            .fetch_one(&mut *tx)
            .await?;
    if !locked {
        return Ok(false);
    }
    let reminder = sqlx::query("SELECT r.user_id,EXISTS(SELECT 1 FROM bookings b JOIN users u ON u.id=r.user_id WHERE b.id=r.booking_id AND b.status='confirmed' AND b.start_time=r.start_time AND b.start_time>now() AND u.id IN (b.requester_id,b.requestee_id) AND NOT u.deleted AND NOT u.unclaimed) AS valid FROM booking_reminders r WHERE r.id=$1 AND r.due_at<=now() AND r.delivered_at IS NULL AND r.canceled_at IS NULL FOR UPDATE SKIP LOCKED")
        .bind(id).fetch_optional(&mut *tx).await?;
    let Some(reminder) = reminder else {
        return Ok(false);
    };
    if reminder.get::<bool, _>("valid") {
        let uid: String = reminder.get("user_id");
        let activity_id = format!("booking-reminder:{id}");
        sqlx::query("INSERT INTO activities(id,activity_type,to_user_id,booking_id,occurred_at) VALUES($1,'bookingReminder',$2,$3,now()) ON CONFLICT(id) DO NOTHING")
            .bind(&activity_id).bind(&uid).bind(&booking_id).execute(&mut *tx).await?;
        crate::domain::external_effects::record_activity(
            &mut tx,
            &activity_id,
            &uid,
            "bookingReminder",
            &booking_id,
        )
        .await?;
        sqlx::query("UPDATE booking_reminders SET delivered_at=now() WHERE id=$1")
            .bind(id)
            .execute(&mut *tx)
            .await?;
    } else {
        sqlx::query("UPDATE booking_reminders SET canceled_at=now() WHERE id=$1")
            .bind(id)
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;
    Ok(true)
}

/// Preserve the legacy hourly expiry rule (pending bookings > one day past start), without
/// replaying push/email effects for historical pending records. Shares the API booking lock.
pub async fn expire_one(pool: &PgPool) -> Result<bool, sqlx::Error> {
    let candidate: Option<String> = sqlx::query_scalar("SELECT id FROM bookings WHERE status='pending' AND start_time+interval '1 day'<now() ORDER BY start_time,id LIMIT 1")
        .fetch_optional(pool).await?;
    let Some(id) = candidate else {
        return Ok(false);
    };
    let mut tx = pool.begin().await?;
    let locked: bool =
        sqlx::query_scalar("SELECT pg_try_advisory_xact_lock(hashtextextended($1,0))")
            .bind(format!("bookings:{id}"))
            .fetch_one(&mut *tx)
            .await?;
    if !locked {
        return Ok(false);
    }
    let updated = sqlx::query("UPDATE bookings SET status='canceled' WHERE id=$1 AND status='pending' AND start_time+interval '1 day'<now()")
        .bind(&id).execute(&mut *tx).await?.rows_affected()>0;
    if updated {
        schedule(&mut tx, &id).await?;
    }
    tx.commit().await?;
    Ok(updated)
}

pub async fn run(pool: PgPool) {
    loop {
        let result = async {
            let expired = expire_one(&pool).await?;
            let delivered = deliver_one(&pool).await?;
            Ok::<_, sqlx::Error>(expired || delivered)
        }
        .await;
        match result {
            Ok(true) => {}
            Ok(false) => tokio::time::sleep(Duration::from_secs(10)).await,
            Err(_) => {
                tracing::warn!("booking reminder transaction failed; retained for retry");
                tokio::time::sleep(Duration::from_secs(10)).await;
            }
        }
    }
}
