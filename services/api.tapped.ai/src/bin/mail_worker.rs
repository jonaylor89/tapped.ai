use color_eyre::eyre::Result;
use std::sync::Arc;
use tapped_api_rs::{
    domain::{mail_bridge::SqliteMailStore, mail_worker::run_worker},
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
    let smtp = std::env::var("SMTP_ADDRESS").unwrap_or_else(|_| "127.0.0.1:2525".into());
    let store =
        SqliteMailStore::open(&path).map_err(|error| color_eyre::eyre::eyre!(error.to_string()))?;
    tracing::info!(smtp_address = smtp, "mail worker started");
    run_worker(Arc::new(store), smtp).await;
}
