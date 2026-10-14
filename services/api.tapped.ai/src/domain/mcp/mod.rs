//! Remote MCP server for Tapped performers: `/mcp` (Streamable HTTP via the official `rmcp`
//! SDK, stateless) plus the OAuth endpoints that connect Claude and other MCP clients to an
//! account. See `services/api.tapped.ai/README.md#mcp-server`.

pub mod oauth;
pub mod tools;

use std::sync::Arc;

use axum::{
    Json, Router,
    extract::{Request, State},
    http::{HeaderName, Method, StatusCode, header},
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use rmcp::transport::streamable_http_server::{
    StreamableHttpServerConfig, StreamableHttpService, session::never::NeverSessionManager,
};
use serde_json::json;
use tower_http::cors::{Any, CorsLayer};

use crate::{
    domain::firebase_auth::{FirebaseUser, verify_firebase_token},
    rate_limit::RateLimits,
    state::AppStateDyn,
};

pub fn router(state: AppStateDyn, rate_limits: &RateLimits) -> Router<AppStateDyn> {
    // Bearer tokens only, never cookies, so any origin may call these (e.g. browser-based clients).
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods([Method::GET, Method::POST, Method::DELETE, Method::OPTIONS])
        .allow_headers([
            header::AUTHORIZATION,
            header::CONTENT_TYPE,
            HeaderName::from_static("mcp-protocol-version"),
            HeaderName::from_static("mcp-session-id"),
            HeaderName::from_static("last-event-id"),
        ])
        .expose_headers([
            header::WWW_AUTHENTICATE,
            HeaderName::from_static("mcp-session-id"),
        ]);

    let approve = Router::new()
        .route(
            "/oauth/authorization-requests/{id}/approve",
            post(oauth::approve),
        )
        .route_layer(middleware::from_fn_with_state(
            state.clone(),
            verify_firebase_token,
        ));

    let mcp = Router::new()
        .route_service("/mcp", mcp_service(state.clone()))
        .route_layer(middleware::from_fn_with_state(state, require_access_token));

    // Unauthenticated endpoints that write rows are limited per IP.
    let limited = Router::new()
        .route("/oauth/register", post(oauth::register))
        .route("/oauth/authorize", get(oauth::authorize))
        .route("/oauth/token", post(oauth::token))
        .route("/oauth/revoke", post(oauth::revoke))
        .route(
            "/oauth/authorization-requests/{id}",
            get(oauth::authorization_request),
        )
        .route("/oauth/authorization-requests/{id}/deny", post(oauth::deny))
        .layer(rate_limits.per_ip_layer());

    Router::new()
        .route(
            "/.well-known/oauth-protected-resource",
            get(oauth::protected_resource_metadata),
        )
        .route(
            "/.well-known/oauth-protected-resource/mcp",
            get(oauth::protected_resource_metadata),
        )
        .route(
            "/.well-known/oauth-authorization-server",
            get(oauth::authorization_server_metadata),
        )
        .merge(mcp)
        .merge(limited)
        .merge(approve)
        .layer(cors)
}

/// Stateless Streamable HTTP: each request gets a fresh server, JSON responses where possible.
fn mcp_service(state: AppStateDyn) -> StreamableHttpService<tools::TappedMcp, NeverSessionManager> {
    StreamableHttpService::new(
        move || Ok(tools::TappedMcp::new(state.clone())),
        Arc::new(NeverSessionManager::default()),
        StreamableHttpServerConfig::default()
            .with_legacy_session_mode(false)
            .with_json_response(true)
            .with_sse_keep_alive(None)
            // Host allowlisting guards unauthenticated local servers against DNS rebinding.
            // This one is public and every request carries a bearer token.
            .disable_allowed_hosts(),
    )
}

/// Resolves the bearer access token to its user, or answers with the RFC 9728 challenge that
/// starts the OAuth flow in MCP clients.
async fn require_access_token(
    State(state): State<AppStateDyn>,
    mut request: Request,
    next: Next,
) -> Response {
    let token = request
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| {
            value
                .strip_prefix("Bearer ")
                .or_else(|| value.strip_prefix("bearer "))
        })
        .map(|token| token.trim().to_owned());
    let Some(token) = token else {
        return unauthorized(None);
    };
    let pool = match oauth::pool(&state) {
        Ok(pool) => pool,
        Err(error) => return error.into_response(),
    };
    match oauth::access_token_user(pool, &token).await {
        Ok(Some(uid)) => {
            tracing::Span::current().record("user_id", uid.as_str());
            request
                .extensions_mut()
                .insert(FirebaseUser { uid, email: None });
            next.run(request).await
        }
        Ok(None) => unauthorized(Some("invalid_token")),
        Err(error) => error.into_response(),
    }
}

fn unauthorized(error: Option<&str>) -> Response {
    let metadata = format!(
        "{}/.well-known/oauth-protected-resource/mcp",
        oauth::issuer()
    );
    let challenge = match error {
        Some(error) => format!(r#"Bearer error="{error}", resource_metadata="{metadata}""#),
        None => format!(r#"Bearer resource_metadata="{metadata}""#),
    };
    (
        StatusCode::UNAUTHORIZED,
        [
            (header::WWW_AUTHENTICATE, challenge),
            (header::CACHE_CONTROL, "no-store".to_owned()),
        ],
        Json(json!({
            "error": error.unwrap_or("unauthorized"),
            "error_description": "Connect your Tapped account to use this MCP server",
        })),
    )
        .into_response()
}
