//! Firebase-bound one-time OAuth state with PKCE. Provider tokens remain in private Postgres.
use crate::{
    data::spotify::OAuthToken, domain::firebase_auth::FirebaseUser, errors::AppError,
    state::AppStateDyn,
};
use axum::{
    Json,
    extract::{Query, State},
    http::StatusCode,
    response::Html,
};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::{PgPool, Postgres, Transaction};

fn pool(state: &AppStateDyn) -> Result<&PgPool, AppError> {
    state
        .postgres
        .as_ref()
        .ok_or_else(|| AppError::from_status(StatusCode::SERVICE_UNAVAILABLE))
}
fn db_error(_: sqlx::Error) -> AppError {
    AppError::from_status(StatusCode::SERVICE_UNAVAILABLE)
}
fn upstream(_: anyhow::Error) -> AppError {
    AppError::from_status(StatusCode::BAD_GATEWAY)
}
fn random() -> String {
    format!(
        "{}{}",
        uuid::Uuid::new_v4().simple(),
        uuid::Uuid::new_v4().simple()
    )
}
fn hash(s: &str) -> String {
    hex::encode(Sha256::digest(s.as_bytes()))
}
fn public_grant(t: &OAuthToken) -> Value {
    json!({"accessToken":t.access_token,"refreshToken":t.refresh_token,"expiresIn":t.expires_in,"scope":t.scope,"tokenType":t.token_type})
}

pub async fn authorize(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
) -> Result<Json<Value>, AppError> {
    let nonce = random();
    let verifier = random();
    let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
    let url = state
        .spotify
        .authorize_url(&nonce, &challenge)
        .map_err(upstream)?;
    let pool = pool(&state)?;
    let mut tx = pool.begin().await.map_err(db_error)?;
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))")
        .bind(format!("users:{}", user.uid))
        .execute(&mut *tx)
        .await
        .map_err(db_error)?;
    // Bound outstanding private state per user; preserve recent browser sessions.
    sqlx::query("DELETE FROM spotify_oauth_states WHERE user_id=$1 AND expires_at<=now()")
        .bind(&user.uid)
        .execute(&mut *tx)
        .await
        .map_err(db_error)?;
    let count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM spotify_oauth_states WHERE user_id=$1 AND consumed_at IS NULL",
    )
    .bind(&user.uid)
    .fetch_one(&mut *tx)
    .await
    .map_err(db_error)?;
    if count >= 10 {
        return Err(AppError::from_status(StatusCode::TOO_MANY_REQUESTS));
    }
    sqlx::query("INSERT INTO spotify_oauth_states(state_hash,user_id,verifier,redirect_uri,expires_at) VALUES($1,$2,$3,$4,now()+interval '10 minutes')")
        .bind(hash(&nonce)).bind(&user.uid).bind(verifier).bind(state.spotify.oauth_redirect_uri()).execute(&mut *tx).await.map_err(db_error)?;
    tx.commit().await.map_err(db_error)?;
    Ok(Json(json!({"authorizationUrl":url,"state":nonce})))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Exchange {
    pub state: String,
    pub code: String,
}

async fn persist(
    tx: &mut Transaction<'_, Postgres>,
    uid: &str,
    t: &OAuthToken,
) -> Result<(), AppError> {
    sqlx::query("INSERT INTO spotify_oauth_tokens(user_id,access_token,refresh_token,token_type,scope,expires_at) VALUES($1,$2,$3,$4,$5,now()+make_interval(secs=>$6)) ON CONFLICT(user_id) DO UPDATE SET access_token=EXCLUDED.access_token,refresh_token=EXCLUDED.refresh_token,token_type=EXCLUDED.token_type,scope=EXCLUDED.scope,expires_at=EXCLUDED.expires_at,updated_at=now()")
        .bind(uid).bind(&t.access_token).bind(t.refresh_token.as_deref().unwrap_or_default()).bind(&t.token_type).bind(&t.scope).bind(t.expires_in as f64)
        .execute(&mut **tx).await.map_err(db_error)?;
    Ok(())
}

