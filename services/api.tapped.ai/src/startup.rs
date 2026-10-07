use crate::{
    data::places::{AutocompletePrediction, PlaceDetails},
    data::{database::Firestore, places::GooglePlaces, search::Typesense, spotify::SpotifyHttp},
    docs::{docs_routes, serve_docs},
    domain::{
        app_functions::{
            NotifyVenueResponse, StreamUserTokenResponse, get_venue_notification,
            notify_venue_of_interested_opportunities, stream_user_token,
        },
        firebase_auth::verify_firebase_token,
        health::{Health, Readiness, Version, health, ready, version},
        mail_bridge::{
            MailBridge, SqliteMailStore, StreamHttpGateway, backfill_email_message,
            backfill_email_thread, create_email_thread, enqueue_service_email, inbound_email,
            postmark_inbound_email, stream_before_message,
        },
        mail_composer::OpenAiEmailComposer,
        places::{
            PhotoResponse, ReverseGeocodeResponse, autocomplete_places, get_place, get_place_photo,
            reverse_geocode,
        },
        public_docs::{get_public_opportunity, get_public_user_by_username},
        spotify::{get_spotify_artist, get_spotify_artist_top_tracks},
        venue_notifications,
    },
    errors::{AppError, json_error_bodies, panic_response},
    rate_limit::RateLimits,
    request_id::{RequestId, propagate_request_id},
    routes::v1_routes,
    state::AppStateDyn,
};
use aide::{
    axum::{
        ApiRouter,
        routing::{get_with, post_with},
    },
    openapi::{OpenApi, SecurityScheme, Server, Tag},
    transform::{TransformOpenApi, TransformOperation},
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
use firestore::{FirestoreDb, FirestoreDbOptions};
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

/// Upper bound for any request. Kept below `URLSession`'s 60 s default so the server gives up
/// first; slow work such as LLM email composition runs in background jobs, not in a request.
pub const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

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

        tokio::spawn(venue_notifications::run_worker(state.clone()));
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

    /// Serves until SIGTERM/SIGINT, then stops accepting connections and lets in-flight
    /// requests finish.
    pub async fn run_until_stopped(self) -> Result<(), std::io::Error> {
        self.server.with_graceful_shutdown(shutdown_signal()).await
    }
}

async fn run(listener: TcpListener, state: AppStateDyn) -> Result<Serve<Router, Router>> {
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

fn app_op<'a>(op: TransformOperation<'a>, summary: &str) -> TransformOperation<'a> {
    op.tag("app")
        .summary(summary)
        .security_requirement("FirebaseAuth")
}

fn public_op<'a>(op: TransformOperation<'a>, summary: &str) -> TransformOperation<'a> {
    op.tag("public").summary(summary)
}

