use aide::{
    axum::{ApiRouter, routing::get_with},
    transform::TransformOperation,
};
use axum::{Json, middleware};

use crate::{
    domain::{
        auth::verify_api_token,
        controller::{
            LocationResponse, get_location, get_performer, get_performer_username,
            search_performers,
        },
        models::user::GuardedPerformer,
    },
    rate_limit::RateLimits,
    state::AppStateDyn,
};

fn v1_op<'a>(op: TransformOperation<'a>, summary: &str) -> TransformOperation<'a> {
    op.tag("v1").summary(summary).security_requirement("ApiKey")
}

pub fn v1_routes(state: AppStateDyn, rate_limits: &RateLimits) -> ApiRouter {
    ApiRouter::new()
        .api_route(
            "/performer/search",
            get_with(search_performers, |op| {
                v1_op(op, "Search performers")
                    .description("Full-text search over performer profiles. Cached for 60s.")
                    .response::<200, Json<Vec<GuardedPerformer>>>()
            }),
        )
        .api_route(
            "/performer/:id",
            get_with(get_performer, |op| {
                v1_op(op, "Get a performer by ID").response::<200, Json<GuardedPerformer>>()
            }),
        )
        .api_route(
            "/performer/username/:username",
            get_with(get_performer_username, |op| {
                v1_op(op, "Get a performer by username").response::<200, Json<GuardedPerformer>>()
            }),
        )
        .api_route(
            "/location/:latlng",
            get_with(get_location, |op| {
                v1_op(op, "Venues, top performers and genre mix near a coordinate")
                    .description(
                        "Searches a 100km radius. `genres` maps genre to its share of venues.",
                    )
                    .response::<200, Json<LocationResponse>>()
            }),
        )
        // Outermost first: per-IP limit, then the key check, then the per-key limit.
        .route_layer(rate_limits.per_api_key_layer())
        .route_layer(middleware::from_fn_with_state(
            state.clone(),
            verify_api_token,
        ))
        .route_layer(rate_limits.per_ip_layer())
        .with_state(state)
}
