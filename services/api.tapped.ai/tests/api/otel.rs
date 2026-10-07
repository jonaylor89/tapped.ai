use crate::helpers::spawn_app;
use opentelemetry::{
    Value,
    trace::{SpanId, SpanKind, TraceId, TracerProvider as _},
};
use opentelemetry_sdk::trace::{InMemorySpanExporter, SdkTracerProvider, SpanData};
use tapped_api_rs::{
    data::places::{GooglePlaces, Places},
    tracing::get_subscriber_with_tracer,
};
use tracing::Instrument;

const TRACE_ID: &str = "4bf92f3577b34da6a3ce929d0e0e4736";
const PARENT_SPAN_ID: &str = "00f067aa0ba902b7";

/// Exports to memory through the same subscriber the binaries use.
fn in_memory_tracing() -> (
    InMemorySpanExporter,
    SdkTracerProvider,
    tracing::subscriber::DefaultGuard,
) {
    let exporter = InMemorySpanExporter::default();
    let provider = SdkTracerProvider::builder()
        .with_simple_exporter(exporter.clone())
        .build();
    let guard = tracing::subscriber::set_default(get_subscriber_with_tracer(
        "test".into(),
        "info".into(),
        std::io::sink,
        Some(provider.tracer("test")),
    ));
    (exporter, provider, guard)
}

fn attribute(span: &SpanData, key: &str) -> Option<Value> {
    span.attributes
        .iter()
        .find(|kv| kv.key.as_str() == key)
        .map(|kv| kv.value.clone())
}

fn server_span(spans: &[SpanData]) -> &SpanData {
    spans
        .iter()
        .find(|span| span.span_kind == SpanKind::Server)
        .unwrap_or_else(|| panic!("no server span in {spans:#?}"))
}

// `#[tokio::test]` runs the server on this thread, so the thread-local subscriber sees its spans.
#[tokio::test]
async fn server_span_joins_the_incoming_w3c_trace() {
    let (exporter, provider, _guard) = in_memory_tracing();
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(format!("{}/app/v1/opportunities/opp-1", app.address))
        .header("traceparent", format!("00-{TRACE_ID}-{PARENT_SPAN_ID}-01"))
        .header("tracestate", "ios=1")
        .header("x-request-id", "ios-req-1")
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), 200);

    provider.force_flush().unwrap();
    let spans = exporter.get_finished_spans().unwrap();
    let span = server_span(&spans);
    assert_eq!(span.name, "GET /app/v1/opportunities/:opportunity_id");
    assert_eq!(
        span.span_context.trace_id(),
        TraceId::from_hex(TRACE_ID).unwrap()
    );
    assert_eq!(
        span.parent_span_id,
        SpanId::from_hex(PARENT_SPAN_ID).unwrap()
    );
    assert_eq!(span.span_context.trace_state().header(), "ios=1");
    assert_eq!(attribute(span, "request_id"), Some("ios-req-1".into()));
    assert_eq!(
        attribute(span, "http.route"),
        Some("/app/v1/opportunities/:opportunity_id".into())
    );
    assert_eq!(attribute(span, "http.request.method"), Some("GET".into()));
    assert_eq!(
        attribute(span, "http.response.status_code"),
        Some(200.into())
    );
}

#[tokio::test]
async fn server_span_starts_a_new_trace_without_traceparent() {
    let (exporter, provider, _guard) = in_memory_tracing();
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(format!("{}/health", app.address))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), 200);

    provider.force_flush().unwrap();
    let spans = exporter.get_finished_spans().unwrap();
    let span = server_span(&spans);
    assert_eq!(span.parent_span_id, SpanId::INVALID);
    assert!(span.span_context.is_valid());
    let request_id = response.headers()["x-request-id"].to_str().unwrap();
    assert_eq!(
        attribute(span, "request_id"),
        Some(request_id.to_owned().into())
    );
}

#[tokio::test]
async fn dependency_calls_are_client_child_spans() {
    let (exporter, provider, _guard) = in_memory_tracing();
    // No API key: the call fails before any network I/O, but its span is still recorded.
    let places = GooglePlaces::new(String::new());

    async {
        assert!(places.autocomplete("bar", &[], None).await.is_err());
    }
    .instrument(tracing::info_span!("parent"))
    .await;

    provider.force_flush().unwrap();
    let spans = exporter.get_finished_spans().unwrap();
    let parent = spans.iter().find(|span| span.name == "parent").unwrap();
    let child = spans
        .iter()
        .find(|span| span.name == "autocomplete")
        .unwrap_or_else(|| panic!("no dependency span in {spans:#?}"));
    assert_eq!(child.span_kind, SpanKind::Client);
    assert_eq!(child.parent_span_id, parent.span_context.span_id());
    assert_eq!(
        child.span_context.trace_id(),
        parent.span_context.trace_id()
    );
    assert_eq!(attribute(child, "dependency"), Some("google_places".into()));
    assert_eq!(
        attribute(child, "server.address"),
        Some("places.googleapis.com".into())
    );
}

#[tokio::test]
async fn exports_to_the_posthog_traces_endpoint_with_the_project_token() {
    use axum::{
        Router,
        body::Bytes,
        http::{HeaderMap, Uri},
    };
    use tapped_api_rs::telemetry::{OtelConfig, Telemetry};

    // A local stand-in for PostHog's OTLP endpoint.
    let (sender, mut received) = tokio::sync::mpsc::unbounded_channel();
    let collector = Router::new().fallback(move |uri: Uri, headers: HeaderMap, body: Bytes| {
        let sender = sender.clone();
        async move {
            sender
                .send((uri.path().to_owned(), headers, body.len()))
                .unwrap();
        }
    });
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, collector).await.unwrap() });

    let config = OtelConfig::from_lookup(|key| match key {
        "POSTHOG_PROJECT_TOKEN" => Some("phc_test".into()),
        "POSTHOG_HOST" => Some(format!("http://{address}")),
        _ => None,
    })
    .unwrap();
    let telemetry = Telemetry::posthog("api.tapped.ai", &config).unwrap();
    {
        let _guard = tracing::subscriber::set_default(get_subscriber_with_tracer(
            "test".into(),
            "info".into(),
            std::io::sink,
            Some(telemetry.tracer()),
        ));
        tracing::info_span!("work").in_scope(|| {});
    }
    // The batch exporter only sends on its interval or at shutdown.
    assert!(received.try_recv().is_err());
    telemetry.shutdown().await;

    let (path, headers, body_len) = received.try_recv().expect("nothing was exported");
    assert_eq!(path, "/i/v1/traces");
    assert_eq!(headers["authorization"], "Bearer phc_test");
    assert_eq!(headers["content-type"], "application/x-protobuf");
    assert!(body_len > 0);
}
