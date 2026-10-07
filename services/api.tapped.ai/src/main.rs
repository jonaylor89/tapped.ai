use color_eyre::eyre::{Result, WrapErr};
use tapped_api_rs::{
    startup::Application,
    telemetry::Telemetry,
    tracing::{get_subscriber_with_tracer, init_subscriber},
};

const SERVICE_NAME: &str = "api.tapped.ai";

#[tokio::main]
async fn main() -> Result<()> {
    color_eyre::install()?;
    let parse_dotenv = dotenvy::dotenv();
    if let Err(e) = parse_dotenv {
        tracing::warn!("failed to parse .env file: {}", e);
    }

    let telemetry = Telemetry::from_env(SERVICE_NAME);
    let tracer = telemetry
        .as_ref()
        .ok()
        .and_then(Option::as_ref)
        .map(Telemetry::tracer);
    let subscriber =
        get_subscriber_with_tracer("tapped-api".into(), "info".into(), std::io::stdout, tracer);
    init_subscriber(subscriber);
    let telemetry = log_telemetry_status(telemetry);

    let port: u16 = std::env::var("PORT")
        .unwrap_or_else(|_| "3000".into())
        .parse()
        .wrap_err("failed to parse PORT")?;
    let project_id = std::env::var("FIREBASE_PROJECT_ID").wrap_err("Failed to parse PROJECT_ID")?;

    let app = Application::build(port, project_id).await?;
    let served = app.run_until_stopped().await;
    if let Some(telemetry) = telemetry {
        telemetry.shutdown().await;
    }
    served?;

    Ok(())
}

fn log_telemetry_status(telemetry: anyhow::Result<Option<Telemetry>>) -> Option<Telemetry> {
    match telemetry {
        Ok(Some(telemetry)) => {
            tracing::info!("exporting traces to PostHog");
            Some(telemetry)
        }
        Ok(None) => {
            tracing::info!("POSTHOG_PROJECT_TOKEN is not set; traces are not exported");
            None
        }
        Err(error) => {
            tracing::warn!("trace export disabled: {error:#}");
            None
        }
    }
}
