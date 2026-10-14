//! The OpenAPI document: shared metadata here, operations from each handler's
//! `#[utoipa::path]`, collected by the `OpenApiRouter`s in `startup` and `routes`.

use std::sync::Arc;

use axum::{
    Extension, Json, Router,
    response::{Html, IntoResponse},
    routing::get,
};
use utoipa::{
    Modify, OpenApi, ToSchema,
    openapi::{
        self, Ref, RefOr, Response, ResponseBuilder,
        content::ContentBuilder,
        security::{ApiKey, ApiKeyValue, HttpAuthScheme, HttpBuilder, SecurityScheme},
    },
};
use utoipa_redoc::Redoc;

use crate::{errors::AppError, state::AppStateDyn};

#[derive(OpenApi)]
#[openapi(
    info(
        title = "Tapped API Docs",
        description = "The leading API for live music data including performers, venues, and events. High quality live music data and aggregates.\n\nErrors share one shape: `{ \"error\", \"error_id\", \"error_details\"? }`. Quote `error_id` when reporting a problem; it is logged server-side."
    ),
    servers((url = "https://api.tapped.ai")),
    tags(
        (name = "v1", description = "Partner API, authenticated with a `tapped-api-key`."),
        (name = "app", description = "Used by the Tapped apps, authenticated with a Firebase ID token."),
        (name = "public", description = "Unauthenticated, rate limited per IP."),
        (name = "meta", description = "Version, liveness and readiness."),
    ),
    components(schemas(AppError))
)]
pub struct ApiDoc;

/// Security schemes, and the error response every operation can return. Applied after the
/// routers have added their operations (a `#[openapi(modifiers)]` would run before).
pub struct SharedDocs;

impl Modify for SharedDocs {
    fn modify(&self, api: &mut openapi::OpenApi) {
        let components = api.components.get_or_insert_with(Default::default);
        components.add_security_scheme(
            "ApiKey",
            SecurityScheme::ApiKey(ApiKey::Header(ApiKeyValue::with_description(
                "tapped-api-key",
                "your API Key",
            ))),
        );
        components.add_security_scheme(
            "FirebaseAuth",
            SecurityScheme::Http(
                HttpBuilder::new()
                    .scheme(HttpAuthScheme::Bearer)
                    .bearer_format("JWT")
                    .description(Some("A Firebase Auth ID token for the tapped project."))
                    .build(),
            ),
        );

        let mut example = AppError::new("some error happened");
        // Fixed so the generated spec is reproducible.
        example.error_id = uuid::Uuid::nil();
        let error: RefOr<Response> = ResponseBuilder::new()
            .description(
                "The error body every route returns: `{ \"error\", \"error_id\", \"error_details\"? }`.",
            )
            .content(
                "application/json",
                ContentBuilder::new()
                    .schema(Some(Ref::from_schema_name(AppError::name())))
                    .example(serde_json::to_value(&example).ok())
                    .build(),
            )
            .build()
            .into();
        for item in api.paths.paths.values_mut() {
            for operation in [
                &mut item.get,
                &mut item.post,
                &mut item.put,
                &mut item.delete,
                &mut item.patch,
            ]
            .into_iter()
            .flatten()
            {
                operation
                    .responses
                    .responses
                    .entry("default".into())
                    .or_insert_with(|| error.clone());
            }
        }
    }
}

/// `/docs` (Redoc) and the raw document.
pub fn docs_routes(api: &openapi::OpenApi) -> Router<AppStateDyn> {
    let page = Html(Redoc::new(api.clone()).to_html());
    let page = move || {
        let page = page.clone();
        async move { page }
    };
    Router::new()
        .route("/docs", get(page.clone()))
        .route("/docs/", get(page.clone()))
        .route("/docs/redoc", get(page))
        .route("/docs/private/api.json", get(serve_docs))
}

pub async fn serve_docs(Extension(api): Extension<Arc<openapi::OpenApi>>) -> impl IntoResponse {
    Json(api)
}
