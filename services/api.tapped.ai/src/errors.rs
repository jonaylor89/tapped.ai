use std::any::Any;

use aide::OperationOutput;
use axum::{
    http::{StatusCode, header},
    response::{IntoResponse, Response},
};
use schemars::JsonSchema;
use serde::Serialize;
use serde_json::Value;
use uuid::Uuid;

/// The error body every route returns: `{ "error", "error_id", "error_details"? }`.
#[derive(Debug, Serialize, JsonSchema)]
pub struct AppError {
    /// An error message.
    pub error: String,
    /// A unique error ID, also written to the server logs.
    pub error_id: Uuid,
    #[serde(skip)]
    pub status: StatusCode,
    /// Optional Additional error details.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error_details: Option<Value>,
}

impl AppError {
    pub fn new(error: impl Into<String>) -> Self {
        Self {
            error: error.into(),
            error_id: Uuid::new_v4(),
            status: StatusCode::BAD_REQUEST,
            error_details: None,
        }
    }

    pub fn with_status(mut self, status: StatusCode) -> Self {
        self.status = status;
        self
    }

    pub fn with_details(mut self, details: Value) -> Self {
        self.error_details = Some(details);
        self
    }

    pub fn bad_request(error: impl Into<String>) -> Self {
        Self::new(error)
    }

    pub fn unauthorized(error: impl Into<String>) -> Self {
        Self::new(error).with_status(StatusCode::UNAUTHORIZED)
    }

    pub fn not_found(error: impl Into<String>) -> Self {
        Self::new(error).with_status(StatusCode::NOT_FOUND)
    }

    pub fn unprocessable(error: impl Into<String>) -> Self {
        Self::new(error).with_status(StatusCode::UNPROCESSABLE_ENTITY)
    }

    /// A 500 whose cause is logged with the `error_id`, never returned to the client.
    pub fn internal(context: &str, cause: impl std::fmt::Debug) -> Self {
        let error =
            Self::new("internal server error").with_status(StatusCode::INTERNAL_SERVER_ERROR);
        tracing::error!(error_id = %error.error_id, "{context}: {cause:?}");
        error
    }

    /// A 502 for a failed upstream (Google, Spotify, Stream, ...). The cause is only logged.
    pub fn upstream(service: &str, cause: impl std::fmt::Debug) -> Self {
        let error = Self::new(format!("{service} is unavailable, try again later"))
            .with_status(StatusCode::BAD_GATEWAY);
        tracing::error!(error_id = %error.error_id, "{service} request failed: {cause:?}");
        error
    }

    pub fn from_status(status: StatusCode) -> Self {
        Self::new(
            status
                .canonical_reason()
                .unwrap_or("request failed")
                .to_lowercase(),
        )
        .with_status(status)
    }
}

impl From<StatusCode> for AppError {
    fn from(status: StatusCode) -> Self {
        Self::from_status(status)
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let status = self.status;
        let mut res = axum::Json(self).into_response();
        *res.status_mut() = status;
        res
    }
}

// Documented once through `default_response_with` in `startup::api_docs`.
impl OperationOutput for AppError {
    type Inner = Self;
}

const MAX_PLAIN_ERROR_BODY: usize = 1_024;

/// Rewrites non-JSON 4xx/5xx responses (extractor rejections, rate limits, timeouts, unknown
/// routes, bare `StatusCode`s) into an [`AppError`] body, keeping the status and headers.
pub async fn json_error_bodies(response: Response) -> Response {
    let status = response.status();
    if !(status.is_client_error() || status.is_server_error()) {
        return response;
    }
    let is_json = response
        .headers()
        .get(header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| value.starts_with("application/json"));
    if is_json {
        return response;
    }

    let (parts, body) = response.into_parts();
    let mut error = AppError::from_status(status);
    if let Ok(bytes) = axum::body::to_bytes(body, MAX_PLAIN_ERROR_BODY).await {
        let message = String::from_utf8_lossy(&bytes).trim().to_owned();
        if !message.is_empty() {
            error.error = message;
        }
    }
    if status.is_server_error() {
        tracing::warn!(error_id = %error.error_id, %status, "{}", error.error);
    }

    let mut response = error.into_response();
    for (name, value) in &parts.headers {
        if name != header::CONTENT_TYPE && name != header::CONTENT_LENGTH {
            response.headers_mut().append(name.clone(), value.clone());
        }
    }
    response
}

/// Used with `CatchPanicLayer::custom` so a panicking handler returns a JSON 500.
pub fn panic_response(panic: Box<dyn Any + Send + 'static>) -> Response {
    let detail = panic
        .downcast_ref::<String>()
        .map(String::as_str)
        .or_else(|| panic.downcast_ref::<&str>().copied())
        .unwrap_or("unknown panic");
    let error =
        AppError::new("internal server error").with_status(StatusCode::INTERNAL_SERVER_ERROR);
    tracing::error!(error_id = %error.error_id, "request handler panicked: {detail}");
    error.into_response()
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::{Body, to_bytes};

    async fn body_json(response: Response) -> Value {
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap()
    }

    #[tokio::test]
    async fn rewrites_plain_error_bodies_as_json() {
        let response = Response::builder()
            .status(StatusCode::TOO_MANY_REQUESTS)
            .header(header::RETRY_AFTER, "3")
            .header(header::CONTENT_TYPE, "text/plain")
            .body(Body::from("Too Many Requests! Wait for 3s"))
            .unwrap();
        let response = json_error_bodies(response).await;
        assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
        assert_eq!(response.headers()[header::RETRY_AFTER], "3");
        let body = body_json(response).await;
        assert_eq!(body["error"], "Too Many Requests! Wait for 3s");
        assert!(body["error_id"].is_string());
    }

    #[tokio::test]
    async fn fills_in_empty_error_bodies() {
        let response = json_error_bodies(StatusCode::NOT_FOUND.into_response()).await;
        assert_eq!(body_json(response).await["error"], "not found");
    }

    #[tokio::test]
    async fn leaves_success_and_json_errors_alone() {
        let ok = json_error_bodies("hello".into_response()).await;
        assert_eq!(to_bytes(ok.into_body(), usize::MAX).await.unwrap(), "hello");

        let error =
            json_error_bodies(AppError::not_found("no such performer").into_response()).await;
        assert_eq!(body_json(error).await["error"], "no such performer");
    }

    #[tokio::test]
    async fn panics_become_json_500s() {
        let response = panic_response(Box::new("boom"));
        assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
        assert_eq!(body_json(response).await["error"], "internal server error");
    }
}
