//! Per-client rate limits. Requests arrive through Cloudflare Tunnel, so the client is identified
//! by `CF-Connecting-IP` (set by Cloudflare) and, on `/v1`, by the `tapped-api-key` header.

use std::{sync::Arc, time::Duration};

use axum::{
    body::Body,
    http::{HeaderMap, HeaderValue, Request, Response, StatusCode, header::RETRY_AFTER},
    response::IntoResponse,
};
use governor::middleware::StateInformationMiddleware;
use tower_governor::{
    GovernorError, GovernorLayer,
    governor::{GovernorConfig, GovernorConfigBuilder},
    key_extractor::KeyExtractor,
};

use crate::{
    domain::{auth::API_KEY_HEADER, models::api_key::hash_api_key},
    errors::AppError,
};

/// Generous enough for a phone behind carrier NAT opening the app (bursty) while stopping a
/// single client from hammering Firestore, Typesense or Google.
const PER_IP_REPLENISH: Duration = Duration::from_millis(100);
const PER_IP_BURST: u32 = 100;
/// API-key clients (including MCP tools that loop) get a steady 5 requests/s per key.
const PER_KEY_REPLENISH: Duration = Duration::from_millis(200);
const PER_KEY_BURST: u32 = 60;

pub type Limiter<K> = Arc<GovernorConfig<K, StateInformationMiddleware>>;

#[derive(Clone)]
pub struct RateLimits {
    pub per_ip: Limiter<ClientIp>,
    pub per_api_key: Limiter<ApiKeyOrIp>,
}

impl Default for RateLimits {
    fn default() -> Self {
        Self {
            per_ip: limiter(ClientIp, PER_IP_REPLENISH, PER_IP_BURST),
            per_api_key: limiter(ApiKeyOrIp, PER_KEY_REPLENISH, PER_KEY_BURST),
        }
    }
}

impl RateLimits {
    pub fn per_ip_layer(&self) -> GovernorLayer<ClientIp, StateInformationMiddleware> {
        GovernorLayer {
            config: self.per_ip.clone(),
        }
    }

    pub fn per_api_key_layer(&self) -> GovernorLayer<ApiKeyOrIp, StateInformationMiddleware> {
        GovernorLayer {
            config: self.per_api_key.clone(),
        }
    }

    /// Drops idle buckets so the limiter's memory doesn't grow with every client ever seen.
    pub fn spawn_cleanup(&self) {
        let limits = self.clone();
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(60));
            loop {
                interval.tick().await;
                limits.per_ip.limiter().retain_recent();
                limits.per_api_key.limiter().retain_recent();
            }
        });
    }
}

fn limiter<K: KeyExtractor>(key: K, replenish: Duration, burst: u32) -> Limiter<K> {
    Arc::new(
        GovernorConfigBuilder::default()
            .key_extractor(key)
            .use_headers()
            .period(replenish)
            .burst_size(burst)
            .error_handler(rate_limited)
            .finish()
            .expect("rate limit period and burst are non-zero"),
    )
}

fn rate_limited(error: GovernorError) -> Response<Body> {
    match error {
        GovernorError::TooManyRequests { wait_time, headers } => {
            let mut response = AppError::new(format!("rate limit exceeded, retry in {wait_time}s"))
                .with_status(StatusCode::TOO_MANY_REQUESTS)
                .into_response();
            if let Some(headers) = headers {
                response.headers_mut().extend(headers);
            }
            response
                .headers_mut()
                .insert(RETRY_AFTER, HeaderValue::from(wait_time));
            response
        }
        other => AppError::internal("rate limiter failed", other).into_response(),
    }
}

pub fn client_ip(headers: &HeaderMap) -> Option<String> {
    let header = |name: &str| {
        headers
            .get(name)
            .and_then(|value| value.to_str().ok())
            .map(str::trim)
            .filter(|value| !value.is_empty())
    };
    header("cf-connecting-ip")
        .or_else(|| header("x-real-ip"))
        .or_else(|| header("x-forwarded-for")?.split(',').next().map(str::trim))
        .map(str::to_owned)
}

#[derive(Debug, Clone, Copy)]
pub struct ClientIp;

impl KeyExtractor for ClientIp {
    type Key = String;

    fn extract<T>(&self, req: &Request<T>) -> Result<Self::Key, GovernorError> {
        Ok(client_ip(req.headers()).unwrap_or_else(|| "unknown".into()))
    }
}

#[derive(Debug, Clone, Copy)]
pub struct ApiKeyOrIp;

impl KeyExtractor for ApiKeyOrIp {
    type Key = String;

    fn extract<T>(&self, req: &Request<T>) -> Result<Self::Key, GovernorError> {
        // Hashed so raw keys aren't held in the limiter's memory.
        Ok(
            match req
                .headers()
                .get(API_KEY_HEADER)
                .and_then(|value| value.to_str().ok())
            {
                Some(key) => format!("key:{}", hash_api_key(key)),
                None => format!("ip:{}", ClientIp.extract(req)?),
            },
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prefers_the_cloudflare_client_ip() {
        let mut headers = HeaderMap::new();
        assert_eq!(client_ip(&headers), None);
        headers.insert("x-forwarded-for", "203.0.113.9, 10.0.0.1".parse().unwrap());
        assert_eq!(client_ip(&headers).as_deref(), Some("203.0.113.9"));
        headers.insert("cf-connecting-ip", "198.51.100.7".parse().unwrap());
        assert_eq!(client_ip(&headers).as_deref(), Some("198.51.100.7"));
    }

    #[test]
    fn keys_api_clients_by_hashed_key() {
        let req = Request::builder()
            .header(API_KEY_HEADER, "test-key")
            .body(())
            .unwrap();
        let key = ApiKeyOrIp.extract(&req).unwrap();
        assert_eq!(key, format!("key:{}", hash_api_key("test-key")));
        assert!(!key.contains("test-key"));
    }
}
