use axum::{
    async_trait,
    extract::{FromRequestParts, Request},
    http::{StatusCode, request::Parts},
    middleware::Next,
    response::Response,
};
use jsonwebtoken::{DecodingKey, Validation, decode, decode_header, jwk::JwkSet};
use serde::{Deserialize, Serialize};
use std::sync::OnceLock;
use tokio::sync::RwLock;

const FIREBASE_JWK_URL: &str =
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";

static CACHED_JWKS: OnceLock<RwLock<Option<JwkSet>>> = OnceLock::new();

#[derive(Debug, Clone, Serialize, Deserialize)]
struct FirebaseClaims {
    sub: String,
    email: Option<String>,
}

/// The authenticated Firebase user, populated by [`verify_firebase_token`] middleware.
/// Add this as an extractor on any route that requires Firebase auth.
#[derive(Debug, Clone)]
pub struct FirebaseUser {
    pub uid: String,
    pub email: Option<String>,
}

async fn fetch_jwks() -> anyhow::Result<JwkSet> {
    let jwks = reqwest::get(FIREBASE_JWK_URL)
        .await?
        .json::<JwkSet>()
        .await?;
    Ok(jwks)
}

async fn get_jwks() -> anyhow::Result<JwkSet> {
    let lock = CACHED_JWKS.get_or_init(|| RwLock::new(None));

    {
        let read = lock.read().await;
        if let Some(jwks) = read.as_ref() {
            return Ok(jwks.clone());
        }
    }

    let jwks = fetch_jwks().await?;
    let mut write = lock.write().await;
    *write = Some(jwks.clone());
    Ok(jwks)
}

/// Axum middleware that validates a Firebase ID token from the `Authorization: Bearer <token>`
/// header and inserts a [`FirebaseUser`] into request extensions.
///
/// Apply to routes with `route_layer(middleware::from_fn(verify_firebase_token))`.
/// Not applied to any routes by default.
pub async fn verify_firebase_token(mut req: Request, next: Next) -> Result<Response, StatusCode> {
    let token = req
        .headers()
        .get("Authorization")
        .and_then(|h| h.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer "))
        .ok_or(StatusCode::UNAUTHORIZED)?;

    let header = decode_header(token).map_err(|_| StatusCode::UNAUTHORIZED)?;
    let kid = header.kid.ok_or(StatusCode::UNAUTHORIZED)?;

    let project_id = std::env::var("FIREBASE_PROJECT_ID").map_err(|_| {
        tracing::error!("FIREBASE_PROJECT_ID env var not set");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let jwks = get_jwks().await.map_err(|e| {
        tracing::error!("failed to fetch Firebase JWKs: {:?}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let jwk = jwks.find(&kid).ok_or_else(|| {
        tracing::warn!("no JWK found for kid={}", kid);
        StatusCode::UNAUTHORIZED
    })?;

    let decoding_key = DecodingKey::from_jwk(jwk).map_err(|_| StatusCode::UNAUTHORIZED)?;

    let mut validation = Validation::new(jsonwebtoken::Algorithm::RS256);
    validation.set_audience(&[&project_id]);
    validation.set_issuer(&[format!("https://securetoken.google.com/{}", project_id)]);

    let token_data = decode::<FirebaseClaims>(token, &decoding_key, &validation).map_err(|e| {
        tracing::warn!("firebase token validation failed: {:?}", e);
        StatusCode::UNAUTHORIZED
    })?;

    req.extensions_mut().insert(FirebaseUser {
        uid: token_data.claims.sub,
        email: token_data.claims.email,
    });

    Ok(next.run(req).await)
}

#[async_trait]
impl<S> FromRequestParts<S> for FirebaseUser
where
    S: Send + Sync,
{
    type Rejection = StatusCode;

    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
        parts
            .extensions
            .get::<FirebaseUser>()
            .cloned()
            .ok_or(StatusCode::UNAUTHORIZED)
    }
}
