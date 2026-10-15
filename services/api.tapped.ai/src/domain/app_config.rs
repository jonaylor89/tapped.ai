//! Launch gates the iOS app reads before sign-in (formerly Firebase Remote Config).
use axum::{
    Json,
    extract::State,
    http::{HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
};
use serde::Serialize;
use utoipa::ToSchema;

use crate::{errors::AppError, state::AppStateDyn};

/// Short so a maintenance flip reaches every client within a minute, edge cache included.
const CACHE_CONTROL: &str = "public, max-age=30, s-maxage=30";

#[derive(Debug, Serialize, ToSchema, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct AppConfig {
    /// Blocks the app behind the maintenance screen.
    pub down_for_maintenance: bool,
    pub booking_fee: f64,
    /// Semver; older iOS builds must update. Empty disables the gate.
    pub ios_minimum_app_version: String,
    /// Semver; older iOS builds see a dismissible update prompt. Empty disables it.
    pub ios_latest_app_version: String,
    pub premium_waitlist_enabled: bool,
}

#[utoipa::path(
    get,
    path = "/public/app-config",
    tag = "public",
    summary = "Client launch configuration",
    description = "Maintenance and app-version gates, read by the iOS app before sign-in.",
    responses((status = 200, description = "Success", body = AppConfig))
)]
pub async fn get_app_config(State(state): State<AppStateDyn>) -> Response {
    let Some(pool) = state.postgres.as_ref() else {
        return AppError::new("database unavailable")
            .with_status(StatusCode::SERVICE_UNAVAILABLE)
            .into_response();
    };
    let config = sqlx::query_as::<_, AppConfig>(
        "SELECT down_for_maintenance,booking_fee,ios_minimum_app_version,ios_latest_app_version,premium_waitlist_enabled FROM app_config",
    )
    .fetch_one(pool)
    .await;
    match config {
        Ok(config) => {
            let mut response = Json(config).into_response();
            response.headers_mut().insert(
                header::CACHE_CONTROL,
                HeaderValue::from_static(CACHE_CONTROL),
            );
            response
        }
        Err(_) => AppError::from_status(StatusCode::SERVICE_UNAVAILABLE).into_response(),
    }
}
