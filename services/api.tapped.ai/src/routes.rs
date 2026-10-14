use axum::middleware;
use utoipa_axum::{router::OpenApiRouter, routes};

use crate::{
    domain::{auth::verify_api_token, controller},
    rate_limit::RateLimits,
    state::AppStateDyn,
};

pub fn v1_routes(state: AppStateDyn, rate_limits: &RateLimits) -> OpenApiRouter<AppStateDyn> {
    OpenApiRouter::new()
        .routes(routes!(controller::search_performers))
        .routes(routes!(controller::get_performer))
        .routes(routes!(controller::get_performer_username))
        .routes(routes!(controller::get_location))
        // Outermost first: per-IP limit, then the key check, then the per-key limit.
        .route_layer(rate_limits.per_api_key_layer())
        .route_layer(middleware::from_fn_with_state(state, verify_api_token))
        .route_layer(rate_limits.per_ip_layer())
}
