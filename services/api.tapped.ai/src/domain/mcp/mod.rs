//! Remote MCP server for Tapped performers: `POST /mcp` (Streamable HTTP, stateless, JSON
//! responses) plus the OAuth endpoints that connect Claude and other MCP clients to an account.
//! See `services/api.tapped.ai/README.md#mcp-server`.

pub mod oauth;
pub mod tools;

use aide::axum::ApiRouter;
use axum::{
    Json,
    body::Bytes,
    extract::State,
    http::{HeaderMap, HeaderName, Method, StatusCode, header},
    middleware,
    response::{IntoResponse, Response},
    routing::{get, post},
};
use serde_json::{Value, json};
use tower_http::cors::{Any, CorsLayer};

use crate::{
    domain::firebase_auth::{FirebaseUser, verify_firebase_token},
    rate_limit::RateLimits,
    state::AppStateDyn,
};

const PROTOCOL_VERSIONS: [&str; 3] = ["2025-11-25", "2025-06-18", "2025-03-26"];

pub fn router(state: AppStateDyn, rate_limits: &RateLimits) -> ApiRouter<AppStateDyn> {
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

    let approve = ApiRouter::new()
        .route(
            "/oauth/authorization-requests/{id}/approve",
            post(oauth::approve),
        )
        .route_layer(middleware::from_fn_with_state(state, verify_firebase_token));

    // Unauthenticated endpoints that write rows are limited per IP.
    let limited = ApiRouter::new()
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

    ApiRouter::new()
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
        .route(
            "/mcp",
            post(handle)
                .get(method_not_allowed)
                .delete(method_not_allowed),
        )
        .merge(limited)
        .merge(approve)
        .layer(cors)
}

/// No server-initiated stream and no sessions (stateless).
async fn method_not_allowed() -> Response {
    (
        StatusCode::METHOD_NOT_ALLOWED,
        [(header::ALLOW, "POST")],
        Json(json!({ "error": "method not allowed" })),
    )
        .into_response()
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

fn rpc_result(id: &Value, result: Value) -> Response {
    rpc(json!({ "jsonrpc": "2.0", "id": id, "result": result }))
}

fn rpc_error(id: &Value, code: i64, message: &str) -> Response {
    rpc(json!({ "jsonrpc": "2.0", "id": id, "error": { "code": code, "message": message } }))
}

fn rpc(body: Value) -> Response {
    ([(header::CACHE_CONTROL, "no-store")], Json(body)).into_response()
}

async fn handle(State(state): State<AppStateDyn>, headers: HeaderMap, body: Bytes) -> Response {
    let Some(token) = headers
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| {
            value
                .strip_prefix("Bearer ")
                .or_else(|| value.strip_prefix("bearer "))
        })
    else {
        return unauthorized(None);
    };
    let pool = match oauth::pool(&state) {
        Ok(pool) => pool,
        Err(error) => return error.into_response(),
    };
    let uid = match oauth::access_token_user(pool, token.trim()).await {
        Ok(Some(uid)) => uid,
        Ok(None) => return unauthorized(Some("invalid_token")),
        Err(error) => return error.into_response(),
    };
    tracing::Span::current().record("user_id", uid.as_str());
    let user = FirebaseUser { uid, email: None };

    let Ok(message) = serde_json::from_slice::<Value>(&body) else {
        return rpc_error(&Value::Null, -32700, "Parse error");
    };
    if !message.is_object() || message["jsonrpc"] != "2.0" {
        // JSON-RPC batches were removed from MCP in 2025-06-18.
        return rpc_error(&Value::Null, -32600, "Invalid Request");
    }
    let Some(id) = message.get("id").filter(|id| !id.is_null()) else {
        // Notifications (e.g. notifications/initialized) and client responses need no reply.
        return StatusCode::ACCEPTED.into_response();
    };
    let params = &message["params"];
    match message["method"].as_str().unwrap_or("") {
        "initialize" => {
            let requested = params["protocolVersion"].as_str().unwrap_or("");
            let version = PROTOCOL_VERSIONS
                .into_iter()
                .find(|v| *v == requested)
                .unwrap_or(PROTOCOL_VERSIONS[1]);
            rpc_result(
                id,
                json!({
                    "protocolVersion": version,
                    "capabilities": { "tools": {} },
                    "serverInfo": { "name": "tapped", "title": "Tapped", "version": env!("CARGO_PKG_VERSION") },
                    "instructions": tools::INSTRUCTIONS,
                }),
            )
        }
        "ping" => rpc_result(id, json!({})),
        "tools/list" => rpc_result(id, json!({ "tools": tools::definitions() })),
        "tools/call" => {
            let name = params["name"].as_str().unwrap_or("");
            let arguments = params.get("arguments").cloned().unwrap_or(Value::Null);
            match tools::call(&state, &user, name, arguments).await {
                None => rpc_error(id, -32602, &format!("Unknown tool: {name}")),
                Some(Ok(value)) => rpc_result(
                    id,
                    json!({
                        "content": [{ "type": "text", "text": serde_json::to_string_pretty(&value).unwrap_or_default() }],
                        "isError": false,
                    }),
                ),
                Some(Err(tools::ToolError(message))) => rpc_result(
                    id,
                    json!({ "content": [{ "type": "text", "text": message }], "isError": true }),
                ),
            }
        }
        _ => rpc_error(id, -32601, "Method not found"),
    }
}
