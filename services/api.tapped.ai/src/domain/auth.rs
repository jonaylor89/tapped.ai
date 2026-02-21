use crate::state::AppStateDyn;
use axum::{
    extract::{Request, State},
    http::StatusCode,
    middleware::Next,
    response::Response,
};

pub async fn verify_api_token(
    State(state): State<AppStateDyn>,
    req: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    let auth_header = req
        .headers()
        .get("tapped-api-key")
        .and_then(|header| header.to_str().ok());

    match auth_header {
        Some(api_key) => {
            let user_id = state
                .database
                .get_user_from_api_key(api_key)
                .await
                .map_err(|err| {
                    tracing::error!("error verifying API key: {:?}", err);
                    StatusCode::UNAUTHORIZED
                })?;

            tracing::info!("User ID: {:?}", user_id);

            let res = next.run(req).await;
            Ok(res)
        }
        None => Err(StatusCode::UNAUTHORIZED),
    }
}
