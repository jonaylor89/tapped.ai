use axum::{
    async_trait,
    extract::{FromRequestParts, Request, State},
    http::{HeaderMap, header::CACHE_CONTROL, request::Parts},
    middleware::Next,
    response::Response,
};
use jsonwebtoken::{
    DecodingKey, Validation, decode, decode_header,
    jwk::{Jwk, JwkSet},
};
use serde::{Deserialize, Serialize};
use std::{
    sync::OnceLock,
    time::{Duration, Instant},
};
use tokio::sync::RwLock;

use crate::{errors::AppError, state::AppStateDyn};

const FIREBASE_JWK_URL: &str =
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";

/// Used when Google omits `Cache-Control: max-age` (it normally sends ~6h).
const DEFAULT_JWKS_MAX_AGE: Duration = Duration::from_secs(60 * 60);
const MAX_JWKS_MAX_AGE: Duration = Duration::from_secs(24 * 60 * 60);
/// Tokens with an unknown `kid` refetch the keys at most this often, so garbage tokens can't
/// turn every request into a call to Google.
const MIN_JWKS_REFRESH_INTERVAL: Duration = Duration::from_secs(30);

struct CachedJwks {
    keys: JwkSet,
    fetched_at: Instant,
    expires_at: Instant,
}

static CACHED_JWKS: OnceLock<RwLock<Option<CachedJwks>>> = OnceLock::new();

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

fn max_age(headers: &HeaderMap) -> Duration {
    headers
        .get_all(CACHE_CONTROL)
        .iter()
        .filter_map(|value| value.to_str().ok())
        .flat_map(|value| value.split(','))
        .find_map(|directive| directive.trim().strip_prefix("max-age=")?.parse().ok())
        .map(Duration::from_secs)
        .unwrap_or(DEFAULT_JWKS_MAX_AGE)
        .min(MAX_JWKS_MAX_AGE)
}

#[tracing::instrument(fields(dependency = "google_jwks", otel.kind = "client", server.address = "www.googleapis.com"))]
async fn fetch_jwks() -> anyhow::Result<(JwkSet, Duration)> {
    let response = crate::http::client()
        .get(FIREBASE_JWK_URL)
        .send()
        .await?
        .error_for_status()?;
    let max_age = max_age(response.headers());
    Ok((response.json::<JwkSet>().await?, max_age))
}

#[derive(Debug)]
enum Lookup {
    Found(Box<Jwk>),
    Unknown,
    Refresh,
}

fn lookup(cache: Option<&CachedJwks>, kid: &str, now: Instant) -> Lookup {
    let Some(cache) = cache else {
        return Lookup::Refresh;
    };
    let jwk = cache.keys.find(kid);
    match jwk {
        Some(jwk) if now < cache.expires_at => Lookup::Found(Box::new(jwk.clone())),
        _ if now.saturating_duration_since(cache.fetched_at) < MIN_JWKS_REFRESH_INTERVAL => {
            jwk.map_or(Lookup::Unknown, |jwk| Lookup::Found(Box::new(jwk.clone())))
        }
        _ => Lookup::Refresh,
    }
}

/// The signing key for `kid`, refetching Google's keys when they expire or a new `kid` appears
/// (key rotation). Falls back to stale keys if Google is unreachable.
async fn find_jwk(kid: &str) -> anyhow::Result<Option<Jwk>> {
    let lock = CACHED_JWKS.get_or_init(|| RwLock::new(None));
    match lookup(lock.read().await.as_ref(), kid, Instant::now()) {
        Lookup::Found(jwk) => return Ok(Some(*jwk)),
        Lookup::Unknown => return Ok(None),
        Lookup::Refresh => {}
    }

    let mut cache = lock.write().await;
    // Another request may have refreshed the keys while this one waited for the lock.
    match lookup(cache.as_ref(), kid, Instant::now()) {
        Lookup::Found(jwk) => return Ok(Some(*jwk)),
        Lookup::Unknown => return Ok(None),
        Lookup::Refresh => {}
    }
    match fetch_jwks().await {
        Ok((keys, max_age)) => {
            let jwk = keys.find(kid).cloned();
            let now = Instant::now();
            *cache = Some(CachedJwks {
                keys,
                fetched_at: now,
                expires_at: now + max_age,
            });
            Ok(jwk)
        }
        Err(error) => match cache.as_ref().and_then(|cache| cache.keys.find(kid)) {
            Some(jwk) => {
                tracing::warn!("failed to refresh Firebase JWKs, using cached keys: {error:#}");
                Ok(Some(jwk.clone()))
            }
            None => Err(error),
        },
    }
}

/// Seed the JWK cache with a pre-built JwkSet. Used in tests to inject mock keys.
#[cfg(test)]
pub async fn seed_jwk_cache(jwks: JwkSet) {
    let lock = CACHED_JWKS.get_or_init(|| RwLock::new(None));
    let mut write = lock.write().await;
    let now = Instant::now();
    *write = Some(CachedJwks {
        keys: jwks,
        fetched_at: now,
        expires_at: now + MAX_JWKS_MAX_AGE,
    });
}

fn invalid_token() -> AppError {
    AppError::unauthorized("invalid or expired Firebase ID token")
}

