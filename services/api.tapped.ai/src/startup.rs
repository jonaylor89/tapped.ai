use crate::{
    data::{
        pg_database::PostgresDatabase, pg_search::PostgresSearch, places::GooglePlaces,
        redis_places::RedisPlaceCache, spotify::SpotifyHttp,
    },
    docs::{ApiDoc, SharedDocs, docs_routes, serve_docs},
    domain::{
        firebase_auth::verify_firebase_token,
        founder_notifications::{SlackWebhook, run_worker as run_founder_worker},
        mail_bridge::{
            MailBridge, SqliteMailStore, StreamHttpGateway, backfill_email_message,
            backfill_email_thread, create_email_thread, enqueue_service_email, inbound_email,
            postmark_inbound_email, stream_before_message,
        },
        mail_composer::OpenAiEmailComposer,
    },
    errors::{AppError, json_error_bodies, panic_response},
    rate_limit::RateLimits,
    request_id::{RequestId, propagate_request_id},
    routes::v1_routes,
    state::AppStateDyn,
};
use axum::Router;
use axum::serve::Serve;
use axum::{
    BoxError, Extension, Json,
    error_handling::HandleErrorLayer,
    extract::MatchedPath,
    http::{Request, StatusCode},
    middleware,
    response::{Html, Response},
    routing::{get, post},
};
use axum_swagger_ui::swagger_ui;
use color_eyre::eyre::Result;
use color_eyre::eyre::WrapErr;
use opentelemetry::propagation::TextMapPropagator;
use opentelemetry_http::HeaderExtractor;
use opentelemetry_sdk::propagation::TraceContextPropagator;
use serde_json::{Value, json};
use std::{sync::Arc, time::Duration};
use tokio::net::TcpListener;
use tower::ServiceBuilder;
use tower_http::{
    catch_panic::CatchPanicLayer,
    cors::{Any, CorsLayer},
    trace::TraceLayer,
};
use tracing::{Span, info_span};
use tracing_opentelemetry::OpenTelemetrySpanExt;
use utoipa::openapi::OpenApi;
use utoipa::{Modify, OpenApi as _};
use utoipa_axum::{router::OpenApiRouter, routes};

/// Upper bound for any request, including slow upstreams (LLM email composition, Places).
pub const REQUEST_TIMEOUT: Duration = Duration::from_secs(90);

pub struct Application {
    port: u16,
    server: Serve<TcpListener, Router, Router>,
    founder_worker: Option<tokio::task::JoinHandle<()>>,
    reminder_worker: Option<tokio::task::JoinHandle<()>>,
}

impl Application {
    pub async fn build(port: u16, project_id: String) -> Result<Self> {
        let listener = TcpListener::bind(format!("0.0.0.0:{}", port)).await.wrap_err(
            "Failed to bind to the port. Make sure you have the correct permissions to bind to the port",
        )?;

        let firebase_auth_emulator = crate::domain::firebase_auth::auth_emulator_enabled(
            &project_id,
            std::env::var("FIREBASE_AUTH_EMULATOR_HOST").ok().as_deref(),
        )
        .map_err(|e| color_eyre::eyre::eyre!("{e:#}"))?;
        if firebase_auth_emulator {
            tracing::warn!("accepting unsigned Firebase Auth Emulator tokens for {project_id}");
        }

        // A hard cutover: missing or unavailable Postgres fails boot, never selects Firestore.
        let database_url = std::env::var("DATABASE_URL").wrap_err("DATABASE_URL is required")?;
        let postgres = crate::data::postgres::connect(&database_url)
            .await
            .map_err(|e| color_eyre::eyre::eyre!("Postgres initialization failed: {e:#}"))?;
        let place_cache = RedisPlaceCache::from_env()
            .map_err(|e| color_eyre::eyre::eyre!("Redis initialization failed: {e:#}"))?
            .ok_or_else(|| color_eyre::eyre::eyre!("REDIS_URL is required"))?;

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
            database: Arc::new(PostgresDatabase::new(postgres.clone())),
            search: Arc::new(PostgresSearch::new(postgres.clone())),
            firebase_project_id: project_id,
            firebase_auth_emulator,
            auth_webhook_secret: std::env::var("AUTH_WEBHOOK_SECRET").ok(),
            mail,
            response_cache: Default::default(),
            place_cache: Some(place_cache),
            places: Arc::new(GooglePlaces::new(google_places_api_key)),
            spotify: Arc::new(SpotifyHttp::new(spotify_client_id, spotify_client_secret)),
            postgres: Some(postgres),
            media: crate::domain::uploads::MediaUploads::from_env(),
        };

