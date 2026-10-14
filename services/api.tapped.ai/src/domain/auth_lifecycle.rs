//! Auth hooks are transport only. Acknowledge only after the lifecycle event is durable.
use axum::{
    body::Bytes,
    extract::State,
    http::{HeaderMap, StatusCode},
};
use hmac::{Hmac, KeyInit, Mac};
use serde::Deserialize;
use sha2::Sha256;
use sqlx::PgPool;

use crate::{
    data::google_identity::Account, domain::external_effects, errors::AppError, state::AppStateDyn,
};

#[derive(Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LifecycleKind {
    Signup,
    Delete,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LifecycleEvent {
    pub kind: LifecycleKind,
    pub account: Account,
}

pub async fn lock_identity(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    uid: &str,
) -> Result<(), sqlx::Error> {
    // Includes absent rows: concurrent hooks and reconciliation must not race an INSERT.
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 920041756))")
        .bind(uid)
        .execute(&mut **tx)
        .await?;
    // Serialize profile/service cleanup with normal API profile and service writes too.
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))")
        .bind(format!("users:{uid}"))
        .execute(&mut **tx)
        .await?;
    Ok(())
}

pub async fn receive(pool: &PgPool, event: &LifecycleEvent) -> Result<(), sqlx::Error> {
    let a = &event.account;
    let created = a.created_ms();
    let mut tx = pool.begin().await?;
    lock_identity(&mut tx, &a.local_id).await?;
    let old: Option<(i64, bool)> =
        sqlx::query_as("SELECT created_at_ms,deleted FROM firebase_identities WHERE uid=$1")
            .bind(&a.local_id)
            .fetch_optional(&mut *tx)
            .await?;
    // Creation time identifies the account incarnation. Late callbacks must never resurrect a
    // tombstone or delete a newly recreated account with the same UID.
    let stale =
        old.is_some_and(|(version, deleted)| version > created || (version == created && deleted));
    if !stale {
        let deleted = matches!(event.kind, LifecycleKind::Delete);
        sqlx::query("INSERT INTO firebase_identities(uid,email,display_name,created_at_ms,scan_id,deleted) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(uid) DO UPDATE SET email=EXCLUDED.email,display_name=EXCLUDED.display_name,created_at_ms=EXCLUDED.created_at_ms,deleted=EXCLUDED.deleted")
            .bind(&a.local_id).bind(&a.email).bind(&a.display_name).bind(created).bind(uuid::Uuid::new_v4()).bind(deleted).execute(&mut *tx).await?;
        if deleted {
            sqlx::query("DELETE FROM spotify_oauth_tokens WHERE user_id=$1")
                .bind(&a.local_id)
                .execute(&mut *tx)
                .await?;
            sqlx::query("DELETE FROM spotify_oauth_states WHERE user_id=$1")
                .bind(&a.local_id)
                .execute(&mut *tx)
                .await?;
            sqlx::query("UPDATE users SET deleted=true WHERE id=$1")
                .bind(&a.local_id)
                .execute(&mut *tx)
                .await?;
            sqlx::query("UPDATE services SET deleted=true WHERE user_id=$1")
                .bind(&a.local_id)
                .execute(&mut *tx)
                .await?;
        } else {
            external_effects::update_identity_email(&mut tx, &a.local_id, &a.email).await?;
        }
        let kind = if deleted {
            "auth_delete"
        } else {
            "auth_signup"
        };
        let id = format!(
            "auth-{}:{}:{created}",
            if deleted { "delete" } else { "signup" },
            a.local_id
        );
        // Identical key to the reconciliation worker, even if multiple retained hooks forward it.
        external_effects::enqueue(
            &mut tx,
            &id,
            kind,
            serde_json::to_value(a).expect("serializable account"),
        )
        .await?;
    }
    tx.commit().await
}

fn authorized(secret: &str, headers: &HeaderMap, body: &[u8], now: i64) -> bool {
    let Some(timestamp) = headers
        .get("x-tapped-timestamp")
        .and_then(|h| h.to_str().ok())
    else {
        return false;
    };
    let Ok(time) = timestamp.parse::<i64>() else {
        return false;
    };
    if now.abs_diff(time) > 300 {
        return false;
    }
    let Some(signature) = headers
        .get("x-tapped-signature")
        .and_then(|h| h.to_str().ok())
        .and_then(|h| hex::decode(h).ok())
    else {
        return false;
    };
    let Ok(mut mac) = Hmac::<Sha256>::new_from_slice(secret.as_bytes()) else {
        return false;
    };
    mac.update(timestamp.as_bytes());
    mac.update(b".");
    mac.update(body);
    mac.verify_slice(&signature).is_ok()
}

pub async fn webhook(
    State(state): State<AppStateDyn>,
    headers: HeaderMap,
    body: Bytes,
) -> Result<StatusCode, AppError> {
    let secret = state
        .auth_webhook_secret
        .as_deref()
        .filter(|s| s.len() >= 32)
        .ok_or_else(|| AppError::from_status(StatusCode::SERVICE_UNAVAILABLE))?;
    if !authorized(secret, &headers, &body, chrono::Utc::now().timestamp()) {
        return Err(AppError::unauthorized("invalid Auth webhook signature"));
    }
    if body.len() > 16_384 {
        return Err(AppError::from_status(StatusCode::PAYLOAD_TOO_LARGE));
    }
    let event: LifecycleEvent = serde_json::from_slice(&body)
        .map_err(|_| AppError::bad_request("invalid Auth lifecycle event"))?;
    let a = &event.account;
    if a.local_id.is_empty()
        || a.local_id.len() > 128
        || a.email.len() > 320
        || a.display_name.len() > 1024
        || a.created_ms() <= 0
        || a.created_ms() > chrono::Utc::now().timestamp_millis() + 300_000
    {
        return Err(AppError::bad_request("invalid Auth account"));
    }
    let pool = state
        .postgres
        .as_ref()
        .ok_or_else(|| AppError::from_status(StatusCode::SERVICE_UNAVAILABLE))?;
    receive(pool, &event)
        .await
        .map_err(|_| AppError::from_status(StatusCode::SERVICE_UNAVAILABLE))?;
    Ok(StatusCode::NO_CONTENT)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn signatures_bind_timestamp_and_exact_bytes_and_reject_expired_or_overflowing_time() {
        let secret = "test-secret";
        let body = br#"{ "kind": "signup" }"#;
        let mut mac = Hmac::<Sha256>::new_from_slice(secret.as_bytes()).unwrap();
        mac.update(b"1000.");
        mac.update(body);
        let mut headers = HeaderMap::new();
        headers.insert("x-tapped-timestamp", "1000".parse().unwrap());
        headers.insert(
            "x-tapped-signature",
            hex::encode(mac.finalize().into_bytes()).parse().unwrap(),
        );
        assert!(authorized(secret, &headers, body, 1001));
        assert!(!authorized(secret, &headers, b"{}", 1001));
        assert!(!authorized("other", &headers, body, 1001));
        assert!(!authorized(secret, &headers, body, 1301));
        headers.insert("x-tapped-timestamp", i64::MIN.to_string().parse().unwrap());
        assert!(!authorized(secret, &headers, body, 1001));
    }
}