fn meta_op<'a>(op: TransformOperation<'a>, summary: &str) -> TransformOperation<'a> {
    op.tag("meta").summary(summary)
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
    aide::r#gen::on_error(|error| {
        tracing::error!("{error}");
    });
    aide::r#gen::extract_schemas(true);
    let mut api = OpenApi::default();

    let app_v1_authenticated = ApiRouter::new()
        .route("/venue-email-threads", post(create_email_thread))
        .api_route(
            "/stream-token",
            post_with(stream_user_token, |op| {
                app_op(op, "Mint a Stream chat token for the signed-in user")
                    .response::<200, Json<StreamUserTokenResponse>>()
            }),
        )
        .api_route(
            "/places/photo",
            get_with(get_place_photo, |op| {
                app_op(op, "Resolve a Google place photo to a short-lived URL")
                    .response::<200, Json<PhotoResponse>>()
            }),
        )
        .api_route(
            "/places/reverse-geocode",
            get_with(reverse_geocode, |op| {
                app_op(op, "Locality place for a coordinate")
                    .response::<200, Json<ReverseGeocodeResponse>>()
            }),
        )
        .api_route(
            "/spotify/artists/:artist_id",
            get_with(get_spotify_artist, |op| {
                app_op(op, "Spotify artist by ID")
                    .description("Spotify's artist object, cached for an hour.")
                    .response::<200, Json<serde_json::Value>>()
            }),
        )
        .api_route(
            "/spotify/artists/:artist_id/top-tracks",
            get_with(get_spotify_artist_top_tracks, |op| {
                app_op(op, "Spotify top tracks for an artist")
                    .description("Spotify's `{ tracks }` response, cached for an hour.")
                    .response::<200, Json<serde_json::Value>>()
            }),
        )
        .api_route(
            "/opportunity-venue-notifications",
            post_with(notify_venue_of_interested_opportunities, |op| {
                app_op(
                    op,
                    "Email venues about opportunities the user is interested in",
                )
                .description(
                    "Validates the request and queues a job that emails each unclaimed venue \
                     behind the opportunities. Retrying the same request (same `Idempotency-Key` \
                     header, or the same opportunities and note) within 24 hours returns the \
                     original job instead of emailing again.",
                )
                .response_with::<202, Json<NotifyVenueResponse>, _>(|res| {
                    res.description("The job was queued, or already exists for this request.")
                })
            }),
        )
        .api_route(
            "/opportunity-venue-notifications/:job_id",
            get_with(get_venue_notification, |op| {
                app_op(op, "Status of a venue notification job")
                    .response::<200, Json<NotifyVenueResponse>>()
            }),
        )
        .route_layer(middleware::from_fn_with_state(
            state.clone(),
            verify_firebase_token,
        ));

    // Public: the web app has no signed-in user. Google spend is bounded by the Places quota caps
    // and the per-IP limit, and the user/opportunity documents have private fields removed.
    let app_v1_public = ApiRouter::new()
        .api_route(
            "/places/autocomplete",
            get_with(autocomplete_places, |op| {
                public_op(op, "Autocomplete place names")
                    .response::<200, Json<Vec<AutocompletePrediction>>>()
            }),
        )
        .api_route(
            "/places/:place_id",
            get_with(get_place, |op| {
                public_op(op, "Place details").response::<200, Json<PlaceDetails>>()
            }),
        )
        .api_route(
            "/users/username/:username",
            get_with(get_public_user_by_username, |op| {
                public_op(op, "Public profile by username")
                    .description("The user document with private fields removed. Edge-cacheable: `Cache-Control` allows 5 minutes for a 200 and 1 minute for a 404.")
                    .response::<200, Json<serde_json::Value>>()
            }),
        )
        .api_route(
            "/opportunities/:opportunity_id",
            get_with(get_public_opportunity, |op| {
                public_op(op, "Public opportunity")
                    .description("The opportunity document with private fields removed. Edge-cacheable: `Cache-Control` allows 5 minutes for a 200 and 1 minute for a 404.")
                    .response::<200, Json<serde_json::Value>>()
            }),
        )
        .layer(rate_limits.per_ip_layer())
        .layer(public_get_cors());

    let app = ApiRouter::new()
        .route(
            "/swagger",
            get(|| async { Html(swagger_ui("/swagger/json")) }),
        )
        .route("/swagger/json", get(serve_docs))
        .route("/", get(root))
        .api_route(
            "/version",
            get_with(version, |op| {
                meta_op(op, "API version").response::<200, Json<Version>>()
            }),
        )
        .api_route(
            "/health",
            get_with(health, |op| {
                meta_op(op, "Liveness")
                    .description("The process is serving requests. Doesn't check dependencies.")
                    .response::<200, Json<Health>>()
            }),
        )
        .api_route(
            "/health/ready",
            get_with(ready, |op| {
                meta_op(op, "Readiness")
                    .description("Firestore, Typesense and the mail store all respond within 3s.")
                    .response::<200, Json<Readiness>>()
                    .response::<503, Json<Readiness>>()
            }),
        )
        .route(
            "/webhooks/stream/before-message",
            post(stream_before_message),
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
        .nest("/app/v1", app_v1_authenticated.merge(app_v1_public))
        .nest_api_service("/v1", v1_routes(state.clone(), rate_limits))
        .nest_api_service("/docs", docs_routes(state.clone()))
        .finish_api_with(&mut api, api_docs);

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

fn api_docs(mut api: TransformOpenApi) -> TransformOpenApi {
    let inner = api.inner_mut();
    inner.info.version = env!("CARGO_PKG_VERSION").into();
    inner.servers = vec![Server {
        url: "https://api.tapped.ai".into(),
        ..Default::default()
    }];
    api.title("Tapped API Docs")
        .summary("the leading API for live music data including performers, venues, and events. High quality live music data and aggregates")
        .description("Errors share one shape: `{ \"error\", \"error_id\", \"error_details\"? }`. Quote `error_id` when reporting a problem; it is logged server-side.")
        .tag(Tag {
            name: "v1".into(),
            description: Some("Partner API, authenticated with a `tapped-api-key`.".into()),
            ..Default::default()
        })
        .tag(Tag {
            name: "app".into(),
            description: Some("Used by the Tapped apps, authenticated with a Firebase ID token.".into()),
            ..Default::default()
        })
        .tag(Tag {
            name: "public".into(),
            description: Some("Unauthenticated, rate limited per IP.".into()),
            ..Default::default()
        })
        .tag(Tag {
            name: "meta".into(),
            description: Some("Version, liveness and readiness.".into()),
            ..Default::default()
        })
        .security_scheme(
            "ApiKey",
            SecurityScheme::ApiKey {
                location: aide::openapi::ApiKeyLocation::Header,
                name: "tapped-api-key".into(),
                description: Some("your API Key".into()),
                extensions: Default::default(),
            },
        )
        .security_scheme(
            "FirebaseAuth",
            SecurityScheme::Http {
                scheme: "bearer".into(),
                bearer_format: Some("JWT".into()),
                description: Some("A Firebase Auth ID token for the tapped project.".into()),
                extensions: Default::default(),
            },
        )
        .default_response_with::<Json<AppError>, _>(|res| {
            let mut example = AppError::new("some error happened");
            // Fixed so the generated spec is reproducible.
            example.error_id = uuid::Uuid::nil();
            res.example(example)
        })
}