        let founder_transport = state
            .mail
            .slack_webhook_url
            .as_deref()
            .filter(|url| !url.trim().is_empty())
            .map(SlackWebhook::new)
            .transpose()
            .map_err(|error| color_eyre::eyre::eyre!("{error}"))?;
        let founder_pool = state.postgres.clone().expect("production Postgres pool");
        let reminder_pool = founder_pool.clone();
        let server = run(listener, state).await?;
        let reminder_worker = (std::env::var("BOOKING_REMINDERS_ENABLED").as_deref() == Ok("1"))
            .then(|| tokio::spawn(crate::domain::booking_reminders::run(reminder_pool)));
        let founder_worker = founder_transport.map(|transport| {
            tracing::info!("Postgres founder notification worker enabled");
            tokio::spawn(run_founder_worker(founder_pool, transport))
        });
        if founder_worker.is_none() {
            tracing::warn!(
                "SLACK_WEBHOOK_URL unset; founder events remain queued until a worker is configured"
            );
        }
        Ok(Self {
            port,
            server,
            founder_worker,
            reminder_worker,
        })
    }

    pub async fn build_with_state(port: u16, state: AppStateDyn) -> Result<Self> {
        let listener = TcpListener::bind(format!("0.0.0.0:{}", port)).await.wrap_err(
            "Failed to bind to the port. Make sure you have the correct permissions to bind to the port",
        )?;
        let port = listener.local_addr()?.port();

        let server = run(listener, state).await?;
        Ok(Self {
            port,
            server,
            founder_worker: None,
            reminder_worker: None,
        })
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    /// Serves until SIGTERM/SIGINT, then stops accepting connections and lets in-flight
    /// requests finish.
    pub async fn run_until_stopped(self) -> Result<(), std::io::Error> {
        let result = self.server.with_graceful_shutdown(shutdown_signal()).await;
        if let Some(worker) = self.founder_worker {
            worker.abort();
            let _ = worker.await;
        }
        if let Some(worker) = self.reminder_worker {
            worker.abort();
            let _ = worker.await;
        }
        result
    }
}

async fn run(
    listener: TcpListener,
    state: AppStateDyn,
) -> Result<Serve<TcpListener, Router, Router>> {
    let rate_limits = RateLimits::default();
    rate_limits.spawn_cleanup();
    let (app, _) = api_router(state, &rate_limits);

    tracing::debug!("listening on {}", listener.local_addr()?);
    Ok(axum::serve(listener, app))
}

pub async fn shutdown_signal() {
    let ctrl_c = async {
        if let Err(error) = tokio::signal::ctrl_c().await {
            tracing::error!("failed to listen for ctrl-c: {error}");
            std::future::pending::<()>().await;
        }
    };
    #[cfg(unix)]
    let terminate = async {
        match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(mut signal) => {
                signal.recv().await;
            }
            Err(error) => {
                tracing::error!("failed to listen for SIGTERM: {error}");
                std::future::pending::<()>().await;
            }
        }
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        () = ctrl_c => {},
        () = terminate => {},
    }
    tracing::info!("shutdown signal received, draining in-flight requests");
}

