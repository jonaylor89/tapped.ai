//! OAuth 2.1 authorization server for the MCP endpoint (`/mcp`).
//!
//! Clients register dynamically (RFC 7591) and use PKCE (S256). `/oauth/authorize` validates the
//! request and sends the browser to the consent page on app.tapped.ai, where the user signs in
//! with Firebase and approves; the page then calls `approve` with the user's Firebase ID token.
//! Codes are single-use and tokens are opaque, stored only as SHA-256 hashes; refresh tokens
//! rotate and a replayed one revokes its grant.

use std::collections::HashMap;

use axum::{
    Form, Json,
    extract::{Path, Query, State},
    http::{StatusCode, header},
    response::{IntoResponse, Redirect, Response},
};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use reqwest::Url;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;

use crate::{domain::firebase_auth::FirebaseUser, errors::AppError, state::AppStateDyn};

pub const SCOPE: &str = "tapped";
const ACCESS_TTL_SECONDS: i64 = 60 * 60;
const REFRESH_TTL_DAYS: i64 = 90;
const REQUEST_TTL_MINUTES: i64 = 15;
const CODE_TTL_SECONDS: i64 = 120;

/// The public origin of this API, which is the OAuth issuer.
pub fn issuer() -> String {
    std::env::var("MCP_ISSUER")
        .unwrap_or_else(|_| "https://api.tapped.ai".into())
        .trim_end_matches('/')
        .to_owned()
}

/// The MCP resource identifier (RFC 8707) that tokens are bound to.
pub fn resource() -> String {
    format!("{}/mcp", issuer())
}

/// The sign-in and consent page on the web app.
fn consent_url() -> String {
    std::env::var("MCP_CONSENT_URL")
        .unwrap_or_else(|_| "https://app.tapped.ai/oauth/authorize".into())
}

pub(crate) fn pool(state: &AppStateDyn) -> Result<&PgPool, AppError> {
    state.postgres.as_ref().ok_or_else(|| {
        AppError::new("Postgres is unavailable").with_status(StatusCode::SERVICE_UNAVAILABLE)
    })
}

fn db_error(error: sqlx::Error) -> AppError {
    AppError::internal("MCP OAuth database error", error)
}

pub(crate) fn hash(token: &str) -> String {
    hex::encode(Sha256::digest(token.as_bytes()))
}

/// 244 random bits from two v4 UUIDs (the OS CSPRNG).
fn random_token(prefix: &str) -> String {
    format!(
        "{prefix}{}{}",
        Uuid::new_v4().simple(),
        Uuid::new_v4().simple()
    )
}

/// An OAuth error response (RFC 6749 §5.2).
fn oauth_error(status: StatusCode, error: &str, description: &str) -> Response {
    (
        status,
        [(header::CACHE_CONTROL, "no-store")],
        Json(json!({ "error": error, "error_description": description })),
    )
        .into_response()
}

fn no_store(body: Value) -> Response {
    ([(header::CACHE_CONTROL, "no-store")], Json(body)).into_response()
}

// Discovery

pub async fn protected_resource_metadata() -> Json<Value> {
    Json(json!({
        "resource": resource(),
        "authorization_servers": [issuer()],
        "scopes_supported": [SCOPE],
        "bearer_methods_supported": ["header"],
        "resource_name": "Tapped",
    }))
}

pub async fn authorization_server_metadata() -> Json<Value> {
    let issuer = issuer();
    Json(json!({
        "issuer": issuer,
        "authorization_endpoint": format!("{issuer}/oauth/authorize"),
        "token_endpoint": format!("{issuer}/oauth/token"),
        "registration_endpoint": format!("{issuer}/oauth/register"),
        "revocation_endpoint": format!("{issuer}/oauth/revoke"),
        "response_types_supported": ["code"],
        "grant_types_supported": ["authorization_code", "refresh_token"],
        "code_challenge_methods_supported": ["S256"],
        "token_endpoint_auth_methods_supported": ["none"],
        "revocation_endpoint_auth_methods_supported": ["none"],
        "scopes_supported": [SCOPE],
    }))
}

// Redirect URIs

fn is_loopback(url: &Url) -> bool {
    url.scheme() == "http" && matches!(url.host_str(), Some("localhost" | "127.0.0.1" | "[::1]"))
}

pub(crate) fn valid_redirect_uri(value: &str) -> bool {
    value.len() <= 2048
        && Url::parse(value).is_ok_and(|url| {
            url.fragment().is_none() && (url.scheme() == "https" || is_loopback(&url))
        })
}