/// Axum middleware that validates a Firebase ID token from the `Authorization: Bearer <token>`
/// header and inserts a [`FirebaseUser`] into request extensions.
///
/// Apply to routes with `route_layer(middleware::from_fn_with_state(state, verify_firebase_token))`.
pub async fn verify_firebase_token(
    State(state): State<AppStateDyn>,
    mut req: Request,
    next: Next,
) -> Result<Response, AppError> {
    let token = req
        .headers()
        .get("Authorization")
        .and_then(|h| h.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer "))
        .ok_or_else(|| {
            AppError::unauthorized("missing Authorization: Bearer <Firebase ID token>")
        })?;

    let header = decode_header(token).map_err(|_| invalid_token())?;
    let kid = header.kid.ok_or_else(invalid_token)?;

    let project_id = &state.firebase_project_id;

    let jwk = find_jwk(&kid)
        .await
        .map_err(|error| AppError::upstream("Firebase key service", error))?
        .ok_or_else(|| {
            tracing::warn!("no JWK found for kid={kid}");
            invalid_token()
        })?;

    let decoding_key = DecodingKey::from_jwk(&jwk).map_err(|_| invalid_token())?;

    let mut validation = Validation::new(jsonwebtoken::Algorithm::RS256);
    validation.set_audience(&[project_id.as_str()]);
    validation.set_issuer(&[format!("https://securetoken.google.com/{}", project_id)]);

    let token_data = decode::<FirebaseClaims>(token, &decoding_key, &validation).map_err(|e| {
        tracing::warn!("firebase token validation failed: {:?}", e.kind());
        invalid_token()
    })?;

    // Fills the `user_id` field of the `http_request` span from `startup::run`.
    tracing::Span::current().record("user_id", token_data.claims.sub.as_str());
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
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
        parts
            .extensions
            .get::<FirebaseUser>()
            .cloned()
            .ok_or_else(|| {
                AppError::unauthorized("missing Authorization: Bearer <Firebase ID token>")
            })
    }
}

// Auth is documented as a security requirement on each operation instead.
impl aide::OperationInput for FirebaseUser {}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::data::{database::MockDatabase, search::MockSearch};
    use axum::{Router, body::Body, http::StatusCode, middleware, routing::get};
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
            mail: crate::domain::mail_bridge::MailBridge::disabled(),
            response_cache: Default::default(),
            places: std::sync::Arc::new(crate::data::places::MockPlaces),
            spotify: std::sync::Arc::new(crate::data::spotify::MockSpotify),
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

    fn cached(fetched_ago: Duration, expires_in: Duration) -> (CachedJwks, Instant) {
        let now = Instant::now() + Duration::from_secs(48 * 60 * 60);
        let keys: JwkSet = serde_json::from_str(TEST_JWKS_JSON).unwrap();
        (
            CachedJwks {
                keys,
                fetched_at: now - fetched_ago,
                expires_at: now + expires_in,
            },
            now,
        )
    }

    #[test]
    fn uses_fresh_cached_keys() {
        let (cache, now) = cached(Duration::from_secs(600), Duration::from_secs(600));
        assert!(matches!(
            lookup(Some(&cache), TEST_KID, now),
            Lookup::Found(_)
        ));
    }

    #[test]
    fn refreshes_on_unknown_kid_after_rotation() {
        let (cache, now) = cached(Duration::from_secs(600), Duration::from_secs(600));
        assert!(matches!(
            lookup(Some(&cache), "rotated-kid", now),
            Lookup::Refresh
        ));
    }

    #[test]
    fn throttles_refreshes_for_unknown_kids() {
        let (cache, now) = cached(Duration::from_secs(5), Duration::from_secs(600));
        assert!(matches!(
            lookup(Some(&cache), "garbage", now),
            Lookup::Unknown
        ));
    }

    #[test]
    fn refreshes_expired_keys() {
        let (cache, now) = cached(Duration::from_secs(600), Duration::ZERO);
        assert!(matches!(
            lookup(Some(&cache), TEST_KID, now),
            Lookup::Refresh
        ));
        assert!(matches!(lookup(None, TEST_KID, now), Lookup::Refresh));
    }

    #[test]
    fn reads_max_age_from_cache_control() {
        let mut headers = HeaderMap::new();
        assert_eq!(max_age(&headers), DEFAULT_JWKS_MAX_AGE);
        headers.insert(
            CACHE_CONTROL,
            "public, max-age=19302, must-revalidate, no-transform"
                .parse()
                .unwrap(),
        );
        assert_eq!(max_age(&headers), Duration::from_secs(19302));
        headers.insert(CACHE_CONTROL, "max-age=999999999".parse().unwrap());
        assert_eq!(max_age(&headers), MAX_JWKS_MAX_AGE);
    }

    #[tokio::test]
    async fn auth_errors_are_json() {
        setup_jwk_cache().await;
        let resp = test_app()
            .oneshot(
                Request::builder()
                    .uri("/protected")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
        let body: serde_json::Value = serde_json::from_slice(
            &axum::body::to_bytes(resp.into_body(), usize::MAX)
                .await
                .unwrap(),
        )
        .unwrap();
        assert!(body["error"].as_str().unwrap().contains("Bearer"));
        assert!(body["error_id"].is_string());
    }
}