async fn handle_timeout(error: BoxError) -> AppError {
    if error.is::<tower::timeout::error::Elapsed>() {
        AppError::new("request timed out").with_status(StatusCode::GATEWAY_TIMEOUT)
    } else {
        AppError::internal("request failed", anyhow::anyhow!(error))
    }
}

/// The full app and its OpenAPI document, generated from the routes registered here.
pub fn api_router(state: AppStateDyn, rate_limits: &RateLimits) -> (Router, Arc<OpenApi>) {
    use crate::domain::{
        app_data, app_functions, health, places, public_docs, public_map, public_profile, spotify,
    };

    let app_v1_authenticated = OpenApiRouter::new()
        .routes(routes!(crate::domain::commands::create_profile))
        .routes(routes!(crate::domain::commands::update_profile))
        .routes(routes!(crate::domain::commands::request_booking))
        .routes(routes!(crate::domain::commands::edit_booking))
        .routes(routes!(crate::domain::commands::accept_booking))
        .routes(routes!(crate::domain::commands::cancel_booking))
        .routes(routes!(crate::domain::commands::reschedule_booking))
        .routes(routes!(crate::domain::commands::submit_review))
        .routes(routes!(app_data::search_private))
        .routes(routes!(app_data::list_private, app_data::create))
        .routes(routes!(
            app_data::get_private,
            app_data::update,
            app_data::remove
        ))
        .route(
            "/username-availability/{username}",
            get(app_data::username_available),
        )
        .route(
            "/opportunities/{id}/interest",
            get(app_data::interest_status).put(app_data::set_interest),
        )
        .route("/feedback", post(crate::domain::feedback::submit))
        .route(
            "/spotify/oauth/authorize",
            post(crate::domain::spotify_oauth::authorize),
        )
        .route(
            "/spotify/oauth/exchange",
            post(crate::domain::spotify_oauth::exchange),
        )
        .route(
            "/spotify/oauth/refresh",
            post(crate::domain::spotify_oauth::refresh),
        )
        .route("/device-token", post(app_data::register_token))
        .route("/uploads", post(crate::domain::uploads::create))
        .route("/venue-email-threads", post(create_email_thread))
        .routes(routes!(app_functions::revoke_stream_user_tokens))
        .routes(routes!(app_functions::stream_user_token))
        .routes(routes!(places::get_place_photo))
        .routes(routes!(places::reverse_geocode))
        .routes(routes!(places::get_locality_place))
        .routes(routes!(spotify::get_spotify_artist))
        .routes(routes!(spotify::get_spotify_artist_top_tracks))
        .routes(routes!(
            app_functions::notify_venue_of_interested_opportunities
        ))
        .route_layer(middleware::from_fn_with_state(
            state.clone(),
            verify_firebase_token,
        ));

    // Public: the web app has no signed-in user. Google spend is bounded by the Places quota caps
    // and the per-IP limit, and the user/opportunity documents have private fields removed.
    let app_v1_public = OpenApiRouter::new()
        .routes(routes!(public_map::get_map))
        .routes(routes!(crate::domain::app_config::get_app_config))
        .routes(routes!(app_data::search_public))
        .routes(routes!(app_data::list_public))
        .routes(routes!(app_data::get_public))
        .routes(routes!(public_profile::get_details))
        .routes(routes!(crate::domain::commands::profile_stats))
        .route(
            "/public/users/{id}/booking-count",
            get(app_data::booking_count),
        )
        .route(
            "/public/opportunities/{id}/interests",
            get(app_data::interests),
        )
        .routes(routes!(places::autocomplete_places))
        .routes(routes!(places::get_place))
        .routes(routes!(public_docs::get_public_user_by_username))
        .routes(routes!(public_docs::get_public_opportunity))
        .layer(rate_limits.per_ip_layer())
        .layer(public_get_cors());

    let (documented, mut api) = OpenApiRouter::with_openapi(ApiDoc::openapi())
        .routes(routes!(health::version))
        .routes(routes!(health::health))
        .routes(routes!(health::ready))
        .nest("/app/v1", app_v1_authenticated.merge(app_v1_public))
        .nest("/v1", v1_routes(state.clone(), rate_limits))
        .split_for_parts();
    SharedDocs.modify(&mut api);

    let app = documented
        .route(
            "/swagger",
            get(|| async { Html(swagger_ui("/swagger/json")) }),
        )
        .route("/swagger/json", get(serve_docs))
        .route("/", get(root))
        .route(
            "/webhooks/stream/before-message",
            post(stream_before_message),
        )
        .route(
            "/webhooks/firebase/auth",
            post(crate::domain::auth_lifecycle::webhook),
        )
        .route(
            "/webhooks/spotify/callback",
            get(crate::domain::spotify_oauth::callback),
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
        .merge(crate::domain::mcp::router(state.clone(), rate_limits))
        .merge(docs_routes(&api));

    let api = Arc::new(api);
    // Layers run outermost-last: request ID -> trace -> catch panics -> JSON error bodies ->
    // timeout -> app.
    let router = app
        .layer(Extension(api.clone())) // Arc is very important here or you will face massive memory and performance issues
        .layer(
            ServiceBuilder::new()
                .layer(HandleErrorLayer::new(handle_timeout))
                .timeout(REQUEST_TIMEOUT),
        )
        .layer(middleware::map_response(json_error_bodies))
        .layer(CatchPanicLayer::custom(panic_response))
        .layer(
            TraceLayer::new_for_http()
                .make_span_with(|request: &Request<_>| {
                    // The matched route's path, with placeholders not filled in.
                    let matched_path = request
                        .extensions()
                        .get::<MatchedPath>()
                        .map(MatchedPath::as_str);
                    let request_id = request
                        .extensions()
                        .get::<RequestId>()
                        .map(|id| id.0.as_str());

                    let method = request.method();
                    let span_name = match matched_path {
                        Some(route) => format!("{method} {route}"),
                        None => method.to_string(),
                    };

                    let span = info_span!(
                        "http_request",
                        method = %method,
                        matched_path,
                        request_id,
                        // Recorded by the Firebase and API-key auth middleware.
                        user_id = tracing::field::Empty,
                        status = tracing::field::Empty,
                        latency_ms = tracing::field::Empty,
                        // OpenTelemetry semantic conventions for the exported server span.
                        otel.name = %span_name,
                        otel.kind = "server",
                        otel.status_code = tracing::field::Empty,
                        http.request.method = %method,
                        http.route = matched_path,
                        http.response.status_code = tracing::field::Empty,
                    );
                    // Join the caller's trace (W3C `traceparent`/`tracestate`). This fails
                    // harmlessly when trace export is off.
                    let parent =
                        TraceContextPropagator::new().extract(&HeaderExtractor(request.headers()));
                    let _ = span.set_parent(parent);
                    span
                })
                .on_response(|response: &Response, latency: Duration, span: &Span| {
                    let status = response.status().as_u16();
                    let latency_ms = latency.as_secs_f64() * 1_000.0;
                    span.record("status", status);
                    span.record("http.response.status_code", i64::from(status));
                    span.record("latency_ms", latency_ms);
                    if response.status().is_server_error() {
                        span.record("otel.status_code", "error");
                    }
                    // The fields come from the span, so the line isn't repeated with duplicate keys.
                    tracing::info!("request completed");
                }),
        )
        .layer(middleware::from_fn(propagate_request_id))
        .with_state(state);

    (router, api)
}

fn public_get_cors() -> CorsLayer {
    CorsLayer::new()
        .allow_origin(Any)
        .allow_methods([axum::http::Method::GET])
}

async fn root() -> Json<Value> {
    json!({ "status": "ok" }).into()
}