/// Exact match, except loopback ports, which native clients pick at runtime (RFC 8252 §7.3).
pub(crate) fn redirect_uri_allowed(registered: &[String], requested: &str) -> bool {
    let Ok(requested_url) = Url::parse(requested) else {
        return false;
    };
    valid_redirect_uri(requested)
        && registered.iter().any(|uri| {
            uri == requested
                || Url::parse(uri).is_ok_and(|mut url| {
                    is_loopback(&url)
                        && is_loopback(&requested_url)
                        && url.set_port(requested_url.port()).is_ok()
                        && url == requested_url
                })
        })
}

fn with_params(redirect_uri: &str, params: &[(&str, &str)]) -> String {
    let mut url = Url::parse(redirect_uri).expect("redirect URIs are validated before use");
    url.query_pairs_mut().extend_pairs(params);
    url.into()
}

fn resource_matches(requested: Option<&String>) -> bool {
    requested.is_none_or(|value| value.trim_end_matches('/') == resource())
}

pub(crate) fn pkce_matches(verifier: &str, challenge: &str) -> bool {
    let valid = (43..=128).contains(&verifier.len())
        && verifier
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '.' | '_' | '~'));
    valid && URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes())) == challenge
}

// Dynamic client registration

pub async fn register(State(state): State<AppStateDyn>, body: Option<Json<Value>>) -> Response {
    let body = body.map(|Json(body)| body).unwrap_or_default();
    let redirect_uris: Vec<String> = body["redirect_uris"]
        .as_array()
        .map(|uris| {
            uris.iter()
                .filter_map(|u| u.as_str().map(str::to_owned))
                .collect()
        })
        .unwrap_or_default();
    let count = body["redirect_uris"].as_array().map_or(0, Vec::len);
    if redirect_uris.is_empty()
        || redirect_uris.len() != count
        || redirect_uris.len() > 10
        || !redirect_uris.iter().all(|uri| valid_redirect_uri(uri))
    {
        return oauth_error(
            StatusCode::BAD_REQUEST,
            "invalid_redirect_uri",
            "redirect_uris must be 1-10 https or http loopback URLs without fragments",
        );
    }
    if !matches!(
        body["token_endpoint_auth_method"].as_str(),
        None | Some("none")
    ) {
        return oauth_error(
            StatusCode::BAD_REQUEST,
            "invalid_client_metadata",
            "only public clients (token_endpoint_auth_method none) are supported",
        );
    }
    let name: String = body["client_name"]
        .as_str()
        .unwrap_or("")
        .trim()
        .chars()
        .take(100)
        .collect();
    let name = if name.is_empty() {
        "MCP client".to_owned()
    } else {
        name
    };
    let id = random_token("tmcp_client_");
    let pool = match pool(&state) {
        Ok(pool) => pool,
        Err(error) => return error.into_response(),
    };
    if let Err(error) =
        sqlx::query("INSERT INTO mcp_clients(id,name,redirect_uris) VALUES($1,$2,$3)")
            .bind(&id)
            .bind(&name)
            .bind(&redirect_uris)
            .execute(pool)
            .await
    {
        return db_error(error).into_response();
    }
    (
        StatusCode::CREATED,
        [(header::CACHE_CONTROL, "no-store")],
        Json(json!({
            "client_id": id,
            "client_id_issued_at": chrono::Utc::now().timestamp(),
            "client_name": name,
            "redirect_uris": redirect_uris,
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none",
            "scope": SCOPE,
        })),
    )
        .into_response()
}

// Authorization

