use crate::{
    data::{database::Firestore, places::GooglePlaces, search::Typesense, spotify::SpotifyHttp},
    docs::docs_routes,
    domain::{
        app_functions::{notify_venue_of_interested_opportunities, stream_user_token},
        mail_bridge::{
            MailBridge, SqliteMailStore, StreamHttpGateway, backfill_email_message,
            backfill_email_thread, create_email_thread, enqueue_service_email, inbound_email,
            postmark_inbound_email, stream_before_message,
        },
        mail_composer::OpenAiEmailComposer,
        places::{autocomplete_places, get_place, get_place_photo, reverse_geocode},
        public_docs::{get_public_opportunity, get_public_user_by_username},
        spotify::{get_spotify_artist, get_spotify_artist_top_tracks},
    },
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
    routing::{get, post},
};
use axum_swagger_ui::swagger_ui;
use color_eyre::eyre::Result;
use color_eyre::eyre::WrapErr;
use firestore::{FirestoreDb, FirestoreDbOptions};
use serde_json::{Value, json};
use std::sync::Arc;
use tokio::net::TcpListener;
use tower_http::{
    cors::{Any, CorsLayer},
    trace::TraceLayer,
};
use tracing::info_span;
use uuid::Uuid;

pub struct Application {
    port: u16,
    server: Serve<Router, Router>,
}

const DEFAULT_CREDENTIALS_PATH: &str = "./credentials.json";

