use aide::axum::ApiRouter;
use axum::{middleware, routing::get};

use crate::{
    domain::{
        auth::verify_api_token,
        controller::{get_location, get_performer, get_performer_username, search_performers},
    },
    state::AppStateDyn,
};

pub fn v1_routes(state: AppStateDyn) -> ApiRouter {
    let router = ApiRouter::new()
        .route("/performer/search", get(search_performers))
        .route("/performer/:id", get(get_performer))
        .route("/performer/username/:username", get(get_performer_username))
        .route("/location/:latlng", get(get_location))
        .route_layer(middleware::from_fn_with_state(
            state.clone(),
            verify_api_token,
        ))
        .with_state(state);

    router
}