/// Validates the request, stores it, and sends the browser to the consent page. Errors before the
/// redirect URI is trusted are shown on the consent page, never sent to the client.
pub async fn authorize(
    State(state): State<AppStateDyn>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Redirect, AppError> {
    let consent = |error: &str| Redirect::to(&with_params(&consent_url(), &[("error", error)]));
    let pool = pool(&state)?;
    let get = |key: &str| params.get(key).map(String::as_str);

    // Opportunistic cleanup keeps these tables small without a worker.
    sqlx::query("DELETE FROM mcp_authorization_requests WHERE expires_at < now()")
        .execute(pool)
        .await
        .map_err(db_error)?;
    sqlx::query("DELETE FROM mcp_tokens WHERE expires_at < now() - interval '1 day'")
        .execute(pool)
        .await
        .map_err(db_error)?;

    let client_id = get("client_id").unwrap_or("");
    let registered: Option<Vec<String>> =
        sqlx::query_scalar("SELECT redirect_uris FROM mcp_clients WHERE id=$1")
            .bind(client_id)
            .fetch_optional(pool)
            .await
            .map_err(db_error)?;
    let Some(registered) = registered else {
        return Ok(consent(
            "Unknown client. Reconnect Tapped from your MCP client.",
        ));
    };
    let redirect_uri = get("redirect_uri").unwrap_or("");
    if !redirect_uri_allowed(&registered, redirect_uri) {
        return Ok(consent(
            "The redirect URI is not registered for this client.",
        ));
    }

    let client_state = get("state");
    let fail = |error: &str, description: &str| {
        let mut params = vec![("error", error), ("error_description", description)];
        if let Some(state) = client_state {
            params.push(("state", state));
        }
        Ok(Redirect::to(&with_params(redirect_uri, &params)))
    };
    if get("response_type") != Some("code") {
        return fail("unsupported_response_type", "response_type must be code");
    }
    let challenge = get("code_challenge").unwrap_or("");
    let challenge_valid = challenge.len() == 43
        && challenge
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_'));
    if get("code_challenge_method") != Some("S256") || !challenge_valid {
        return fail(
            "invalid_request",
            "PKCE with code_challenge_method S256 is required",
        );
    }
    if !resource_matches(params.get("resource")) {
        return fail("invalid_target", "unknown resource");
    }
    if get("scope").is_some_and(|scope| scope.split(' ').any(|s| !s.is_empty() && s != SCOPE)) {
        return fail("invalid_scope", "the only scope is tapped");
    }

    let id = random_token("");
    sqlx::query(
        "INSERT INTO mcp_authorization_requests(id,client_id,redirect_uri,code_challenge,state,expires_at)
         VALUES($1,$2,$3,$4,$5,now() + make_interval(mins => $6))",
    )
    .bind(&id)
    .bind(client_id)
    .bind(redirect_uri)
    .bind(challenge)
    .bind(client_state)
    .bind(REQUEST_TTL_MINUTES as i32)
    .execute(pool)
    .await
    .map_err(db_error)?;
    Ok(Redirect::to(&with_params(
        &consent_url(),
        &[("request", &id)],
    )))
}

/// What the consent page shows: who is asking and where the browser goes next.
pub async fn authorization_request(
    State(state): State<AppStateDyn>,
    Path(id): Path<String>,
) -> Result<Response, AppError> {
    let row: Option<(String, String)> = sqlx::query_as(
        "SELECT c.name, r.redirect_uri FROM mcp_authorization_requests r JOIN mcp_clients c ON c.id=r.client_id
         WHERE r.id=$1 AND r.user_id IS NULL AND r.expires_at > now()",
    )
    .bind(&id)
    .fetch_optional(pool(&state)?)
    .await
    .map_err(db_error)?;
    let (client_name, redirect_uri) = row.ok_or_else(|| {
        AppError::not_found("This sign-in request expired. Start again from your MCP client.")
    })?;
    let redirect_host = Url::parse(&redirect_uri)
        .ok()
        .and_then(|url| url.host_str().map(str::to_owned))
        .unwrap_or_default();
    Ok(no_store(
        json!({ "clientName": client_name, "redirectHost": redirect_host }),
    ))
}

/// The signed-in user approves; returns where to send the browser with a single-use code.
pub async fn approve(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(id): Path<String>,
) -> Result<Response, AppError> {
    let code = random_token("tmcp_code_");
    let row: Option<(String, Option<String>)> = sqlx::query_as(
        "UPDATE mcp_authorization_requests
         SET user_id=$2, code_hash=$3, expires_at=now() + make_interval(secs => $4)
         WHERE id=$1 AND user_id IS NULL AND expires_at > now()
         RETURNING redirect_uri, state",
    )
    .bind(&id)
    .bind(&user.uid)
    .bind(hash(&code))
    .bind(CODE_TTL_SECONDS as f64)
    .fetch_optional(pool(&state)?)
    .await
    .map_err(db_error)?;
    let (redirect_uri, client_state) = row.ok_or_else(|| {
        AppError::not_found("This sign-in request expired. Start again from your MCP client.")
    })?;
    let issuer = issuer();
    let mut params = vec![("code", code.as_str()), ("iss", issuer.as_str())];
    if let Some(state) = &client_state {
        params.push(("state", state));
    }
    Ok(no_store(
        json!({ "redirectTo": with_params(&redirect_uri, &params) }),
    ))
}

pub async fn deny(
    State(state): State<AppStateDyn>,
    Path(id): Path<String>,
) -> Result<Response, AppError> {
    let row: Option<(String, Option<String>)> = sqlx::query_as(
        "DELETE FROM mcp_authorization_requests WHERE id=$1 AND user_id IS NULL RETURNING redirect_uri, state",
    )
    .bind(&id)
    .fetch_optional(pool(&state)?)
    .await
    .map_err(db_error)?;
    let (redirect_uri, client_state) =
        row.ok_or_else(|| AppError::not_found("unknown sign-in request"))?;
    let mut params = vec![
        ("error", "access_denied"),
        ("error_description", "The user declined access"),
    ];
    if let Some(state) = &client_state {
        params.push(("state", state));
    }
    Ok(no_store(
        json!({ "redirectTo": with_params(&redirect_uri, &params) }),
    ))
}

// Tokens

async fn user_deleted(tx: &mut Transaction<'_, Postgres>, uid: &str) -> Result<bool, sqlx::Error> {
    sqlx::query_scalar("SELECT coalesce((SELECT deleted FROM users WHERE id=$1), false)")
        .bind(uid)
        .fetch_one(&mut **tx)
        .await
}

async fn issue(tx: &mut Transaction<'_, Postgres>, grant: Uuid) -> Result<Value, sqlx::Error> {
    let access = random_token("tmcp_at_");
    let refresh = random_token("tmcp_rt_");
    sqlx::query(
        "INSERT INTO mcp_tokens(hash,grant_id,kind,expires_at) VALUES
         ($1,$3,'access',now() + make_interval(secs => $4)),
         ($2,$3,'refresh',now() + make_interval(days => $5))",
    )
    .bind(hash(&access))
    .bind(hash(&refresh))
    .bind(grant)
    .bind(ACCESS_TTL_SECONDS as f64)
    .bind(REFRESH_TTL_DAYS as i32)
    .execute(&mut **tx)
    .await?;
    Ok(json!({
        "access_token": access,
        "token_type": "Bearer",
        "expires_in": ACCESS_TTL_SECONDS,
        "refresh_token": refresh,
        "scope": SCOPE,
    }))
}

pub async fn token(
    State(state): State<AppStateDyn>,
    Form(form): Form<HashMap<String, String>>,
) -> Response {
    match exchange(&state, &form).await {
        Ok(Ok(body)) => no_store(body),
        Ok(Err((status, error, description))) => oauth_error(status, error, description),
        Err(error) => error.into_response(),
    }
}

type OAuthResult = Result<Value, (StatusCode, &'static str, &'static str)>;

async fn exchange(
    state: &AppStateDyn,
    form: &HashMap<String, String>,
) -> Result<OAuthResult, AppError> {
    let invalid_grant =
        |description| Ok(Err((StatusCode::BAD_REQUEST, "invalid_grant", description)));
    let get = |key: &str| form.get(key).map(String::as_str).unwrap_or("");
    let client_id = get("client_id");
    if !resource_matches(form.get("resource")) {
        return Ok(Err((
            StatusCode::BAD_REQUEST,
            "invalid_target",
            "unknown resource",
        )));
    }
    let mut tx = pool(state)?.begin().await.map_err(db_error)?;
    let body = match get("grant_type") {
        "authorization_code" => {
            // Deleting the request makes the code single-use, even under concurrent exchanges.
            let row: Option<(String, String, String, String)> = sqlx::query_as(
                "DELETE FROM mcp_authorization_requests WHERE code_hash=$1 AND expires_at > now()
                 RETURNING client_id, redirect_uri, code_challenge, user_id",
            )
            .bind(hash(get("code")))
            .fetch_optional(&mut *tx)
            .await
            .map_err(db_error)?;
            let Some((code_client, redirect_uri, challenge, uid)) = row else {
                return invalid_grant("invalid or expired authorization code");
            };
            if code_client != client_id || redirect_uri != get("redirect_uri") {
                return invalid_grant("the code was issued to another client or redirect URI");
            }
            if !pkce_matches(get("code_verifier"), &challenge) {
                return invalid_grant("code_verifier does not match the code challenge");
            }
            if user_deleted(&mut tx, &uid).await.map_err(db_error)? {
                return invalid_grant("the Tapped account was deleted");
            }
            let grant = Uuid::new_v4();
            sqlx::query("INSERT INTO mcp_grants(id,client_id,user_id) VALUES($1,$2,$3)")
                .bind(grant)
                .bind(client_id)
                .bind(&uid)
                .execute(&mut *tx)
                .await
                .map_err(db_error)?;
            issue(&mut tx, grant).await.map_err(db_error)?
        }
        "refresh_token" => {
            let row: Option<(Uuid, bool, String, String)> = sqlx::query_as(
                "SELECT t.grant_id, t.used_at IS NOT NULL, g.client_id, g.user_id
                 FROM mcp_tokens t JOIN mcp_grants g ON g.id=t.grant_id
                 WHERE t.hash=$1 AND t.kind='refresh' AND t.expires_at > now() AND g.revoked_at IS NULL
                 FOR UPDATE OF t",
            )
            .bind(hash(get("refresh_token")))
            .fetch_optional(&mut *tx)
            .await
            .map_err(db_error)?;
            let Some((grant, used, grant_client, uid)) = row else {
                return invalid_grant("invalid or expired refresh token");
            };
            if grant_client != client_id {
                return invalid_grant("the refresh token was issued to another client");
            }
            if used || user_deleted(&mut tx, &uid).await.map_err(db_error)? {
                // A replayed refresh token means it leaked: end the whole connection.
                sqlx::query("UPDATE mcp_grants SET revoked_at=now() WHERE id=$1")
                    .bind(grant)
                    .execute(&mut *tx)
                    .await
                    .map_err(db_error)?;
                tx.commit().await.map_err(db_error)?;
                return invalid_grant("the refresh token was revoked");
            }
            sqlx::query("UPDATE mcp_tokens SET used_at=now() WHERE hash=$1")
                .bind(hash(get("refresh_token")))
                .execute(&mut *tx)
                .await
                .map_err(db_error)?;
            issue(&mut tx, grant).await.map_err(db_error)?
        }
        _ => {
            return Ok(Err((
                StatusCode::BAD_REQUEST,
                "unsupported_grant_type",
                "grant_type must be authorization_code or refresh_token",
            )));
        }
    };
    tx.commit().await.map_err(db_error)?;
    Ok(Ok(body))
}

/// RFC 7009: revoking either token ends the connection. Unknown tokens are not an error.
pub async fn revoke(
    State(state): State<AppStateDyn>,
    Form(form): Form<HashMap<String, String>>,
) -> Response {
    let token = form.get("token").map(String::as_str).unwrap_or("");
    let pool = match pool(&state) {
        Ok(pool) => pool,
        Err(error) => return error.into_response(),
    };
    let result = sqlx::query(
        "UPDATE mcp_grants SET revoked_at=now() WHERE revoked_at IS NULL
         AND id=(SELECT grant_id FROM mcp_tokens WHERE hash=$1)",
    )
    .bind(hash(token))
    .execute(pool)
    .await;
    match result {
        Ok(_) => StatusCode::OK.into_response(),
        Err(error) => db_error(error).into_response(),
    }
}

/// The user behind a valid access token.
pub(crate) async fn access_token_user(
    pool: &PgPool,
    token: &str,
) -> Result<Option<String>, AppError> {
    sqlx::query_scalar(
        "SELECT g.user_id FROM mcp_tokens t JOIN mcp_grants g ON g.id=t.grant_id
         WHERE t.hash=$1 AND t.kind='access' AND t.expires_at > now() AND g.revoked_at IS NULL",
    )
    .bind(hash(token))
    .fetch_optional(pool)
    .await
    .map_err(db_error)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redirect_uris_are_https_or_loopback_and_match_exactly() {
        assert!(valid_redirect_uri(
            "https://claude.ai/api/mcp/auth_callback"
        ));
        assert!(valid_redirect_uri("http://localhost:3334/callback"));
        for uri in [
            "http://evil.example/cb",
            "javascript:alert(1)",
            "https://a.example/cb#x",
            "nope",
        ] {
            assert!(!valid_redirect_uri(uri), "{uri}");
        }
        let registered = vec![
            "https://claude.ai/cb".to_owned(),
            "http://localhost:3334/callback".to_owned(),
        ];
        assert!(redirect_uri_allowed(&registered, "https://claude.ai/cb"));
        assert!(!redirect_uri_allowed(&registered, "https://claude.ai/cb2"));
        assert!(redirect_uri_allowed(
            &registered,
            "http://localhost:51234/callback"
        ));
        assert!(!redirect_uri_allowed(
            &registered,
            "http://localhost:51234/other"
        ));
        assert!(!redirect_uri_allowed(
            &registered,
            "http://127.0.0.2:3334/callback"
        ));
    }

    #[test]
    fn pkce_requires_the_s256_verifier() {
        // RFC 7636 appendix B.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
        assert!(pkce_matches(
            verifier,
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        ));
        assert!(!pkce_matches(
            verifier,
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cN"
        ));
        assert!(!pkce_matches(
            "short",
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        ));
    }

    #[test]
    fn tokens_are_random_and_hashed() {
        let a = random_token("tmcp_at_");
        assert!(a.starts_with("tmcp_at_") && a.len() == 8 + 64);
        assert_ne!(a, random_token("tmcp_at_"));
        assert_eq!(hash(&a).len(), 64);
        assert_ne!(hash(&a), a);
    }
}
