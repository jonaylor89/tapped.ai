use std::sync::Arc;

use crate::{extractors::Json, state::AppStateDyn};
use aide::{
    axum::{
        routing::{get, get_with},
        ApiRouter, IntoApiResponse,
    },
    openapi::OpenApi,
    redoc::Redoc,
    scalar::Scalar,
};
use axum::{response::IntoResponse, Extension};

pub fn docs_routes(state: AppStateDyn) -> ApiRouter {
    // We infer the return types for these routes
    // as an example.
    //
    // As a result, the `serve_redoc` route will
    // have the `text/html` content-type correctly set
    // with a 200 status.
    aide::gen::infer_responses(true);

    let router: ApiRouter = ApiRouter::new()
        .api_route_with(
            "/",
            get_with(
                Scalar::new("/swagger/json")
                    .with_title("Tapped API docs")
                    .axum_handler(),
                |op| op.description("This documentation page."),
            ),
            |p| p.security_requirement("ApiKey"),
        )
        .api_route_with(
            "/redoc",
            get_with(
                Redoc::new("/swagger/json")
                    .with_title("Tapped API docs")
                    .axum_handler(),
                |op| op.description("This documentation page."),
            ),
            |p| p.security_requirement("ApiKey"),
        )
        .route("/private/api.json", get(serve_docs))
        .with_state(state);

    // Afterwards we disable response inference because
    // it might be incorrect for other routes.
    aide::gen::infer_responses(false);

    router
}

async fn serve_docs(Extension(api): Extension<Arc<OpenApi>>) -> impl IntoApiResponse {
    Json(api).into_response()
}
