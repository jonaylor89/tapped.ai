use anyhow::{Context, Result};
use sqlx::{PgPool, migrate::Migrator, postgres::PgPoolOptions};
use std::time::Duration;

pub static MIGRATOR: Migrator = sqlx::migrate!("./migrations");

const MAX_MIGRATION_RETRY_DELAY: Duration = Duration::from_secs(60);

fn pool_options() -> PgPoolOptions {
    PgPoolOptions::new()
        .max_connections(5)
        .acquire_timeout(Duration::from_secs(5))
}

/// Connects to `database_url` and applies pending migrations.
pub async fn connect(database_url: &str) -> Result<PgPool> {
    let pool = pool_options()
        .connect(database_url)
        .await
        .context("failed to connect to Postgres")?;
    MIGRATOR
        .run(&pool)
        .await
        .context("failed to run Postgres migrations")?;
    Ok(pool)
}

/// A pool that opens connections on demand (and reopens them after Postgres restarts), with
/// migrations applied in the background, retrying until Postgres accepts them. Returns without
/// waiting for Postgres, so a database that is still starting can't block or break boot.
pub fn connect_lazy(database_url: &str) -> Result<PgPool> {
    let pool = pool_options()
        .connect_lazy(database_url)
        .context("invalid DATABASE_URL")?;
    tokio::spawn(migrate_with_retry(pool.clone()));
    Ok(pool)
}

async fn migrate_with_retry(pool: PgPool) {
    let mut delay = Duration::from_secs(1);
    loop {
        match MIGRATOR.run(&pool).await {
            Ok(()) => {
                tracing::info!("connected to Postgres; migrations applied");
                return;
            }
            Err(error) => {
                tracing::warn!(
                    "Postgres migrations not applied yet, retrying in {delay:?}: {error}"
                );
                tokio::time::sleep(delay).await;
                delay = (delay * 2).min(MAX_MIGRATION_RETRY_DELAY);
            }
        }
    }
}

/// Lazy pool for `DATABASE_URL`, or `None` when it's unset. Nothing serves requests from
/// Postgres yet, so an unreachable database is logged and retried rather than fatal.
pub fn from_env() -> Option<PgPool> {
    let url = std::env::var("DATABASE_URL")
        .ok()
        .filter(|url| !url.is_empty())?;
    match connect_lazy(&url) {
        Ok(pool) => Some(pool),
        Err(error) => {
            tracing::error!("Postgres disabled: {error:#}");
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn lazy_pool_does_not_wait_for_an_unreachable_database() {
        let started = std::time::Instant::now();
        let pool = connect_lazy("postgres://tapped:secret@127.0.0.1:1/tapped").expect("lazy pool");
        assert!(started.elapsed() < Duration::from_secs(1));
        assert!(pool.acquire().await.is_err());
    }
}
