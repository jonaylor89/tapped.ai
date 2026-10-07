use color_eyre::eyre::{Result, WrapErr};
use std::sync::Arc;
use tapped_api_rs::{
    domain::{
        mail_bridge::SqliteMailStore,
        mail_worker::{MailTransport, run_worker},
    },
    startup::shutdown_signal,
    telemetry::Telemetry,
    tracing::{get_subscriber_with_tracer, init_subscriber},
};

#[tokio::main]
async fn main() -> Result<()> {
    color_eyre::install()?;
    let _ = dotenvy::dotenv();
    let telemetry = Telemetry::from_env("mail-worker.tapped.ai");
    init_subscriber(get_subscriber_with_tracer(
        "tapped-mail-worker".into(),
        "info".into(),
        std::io::stdout,
        telemetry
            .as_ref()
            .ok()
            .and_then(Option::as_ref)
            .map(Telemetry::tracer),
    ));
    let telemetry = match telemetry {
        Ok(telemetry) => telemetry,
        Err(error) => {
            tracing::warn!("trace export disabled: {error:#}");
            None
        }
    };
    let path = std::env::var("MAIL_STORE_PATH").unwrap_or_else(|_| "tapped-mail.sqlite3".into());
    let transport_name = std::env::var("MAIL_TRANSPORT").unwrap_or_else(|_| "smtp".into());
    let transport = match transport_name.as_str() {
        "smtp" => MailTransport::Smtp {
            address: std::env::var("SMTP_ADDRESS").unwrap_or_else(|_| "127.0.0.1:2525".into()),
        },
        "postmark" => MailTransport::Postmark {
            client: tapped_api_rs::http::client_with_timeout(std::time::Duration::from_secs(30)),
            server_token: std::env::var("POSTMARK_SERVER_TOKEN")
                .wrap_err("POSTMARK_SERVER_TOKEN is required for the Postmark transport")?,
        },
        value => {
            return Err(color_eyre::eyre::eyre!(
                "unsupported MAIL_TRANSPORT: {value}"
            ));
        }
    };
    let store =
        SqliteMailStore::open(&path).map_err(|error| color_eyre::eyre::eyre!(error.to_string()))?;
    tracing::info!(mail_transport = transport_name, "mail worker started");
    tokio::select! {
        _ = run_worker(Arc::new(store), transport) => {}
        () = shutdown_signal() => {}
    }
    if let Some(telemetry) = telemetry {
        telemetry.shutdown().await;
    }
    Ok(())
}
