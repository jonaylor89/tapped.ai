use color_eyre::eyre::{Result, WrapErr};
use reqwest::Client;
use std::sync::Arc;
use tapped_api_rs::{
    domain::{
        mail_bridge::SqliteMailStore,
        mail_worker::{MailTransport, run_worker},
    },
    tracing::{get_subscriber, init_subscriber},
};

#[tokio::main]
async fn main() -> Result<()> {
    color_eyre::install()?;
    let _ = dotenvy::dotenv();
    init_subscriber(get_subscriber(
        "tapped-mail-worker".into(),
        "info".into(),
        std::io::stdout,
    ));
    let path = std::env::var("MAIL_STORE_PATH").unwrap_or_else(|_| "tapped-mail.sqlite3".into());
    let transport_name = std::env::var("MAIL_TRANSPORT").unwrap_or_else(|_| "smtp".into());
    let transport = match transport_name.as_str() {
        "smtp" => MailTransport::Smtp {
            address: std::env::var("SMTP_ADDRESS").unwrap_or_else(|_| "127.0.0.1:2525".into()),
        },
        "postmark" => MailTransport::Postmark {
            client: Client::new(),
            server_token: std::env::var("POSTMARK_SERVER_TOKEN")
                .wrap_err("POSTMARK_SERVER_TOKEN is required for the Postmark transport")?,
        },
        value => color_eyre::eyre::bail!("unsupported MAIL_TRANSPORT: {value}"),
    };
    let store =
        SqliteMailStore::open(&path).map_err(|error| color_eyre::eyre::eyre!(error.to_string()))?;
    tracing::info!(mail_transport = transport_name, "mail worker started");
    run_worker(Arc::new(store), transport).await;
}
