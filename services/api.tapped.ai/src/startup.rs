use crate::{
    data::{database::Firestore, search::Typesense},
    docs::docs_routes,
    errors::AppError,
    routes::v1_routes,
    state::AppStateDyn,
};
use aide::{
    axum::ApiRouter,
    openapi::{OpenApi, Tag},
    transform::TransformOpenApi,
};
use axum::Router;
use axum::serve::Serve;
use axum::{
    Extension, Json,
    extract::MatchedPath,
    http::{Request, StatusCode},
    response::Html,
    routing::get,
};
use axum_swagger_ui::swagger_ui;
use color_eyre::eyre::Result;
use color_eyre::eyre::WrapErr;
use firestore::{FirestoreDb, FirestoreDbOptions};
use serde_json::{Value, json};
use std::sync::Arc;
use tokio::net::TcpListener;
use tower_http::trace::TraceLayer;
use tracing::info_span;
use uuid::Uuid;

pub struct Application {
    port: u16,
    server: Serve<Router, Router>,
}

const CREDENTIALS_PATH: &str = "./credentials.json";

impl Application {
    pub async fn build(port: u16, project_id: String) -> Result<Self> {
        let listener = TcpListener::bind(format!("0.0.0.0:{}", port)).await.wrap_err(
            "Failed to bind to the port. Make sure you have the correct permissions to bind to the port",
        )?;

        let firestore_instance = if std::path::Path::new(CREDENTIALS_PATH).exists() {
            FirestoreDb::with_options_service_account_key_file(
                FirestoreDbOptions::new(project_id),
                CREDENTIALS_PATH.into(),
            )
            .await?
        } else {
            FirestoreDb::new(project_id).await?
        };

        let state = AppStateDyn {
            database: Arc::new(Firestore::new(firestore_instance)),
            search: Arc::new(Typesense::from_env()),
        };

        let server = run(listener, state).await?;
        Ok(Self { port, server })
    }

    pub async fn build_with_state(port: u16, state: AppStateDyn) -> Result<Self> {
        let listener = TcpListener::bind(format!("0.0.0.0:{}", port)).await.wrap_err(
            "Failed to bind to the port. Make sure you have the correct permissions to bind to the port",
        )?;
        let port = listener.local_addr()?.port();

        let server = run(listener, state).await?;
        Ok(Self { port, server })
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    pub async fn run_until_stopped(self) -> Result<(), std::io::Error> {
        self.server.await
    }
}

async fn run(listener: TcpListener, state: AppStateDyn) -> Result<Serve<Router, Router>> {
    aide::r#gen::on_error(|error| {
        tracing::error!("{error}");
    });

    aide::r#gen::extract_schemas(true);
    let mut api = OpenApi::default();
    let app = ApiRouter::new()
        .route(
            "/swagger",
            get(|| async { Html(swagger_ui("/swagger/json")) }),
        )
        .route(
            "/swagger/json",
            get(|| async { include_str!("openapi.json") }),
        )
        .route("/", get(root))
        .route("/version", get(version))
        .route("/health", get(health))
        .nest_api_service("/v1", v1_routes(state.clone()))
        .nest_api_service("/docs", docs_routes(state.clone()))
        .finish_api_with(&mut api, api_docs)
        .layer(Extension(Arc::new(api))) // Arc is very important here or you will face massive memory and performance issues
        .layer(
            TraceLayer::new_for_http().make_span_with(|request: &Request<_>| {
                // Log the matched route's path (with placeholders not filled in).
                // Use request.uri() or OriginalUri if you want the real path.
                let matched_path = request
                    .extensions()
                    .get::<MatchedPath>()
                    .map(MatchedPath::as_str);

                info_span!(
                    "http_request",
                    method = ?request.method(),
                    matched_path,
                    some_other_field = tracing::field::Empty,
                )
            }),
        )
        .with_state(state);

    tracing::debug!("listening on {}", listener.local_addr().unwrap());
    let server = axum::serve(listener, app);

    Ok(server)
}

async fn root() -> Json<Value> {
    json!({ "status": "ok" }).into()
}

async fn version() -> Json<Value> {
    json!({ "version": "0.1.0" }).into()
}

async fn health() -> Json<Value> {
    json!({ "status": "ok" }).into()
}

fn api_docs(api: TransformOpenApi) -> TransformOpenApi {
    api.title("Tapped API Docs")
        .summary("the leading API for live music data including performers, venues, and events. High quality live music data and aggregates")
        .tag(Tag {
            name: "tapped api".into(),
            description: Some("Tapped Ai | Live Music Data Analytics".into()),
            ..Default::default()
        })
        .security_scheme(
            "ApiKey",
            aide::openapi::SecurityScheme::ApiKey {
                location: aide::openapi::ApiKeyLocation::Header,
                name: "tapped-api-key".into(),
                description: Some("your API Key".into()),
                extensions: Default::default(),
            },
        )
        .default_response_with::<Json<AppError>, _>(|res| {
            res.example(AppError {
                error: "some error happened".to_string(),
                error_details: None,
                error_id: Uuid::nil(),
                // This is not visible.
                status: StatusCode::IM_A_TEAPOT,
            })
        })
}
