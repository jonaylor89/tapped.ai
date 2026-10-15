use std::time::Duration;
use tapped_api_rs::{
    data::{apns::Apns, google_identity::GoogleIdentity, postgres},
    domain::{
        identity_worker::{ProviderWorker, scan_identities},
        mail_bridge::SqliteMailStore,
    },
    startup::shutdown_signal,
};
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt().with_env_filter("info").init();
    let pool = postgres::connect(&std::env::var("DATABASE_URL")?).await?;
    let google = GoogleIdentity::new(
        &std::env::var("IDENTITY_CREDENTIALS_FILE")?,
        &std::env::var("FIREBASE_PROJECT_ID")?,
    )?;
    let apns = match std::env::var("APNS_KEY_FILE") {
        Ok(file) if !file.is_empty() => Some(Apns::new(
            &file,
            &std::env::var("APNS_KEY_ID")?,
            &std::env::var("APNS_TEAM_ID")?,
            &std::env::var("APNS_TOPIC").unwrap_or_else(|_| "com.intheloopstudio".into()),
        )?),
        _ => None,
    };
    let scanner_pool = pool.clone();
    let scanner_google = google.clone();
    let worker = ProviderWorker {
        pool,
        google,
        mail: SqliteMailStore::open(&std::env::var("MAIL_STORE_PATH")?)?,
        client: reqwest::Client::builder()
            .timeout(Duration::from_secs(30))
            .redirect(reqwest::redirect::Policy::none())
            .build()?,
        stream_key: std::env::var("STREAM_KEY")?,
        stream_secret: std::env::var("STREAM_SECRET")?,
        stream_base_url: std::env::var("STREAM_BASE_URL")
            .unwrap_or_else(|_| "https://chat.stream-io-api.com".into()),
        auth_effects: std::env::var("AUTH_EFFECTS_ENABLED").as_deref() == Ok("1"),
        apns,
    };
    let scan = async {
        loop {
            match scan_identities(&scanner_pool, &scanner_google).await {
                Ok(count) => tracing::info!(accounts = count, "identity-only scan completed"),
                Err(_) => tracing::warn!("identity scan failed; no unconfirmed deletions inferred"),
            }
            tokio::time::sleep(Duration::from_secs(60)).await;
        }
    };
    tokio::select! {_=scan=>{},_=worker.run()=>{},()=shutdown_signal()=>{}}
    Ok(())
}
