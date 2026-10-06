//! Request correlation. Every request gets an `X-Request-Id`: the caller's when it is a sane
//! token (the iOS app sends a UUID per request), otherwise a new UUID. It is echoed on the
//! response and recorded on the `http_request` span, so every log line for a request carries it.

use axum::{
    extract::Request,
    http::{HeaderName, HeaderValue},
    middleware::Next,
    response::Response,
};
use uuid::Uuid;

pub const REQUEST_ID_HEADER: HeaderName = HeaderName::from_static("x-request-id");

const MAX_REQUEST_ID_LEN: usize = 128;

/// The request's correlation ID, available as a request extension.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RequestId(pub String);

fn is_valid_request_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= MAX_REQUEST_ID_LEN
        && value
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | ':'))
}

pub async fn propagate_request_id(mut request: Request, next: Next) -> Response {
    let id = request
        .headers()
        .get(&REQUEST_ID_HEADER)
        .and_then(|value| value.to_str().ok())
        .filter(|value| is_valid_request_id(value))
        .map(str::to_owned)
        .unwrap_or_else(|| Uuid::new_v4().to_string());
    let header = HeaderValue::from_str(&id).expect("request IDs are visible ASCII");

    request
        .headers_mut()
        .insert(REQUEST_ID_HEADER, header.clone());
    request.extensions_mut().insert(RequestId(id));

    let mut response = next.run(request).await;
    response.headers_mut().insert(REQUEST_ID_HEADER, header);
    response
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_uuids_and_simple_tokens() {
        assert!(is_valid_request_id("4f1c2b8e-9a3d-4e5f-8a6b-7c8d9e0f1a2b"));
        assert!(is_valid_request_id("cf-ray:8a1b2c3d4e5f"));
    }

    #[test]
    fn rejects_empty_long_and_unsafe_values() {
        assert!(!is_valid_request_id(""));
        assert!(!is_valid_request_id(&"a".repeat(MAX_REQUEST_ID_LEN + 1)));
        assert!(!is_valid_request_id("id with spaces"));
        assert!(!is_valid_request_id("id\"},{\"injected\":1"));
    }
}
