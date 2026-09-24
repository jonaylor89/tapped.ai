use axum::{
    async_trait,
    extract::{FromRequestParts, Request, State},
    http::{StatusCode, request::Parts},
    middleware::Next,
    response::Response,
};
use jsonwebtoken::{DecodingKey, Validation, decode, decode_header, jwk::JwkSet};
use serde::{Deserialize, Serialize};
use std::sync::OnceLock;
use tokio::sync::RwLock;

use crate::state::AppStateDyn;

const FIREBASE_JWK_URL: &str =
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";

static CACHED_JWKS: OnceLock<RwLock<Option<JwkSet>>> = OnceLock::new();

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct FirebaseClaims {
    pub sub: String,
    pub email: Option<String>,
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

/// Seed the JWK cache with a pre-built JwkSet. Used in tests to inject mock keys.
#[cfg(test)]
pub async fn seed_jwk_cache(jwks: JwkSet) {
    let lock = CACHED_JWKS.get_or_init(|| RwLock::new(None));
    let mut write = lock.write().await;
    *write = Some(jwks);
}

/// Axum middleware that validates a Firebase ID token from the `Authorization: Bearer <token>`
/// header and inserts a [`FirebaseUser`] into request extensions.
///
/// Apply to routes with `route_layer(middleware::from_fn_with_state(state, verify_firebase_token))`.
/// Not applied to any routes by default.
pub async fn verify_firebase_token(
    State(state): State<AppStateDyn>,
    mut req: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    let token = req
        .headers()
        .get("Authorization")
        .and_then(|h| h.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer "))
        .ok_or(StatusCode::UNAUTHORIZED)?;

    let header = decode_header(token).map_err(|_| StatusCode::UNAUTHORIZED)?;
    let kid = header.kid.ok_or(StatusCode::UNAUTHORIZED)?;

    let project_id = &state.firebase_project_id;

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
    validation.set_audience(&[project_id.as_str()]);
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::data::{database::MockDatabase, search::MockSearch};
    use axum::{Router, body::Body, middleware, routing::get};
    use jsonwebtoken::{EncodingKey, Header};
    use std::sync::Arc;
    use tower::ServiceExt;

    const TEST_PROJECT_ID: &str = "test-project";
    const TEST_KID: &str = "test-key-id";

    const TEST_RSA_PRIVATE_PEM: &str = include_str!("../../tests/fixtures/test_rsa_private.pem");

    const TEST_JWKS_JSON: &str = include_str!("../../tests/fixtures/test_jwks.json");

    fn test_state() -> AppStateDyn {
        AppStateDyn {
            database: Arc::new(MockDatabase),
            search: Arc::new(MockSearch),
            firebase_project_id: TEST_PROJECT_ID.to_string(),
        }
    }

    fn make_test_token(sub: &str, email: Option<&str>) -> String {
        let mut header = Header::new(jsonwebtoken::Algorithm::RS256);
        header.kid = Some(TEST_KID.to_string());

        let now = jsonwebtoken::get_current_timestamp();
        let claims = serde_json::json!({
            "sub": sub,
            "email": email,
            "aud": TEST_PROJECT_ID,
            "iss": format!("https://securetoken.google.com/{}", TEST_PROJECT_ID),
            "iat": now,
            "exp": now + 3600,
        });

        let key = EncodingKey::from_rsa_pem(TEST_RSA_PRIVATE_PEM.as_bytes())
            .expect("invalid test RSA key");
        jsonwebtoken::encode(&header, &claims, &key).expect("failed to encode test JWT")
    }

    fn make_bad_token(claims: serde_json::Value, kid: &str) -> String {
        let mut header = Header::new(jsonwebtoken::Algorithm::RS256);
        header.kid = Some(kid.to_string());
        let key = EncodingKey::from_rsa_pem(TEST_RSA_PRIVATE_PEM.as_bytes()).unwrap();
        jsonwebtoken::encode(&header, &claims, &key).unwrap()
    }

    async fn setup_jwk_cache() {
        let jwks: JwkSet = serde_json::from_str(TEST_JWKS_JSON).expect("invalid test JWKS");
        seed_jwk_cache(jwks).await;
    }

    fn test_app() -> Router {
        let state = test_state();
        Router::new()
            .route(
                "/protected",
                get(|user: FirebaseUser| async move {
                    format!("uid={},email={}", user.uid, user.email.unwrap_or_default())
                }),
            )
            .layer(middleware::from_fn_with_state(
                state.clone(),
                verify_firebase_token,
            ))
            .with_state(state)
    }

    #[tokio::test]
    async fn rejects_request_without_auth_header() {
        setup_jwk_cache().await;
        let app = test_app();

        let req = Request::builder()
            .uri("/protected")
            .body(Body::empty())
            .unwrap();

        let resp = app.oneshot(req).await.unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn rejects_request_with_invalid_token() {
        setup_jwk_cache().await;
        let app = test_app();

        let req = Request::builder()
            .uri("/protected")
            .header("Authorization", "Bearer not-a-real-jwt")
            .body(Body::empty())
            .unwrap();

        let resp = app.oneshot(req).await.unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn rejects_token_with_wrong_audience() {
        setup_jwk_cache().await;
        let app = test_app();

        let now = jsonwebtoken::get_current_timestamp();
        let bad_token = make_bad_token(
            serde_json::json!({
                "sub": "user-123",
                "aud": "wrong-project-id",
                "iss": format!("https://securetoken.google.com/{}", TEST_PROJECT_ID),
                "iat": now, "exp": now + 3600,
            }),
            TEST_KID,
        );

        let req = Request::builder()
            .uri("/protected")
            .header("Authorization", format!("Bearer {}", bad_token))
            .body(Body::empty())
            .unwrap();

        let resp = app.oneshot(req).await.unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn rejects_token_with_wrong_issuer() {
        setup_jwk_cache().await;
        let app = test_app();

        let now = jsonwebtoken::get_current_timestamp();
        let bad_token = make_bad_token(
            serde_json::json!({
                "sub": "user-123",
                "aud": TEST_PROJECT_ID,
                "iss": "https://evil.example.com",
                "iat": now, "exp": now + 3600,
            }),
            TEST_KID,
        );

        let req = Request::builder()
            .uri("/protected")
            .header("Authorization", format!("Bearer {}", bad_token))
            .body(Body::empty())
            .unwrap();

        let resp = app.oneshot(req).await.unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn rejects_expired_token() {
        setup_jwk_cache().await;
        let app = test_app();

        let bad_token = make_bad_token(
            serde_json::json!({
                "sub": "user-123",
                "aud": TEST_PROJECT_ID,
                "iss": format!("https://securetoken.google.com/{}", TEST_PROJECT_ID),
                "iat": 1000000, "exp": 1000001,
            }),
            TEST_KID,
        );

        let req = Request::builder()
            .uri("/protected")
            .header("Authorization", format!("Bearer {}", bad_token))
            .body(Body::empty())
            .unwrap();

        let resp = app.oneshot(req).await.unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn rejects_token_with_unknown_kid() {
        setup_jwk_cache().await;
        let app = test_app();

        let now = jsonwebtoken::get_current_timestamp();
        let bad_token = make_bad_token(
            serde_json::json!({
                "sub": "user-123",
                "aud": TEST_PROJECT_ID,
                "iss": format!("https://securetoken.google.com/{}", TEST_PROJECT_ID),
                "iat": now, "exp": now + 3600,
            }),
            "unknown-kid",
        );

        let req = Request::builder()
            .uri("/protected")
            .header("Authorization", format!("Bearer {}", bad_token))
            .body(Body::empty())
            .unwrap();

        let resp = app.oneshot(req).await.unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn accepts_valid_token_and_extracts_user() {
        setup_jwk_cache().await;
        let app = test_app();

        let token = make_test_token("user-abc-123", Some("test@tapped.ai"));

        let req = Request::builder()
            .uri("/protected")
            .header("Authorization", format!("Bearer {}", token))
            .body(Body::empty())
            .unwrap();

        let resp = app.oneshot(req).await.unwrap();
        assert_eq!(resp.status(), StatusCode::OK);

        let body = axum::body::to_bytes(resp.into_body(), usize::MAX)
            .await
            .unwrap();
        let body_str = String::from_utf8(body.to_vec()).unwrap();
        assert_eq!(body_str, "uid=user-abc-123,email=test@tapped.ai");
    }

    #[tokio::test]
    async fn accepts_valid_token_without_email() {
        setup_jwk_cache().await;
        let app = test_app();

        let token = make_test_token("user-no-email", None);

        let req = Request::builder()
            .uri("/protected")
            .header("Authorization", format!("Bearer {}", token))
            .body(Body::empty())
            .unwrap();

        let resp = app.oneshot(req).await.unwrap();
        assert_eq!(resp.status(), StatusCode::OK);

        let body = axum::body::to_bytes(resp.into_body(), usize::MAX)
            .await
            .unwrap();
        let body_str = String::from_utf8(body.to_vec()).unwrap();
        assert_eq!(body_str, "uid=user-no-email,email=");
    }
}
