use anyhow::{Context, Result};
use sqlx::{PgPool, migrate::Migrator, postgres::PgPoolOptions};
use std::time::Duration;

pub static MIGRATOR: Migrator = sqlx::migrate!("./migrations");

/// Connects to `database_url` and applies pending migrations.
pub async fn connect(database_url: &str) -> Result<PgPool> {
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .acquire_timeout(Duration::from_secs(5))
        .connect(database_url)
        .await
        .context("failed to connect to Postgres")?;
    MIGRATOR
        .run(&pool)
        .await
        .context("failed to run Postgres migrations")?;
    Ok(pool)
}

/// Pool for `DATABASE_URL`, or `None` when it's unset. Nothing serves requests from Postgres yet,
/// so a failed connection is logged instead of stopping the API from booting.
pub async fn from_env() -> Option<PgPool> {
    let url = std::env::var("DATABASE_URL")
        .ok()
        .filter(|url| !url.is_empty())?;
    match connect(&url).await {
        Ok(pool) => {
            tracing::info!("connected to Postgres; migrations applied");
            Some(pool)
        }
        Err(error) => {
            tracing::error!("Postgres unavailable: {error:#}");
            None
        }
    }
}
