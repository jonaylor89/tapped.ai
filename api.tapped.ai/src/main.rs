use color_eyre::eyre::{Result, WrapErr};
use tapped_api_rs::{
    startup::Application,
    tracing::{get_subscriber, init_subscriber},
};

#[tokio::main]
async fn main() -> Result<()> {
    color_eyre::install()?;
    let parse_dotenv = dotenvy::dotenv();
    if let Err(e) = parse_dotenv {
        tracing::warn!("failed to parse .env file: {}", e);
    }

    let subscriber = get_subscriber("tapped-api".into(), "info".into(), std::io::stdout);
    init_subscriber(subscriber);

    let port: u16 = std::env::var("PORT")
        .unwrap_or_else(|_| "3000".into())
        .parse()
        .wrap_err("failed to parse PORT")?;
    let project_id = std::env::var("FIREBASE_PROJECT_ID").wrap_err("Failed to parse PROJECT_ID")?;

    let app = Application::build(port, project_id).await?;
    app.run_until_stopped().await?;

    Ok(())
}