async fn complete(
    state: &AppStateDyn,
    command: Exchange,
    expected_uid: Option<&str>,
) -> Result<OAuthToken, AppError> {
    if command.state.len() != 64
        || !command.state.bytes().all(|c| c.is_ascii_hexdigit())
        || command.code.is_empty()
        || command.code.len() > 4096
    {
        return Err(AppError::bad_request("invalid Spotify OAuth callback"));
    }
    let pool = pool(state)?;
    let key = hash(&command.state);
    let uid:Option<String>=sqlx::query_scalar("SELECT user_id FROM spotify_oauth_states WHERE state_hash=$1 AND consumed_at IS NULL AND expires_at>now()")
        .bind(&key).fetch_optional(pool).await.map_err(db_error)?;
    let uid = uid
        .filter(|uid| expected_uid.is_none_or(|expected| expected == uid))
        .ok_or_else(|| AppError::bad_request("invalid or expired OAuth state"))?;
    let mut tx = pool.begin().await.map_err(db_error)?;
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))")
        .bind(format!("users:{uid}"))
        .execute(&mut *tx)
        .await
        .map_err(db_error)?;
    let row:Option<(String,String)>=sqlx::query_as("SELECT verifier,redirect_uri FROM spotify_oauth_states WHERE state_hash=$1 AND consumed_at IS NULL AND expires_at>now() FOR UPDATE")
        .bind(&key).fetch_optional(&mut *tx).await.map_err(db_error)?;
    let (verifier, redirect) =
        row.ok_or_else(|| AppError::bad_request("invalid or expired OAuth state"))?;
    let deleted: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM firebase_identities WHERE uid=$1 AND deleted)",
    )
    .bind(&uid)
    .fetch_one(&mut *tx)
    .await
    .map_err(db_error)?;
    if deleted {
        return Err(AppError::unauthorized("account deleted"));
    }
    let token = state
        .spotify
        .exchange(&command.code, &verifier, &redirect)
        .await
        .map_err(upstream)?;
    if token.refresh_token.as_ref().is_none_or(|t| t.is_empty()) {
        return Err(AppError::from_status(StatusCode::BAD_GATEWAY));
    }
    persist(&mut tx, &uid, &token).await?;
    sqlx::query(
        "UPDATE spotify_oauth_states SET consumed_at=now(),verifier='' WHERE state_hash=$1",
    )
    .bind(key)
    .execute(&mut *tx)
    .await
    .map_err(db_error)?;
    tx.commit().await.map_err(db_error)?;
    Ok(token)
}

pub async fn exchange(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Json(command): Json<Exchange>,
) -> Result<Json<Value>, AppError> {
    complete(&state, command, Some(&user.uid))
        .await
        .map(|t| Json(public_grant(&t)))
}

#[derive(Deserialize)]
pub struct Callback {
    state: String,
    code: Option<String>,
    error: Option<String>,
}
pub async fn callback(
    State(state): State<AppStateDyn>,
    Query(command): Query<Callback>,
) -> Result<Html<&'static str>, AppError> {
    if command.error.is_some() {
        return Err(AppError::bad_request("Spotify authorization declined"));
    }
    complete(
        &state,
        Exchange {
            state: command.state,
            code: command.code.unwrap_or_default(),
        },
        None,
    )
    .await?;
    // Never put grants in a redirect/query string or an unauthenticated browser response.
    Ok(Html(
        "<!doctype html><title>Spotify connected</title><p>Spotify connected. You can return to Tapped.</p>",
    ))
}

pub async fn refresh(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
) -> Result<Json<Value>, AppError> {
    let mut tx = pool(&state)?.begin().await.map_err(db_error)?;
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))")
        .bind(format!("users:{}", user.uid))
        .execute(&mut *tx)
        .await
        .map_err(db_error)?;
    let old: Option<String> = sqlx::query_scalar(
        "SELECT refresh_token FROM spotify_oauth_tokens WHERE user_id=$1 FOR UPDATE",
    )
    .bind(&user.uid)
    .fetch_optional(&mut *tx)
    .await
    .map_err(db_error)?;
    let old = old
        .filter(|s| !s.is_empty())
        .ok_or_else(|| AppError::not_found("Spotify account not connected"))?;
    let mut token = state.spotify.refresh(&old).await.map_err(upstream)?;
    if token.refresh_token.as_ref().is_none_or(|t| t.is_empty()) {
        token.refresh_token = Some(old);
    }
    persist(&mut tx, &user.uid, &token).await?;
    tx.commit().await.map_err(db_error)?;
    Ok(Json(public_grant(&token)))
}
