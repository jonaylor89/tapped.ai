//! OpenTelemetry trace export to PostHog over OTLP/HTTP.
//!
//! Export is off unless `POSTHOG_PROJECT_TOKEN` is set, so tests, CI and local runs never call
//! PostHog. The JSON logs on stdout are the same either way.

use std::{collections::HashMap, time::Duration};

use async_trait::async_trait;
use axum::{
    body::Bytes,
    http::{Request, Response},
};
use opentelemetry::{KeyValue, trace::TracerProvider as _};
use opentelemetry_http::{HttpClient, HttpError};
use opentelemetry_otlp::{Protocol, SpanExporter, WithExportConfig, WithHttpConfig};
use opentelemetry_sdk::{
    Resource,
    trace::{SdkTracer, SdkTracerProvider},
};

/// The tapped PostHog project is on US cloud; EU projects use `https://eu.i.posthog.com`.
pub const DEFAULT_POSTHOG_HOST: &str = "https://us.i.posthog.com";
const EXPORT_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OtelConfig {
    /// The `phc_` project token, sent as `Authorization: Bearer`.
    pub project_token: String,
    pub host: String,
    pub environment: String,
    pub version: String,
}

impl OtelConfig {
    pub fn from_env() -> Option<Self> {
        Self::from_lookup(|key| std::env::var(key).ok())
    }

    /// `None` when `POSTHOG_PROJECT_TOKEN` is unset or blank.
    pub fn from_lookup(lookup: impl Fn(&str) -> Option<String>) -> Option<Self> {
        let value = |key: &str| {
            lookup(key)
                .map(|value| value.trim().to_owned())
                .filter(|value| !value.is_empty())
        };
        Some(Self {
            project_token: value("POSTHOG_PROJECT_TOKEN")?,
            host: value("POSTHOG_HOST").unwrap_or_else(|| DEFAULT_POSTHOG_HOST.into()),
            environment: value("DEPLOYMENT_ENVIRONMENT").unwrap_or_else(|| "development".into()),
            version: value("SERVICE_VERSION").unwrap_or_else(|| env!("CARGO_PKG_VERSION").into()),
        })
    }

    pub fn traces_endpoint(&self) -> String {
        format!("{}/i/v1/traces", self.host.trim_end_matches('/'))
    }
}

pub fn resource(service_name: &'static str, environment: &str, version: &str) -> Resource {
    Resource::builder_empty()
        .with_service_name(service_name)
        .with_attributes([
            KeyValue::new("service.version", version.to_owned()),
            KeyValue::new("deployment.environment.name", environment.to_owned()),
        ])
        .build()
}

/// A tracer provider with a batch exporter. Call [`Telemetry::shutdown`] before exiting so
/// buffered spans are sent.
pub struct Telemetry {
    provider: SdkTracerProvider,
    tracer: SdkTracer,
}

impl Telemetry {
    /// `Ok(None)` when export is not configured. Must run inside the Tokio runtime.
    pub fn from_env(service_name: &'static str) -> anyhow::Result<Option<Self>> {
        OtelConfig::from_env()
            .map(|config| Self::posthog(service_name, &config))
            .transpose()
    }

    /// Must run inside the Tokio runtime: exports are sent on it.
    pub fn posthog(service_name: &'static str, config: &OtelConfig) -> anyhow::Result<Self> {
        let exporter = SpanExporter::builder()
            .with_http()
            .with_protocol(Protocol::HttpBinary)
            .with_endpoint(config.traces_endpoint())
            .with_timeout(EXPORT_TIMEOUT)
            .with_headers(HashMap::from([(
                "Authorization".to_owned(),
                format!("Bearer {}", config.project_token),
            )]))
            .with_http_client(TokioHttpClient {
                client: crate::http::client_with_timeout(EXPORT_TIMEOUT),
                runtime: tokio::runtime::Handle::current(),
            })
            .build()?;
        let provider = SdkTracerProvider::builder()
            .with_resource(resource(service_name, &config.environment, &config.version))
            .with_batch_exporter(exporter)
            .build();
        let tracer = provider.tracer(service_name);
        Ok(Self { provider, tracer })
    }