impl Application {
    pub async fn build(port: u16, project_id: String) -> Result<Self> {
        let listener = TcpListener::bind(format!("0.0.0.0:{}", port)).await.wrap_err(
            "Failed to bind to the port. Make sure you have the correct permissions to bind to the port",
        )?;

        let credentials_path = std::env::var("GOOGLE_APPLICATION_CREDENTIALS")
            .unwrap_or_else(|_| DEFAULT_CREDENTIALS_PATH.into());
        let firestore_instance = if std::path::Path::new(&credentials_path).exists() {
            FirestoreDb::with_options_service_account_key_file(
                FirestoreDbOptions::new(project_id.clone()),
                credentials_path.into(),
            )
            .await?
        } else {
            FirestoreDb::new(project_id.clone()).await?
        };

        let mail_store_path =
            std::env::var("MAIL_STORE_PATH").unwrap_or_else(|_| "tapped-mail.sqlite3".into());
        let stream_secret = std::env::var("STREAM_SECRET").wrap_err("STREAM_SECRET is required")?;
        let stream_key = std::env::var("STREAM_KEY").wrap_err("STREAM_KEY is required")?;
        let mail = MailBridge {
            store: Arc::new(
                SqliteMailStore::open(&mail_store_path)
                    .map_err(|error| color_eyre::eyre::eyre!(error.to_string()))?,
            ),
            stream: Arc::new(
                StreamHttpGateway::new(stream_key, &stream_secret)
                    .map_err(|error| color_eyre::eyre::eyre!(error.to_string()))?,
            ),
            stream_webhook_secret: stream_secret,
            ingress_secret: std::env::var("MAIL_INGRESS_SECRET")
                .wrap_err("MAIL_INGRESS_SECRET is required")?,
            service_secret: std::env::var("MAIL_API_SECRET")
                .wrap_err("MAIL_API_SECRET is required")?,
            booking_domain: std::env::var("BOOKING_EMAIL_DOMAIN")
                .unwrap_or_else(|_| "booking.tapped.ai".into()),
            composer: Arc::new(OpenAiEmailComposer::new(
                std::env::var("OPENAI_API_KEY")
                    .or_else(|_| std::env::var("OPEN_AI_KEY"))
                    .wrap_err("OPENAI_API_KEY (or legacy OPEN_AI_KEY) is required")?,
                std::env::var("OPENAI_MODEL").unwrap_or_else(|_| "gpt-4.1-mini".into()),
            )),
            founder_cc: std::env::var("VENUE_CONTACT_FOUNDER_CC")
                .unwrap_or_else(|_| "johannes@tapped.ai,ilias@tapped.ai".into())
                .split(',')
                .map(str::trim)
                .filter(|address| !address.is_empty())
                .map(str::to_owned)
                .collect(),
            slack_webhook_url: std::env::var("SLACK_WEBHOOK_URL").ok(),
        };
        let google_places_api_key = std::env::var("GOOGLE_PLACES_API_KEY").unwrap_or_default();
        if google_places_api_key.is_empty() {
            tracing::warn!("GOOGLE_PLACES_API_KEY is not set; /app/v1/places will return 502");
        }
        let spotify_client_id = std::env::var("SPOTIFY_CLIENT_ID").unwrap_or_default();
        let spotify_client_secret = std::env::var("SPOTIFY_CLIENT_SECRET").unwrap_or_default();
        if spotify_client_id.is_empty() || spotify_client_secret.is_empty() {
            tracing::warn!("SPOTIFY_CLIENT_ID/SECRET are not set; /app/v1/spotify will return 502");
        }
        let state = AppStateDyn {
            database: Arc::new(Firestore::new(firestore_instance)),
            search: Arc::new(Typesense::from_env()),
            firebase_project_id: project_id,
            mail,
            response_cache: Default::default(),
            places: Arc::new(GooglePlaces::new(google_places_api_key)),
            spotify: Arc::new(SpotifyHttp::new(spotify_client_id, spotify_client_secret)),
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
        .route(
            "/webhooks/stream/before-message",
            axum::routing::post(stream_before_message),
        )
        .route("/internal/mail/inbound", post(inbound_email))
        .route("/webhooks/postmark/inbound", post(postmark_inbound_email))
        .route("/internal/mail/outbound", post(enqueue_service_email))
        .route(
            "/internal/mail/backfill-thread",
            post(backfill_email_thread),
        )
        .route(
            "/internal/mail/backfill-message",
            post(backfill_email_message),
        )
        .nest(
            "/app/v1",
            Router::new()
                .route("/venue-email-threads", post(create_email_thread))
                .route("/stream-token", post(stream_user_token))
                .route("/places/photo", get(get_place_photo))
                .route("/places/reverse-geocode", get(reverse_geocode))
                .route("/spotify/artists/:artist_id", get(get_spotify_artist))
                .route(
                    "/spotify/artists/:artist_id/top-tracks",
                    get(get_spotify_artist_top_tracks),
                )
                .route(
                    "/opportunity-venue-notifications",
                    post(notify_venue_of_interested_opportunities),
                )
                .route_layer(axum::middleware::from_fn_with_state(
                    state.clone(),
                    crate::domain::firebase_auth::verify_firebase_token,
                ))
                // Public: added after `route_layer` so Firebase auth doesn't apply. The web app has
                // no signed-in user; Google spend is bounded by the Places quota caps, and the
                // user/opportunity documents have private fields removed.
                .route(
                    "/places/autocomplete",
                    get(autocomplete_places).layer(public_get_cors()),
                )
                .route("/places/:place_id", get(get_place).layer(public_get_cors()))
                .route(
                    "/users/username/:username",
                    get(get_public_user_by_username).layer(public_get_cors()),
                )
                .route(
                    "/opportunities/:opportunity_id",
                    get(get_public_opportunity).layer(public_get_cors()),
                )
                .into(),
        )
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
                    // Recorded by `verify_firebase_token` on authenticated routes.
                    user_id = tracing::field::Empty,
                )
            }),
        )
        .with_state(state);

    tracing::debug!("listening on {}", listener.local_addr().unwrap());
    let server = axum::serve(listener, app);

    Ok(server)
}

fn public_get_cors() -> CorsLayer {
    CorsLayer::new()
        .allow_origin(Any)
        .allow_methods([axum::http::Method::GET])
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
