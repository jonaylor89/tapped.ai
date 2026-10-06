use crate::{
    domain::models::api_key::is_well_formed_api_key, errors::AppError, state::AppStateDyn,
};
use axum::{
    extract::{Request, State},
    http::StatusCode,
    middleware::Next,
    response::Response,
};

pub const API_KEY_HEADER: &str = "tapped-api-key";

/// The owner of the `tapped-api-key` on a `/v1` request, inserted by [`verify_api_token`].
#[derive(Debug, Clone)]
pub struct ApiKeyUser {
    pub user_id: String,
}

pub async fn verify_api_token(
    State(state): State<AppStateDyn>,
    mut req: Request,
    next: Next,
) -> Result<Response, AppError> {
    let api_key = req
        .headers()
        .get(API_KEY_HEADER)
        .and_then(|header| header.to_str().ok())
        .ok_or_else(|| AppError::unauthorized("missing tapped-api-key header"))?;
    if !is_well_formed_api_key(api_key) {
        return Err(AppError::unauthorized("invalid API key"));
    }

    let user_id = state
        .database
        .get_user_from_api_key(api_key)
        .await
        .map_err(|error| {
            AppError::internal("failed to verify API key", error)
                .with_status(StatusCode::SERVICE_UNAVAILABLE)
        })?
        .ok_or_else(|| AppError::unauthorized("invalid API key"))?;

    tracing::Span::current().record("user_id", user_id.as_str());
    req.extensions_mut().insert(ApiKeyUser { user_id });

    Ok(next.run(req).await)
}