    pub fn tracer(&self) -> SdkTracer {
        self.tracer.clone()
    }

    /// Flushes buffered spans and stops the exporter.
    pub async fn shutdown(self) {
        let provider = self.provider;
        // `shutdown` blocks until the export thread finishes, and that export runs on this runtime.
        match tokio::task::spawn_blocking(move || provider.shutdown()).await {
            Ok(Ok(())) => {}
            Ok(Err(error)) => tracing::warn!("failed to flush traces: {error}"),
            Err(error) => tracing::warn!("trace flush task failed: {error}"),
        }
    }
}

/// The batch span processor exports from its own thread with a plain executor, so requests are
/// sent on the app's Tokio runtime with the shared reqwest client.
#[derive(Clone, Debug)]
struct TokioHttpClient {
    client: reqwest::Client,
    runtime: tokio::runtime::Handle,
}

#[async_trait]
impl HttpClient for TokioHttpClient {
    async fn send_bytes(&self, request: Request<Bytes>) -> Result<Response<Bytes>, HttpError> {
        let client = self.client.clone();
        self.runtime
            .spawn(async move {
                let response = client.execute(reqwest::Request::try_from(request)?).await?;
                let mut builder = Response::builder().status(response.status());
                if let Some(headers) = builder.headers_mut() {
                    headers.extend(response.headers().clone());
                }
                let body = response.bytes().await?;
                Ok::<_, HttpError>(builder.body(body)?)
            })
            .await?
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config(vars: &[(&str, &str)]) -> Option<OtelConfig> {
        let vars: HashMap<String, String> = vars
            .iter()
            .map(|(key, value)| (key.to_string(), value.to_string()))
            .collect();
        OtelConfig::from_lookup(|key| vars.get(key).cloned())
    }

    #[test]
    fn export_is_off_without_a_project_token() {
        assert_eq!(config(&[]), None);
        assert_eq!(config(&[("POSTHOG_PROJECT_TOKEN", "  ")]), None);
        assert_eq!(
            config(&[("POSTHOG_HOST", "https://eu.i.posthog.com")]),
            None
        );
    }

    #[test]
    fn defaults_to_us_cloud() {
        let config = config(&[("POSTHOG_PROJECT_TOKEN", "phc_test")]).unwrap();
        assert_eq!(
            config.traces_endpoint(),
            "https://us.i.posthog.com/i/v1/traces"
        );
        assert_eq!(config.environment, "development");
        assert_eq!(config.version, env!("CARGO_PKG_VERSION"));
    }

    #[test]
    fn reads_host_environment_and_version() {
        let config = config(&[
            ("POSTHOG_PROJECT_TOKEN", "phc_test"),
            ("POSTHOG_HOST", "https://eu.i.posthog.com/"),
            ("DEPLOYMENT_ENVIRONMENT", "production"),
            ("SERVICE_VERSION", "ghcr.io/jonaylor89/tapped-api:abc123"),
        ])
        .unwrap();
        assert_eq!(
            config.traces_endpoint(),
            "https://eu.i.posthog.com/i/v1/traces"
        );
        assert_eq!(config.environment, "production");
        assert_eq!(config.version, "ghcr.io/jonaylor89/tapped-api:abc123");
    }

    #[tokio::test]
    async fn builds_and_shuts_down_without_sending_anything() {
        let config = config(&[
            ("POSTHOG_PROJECT_TOKEN", "phc_test"),
            ("POSTHOG_HOST", "http://127.0.0.1:9"),
        ])
        .unwrap();
        let telemetry = Telemetry::posthog("api.tapped.ai", &config).unwrap();
        telemetry.shutdown().await;
    }
}
