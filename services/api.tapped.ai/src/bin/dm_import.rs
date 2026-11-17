//! Imports Stream Chat messaging channels into Postgres direct messages.
//!
//! ```sh
//! DATABASE_URL=… STREAM_KEY=… STREAM_SECRET=… dm_import --dry-run   # counts only, writes nothing
//! DATABASE_URL=… STREAM_KEY=… STREAM_SECRET=… dm_import             # idempotent; re-run for deltas
//! ```
//! Prints a JSON summary. See `services/api.tapped.ai/README.md` (Direct messages) for the cutover.
use tapped_api_rs::{
    data::postgres,
    domain::direct_messages::import::{StreamHttpSource, run},
};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt().with_env_filter("info").init();
    let dry_run = std::env::args().any(|arg| arg == "--dry-run");
    let pool = postgres::connect(&std::env::var("DATABASE_URL")?).await?;
    let source = StreamHttpSource::new(
        std::env::var("STREAM_KEY")?,
        std::env::var("STREAM_SECRET")?,
        std::env::var("STREAM_BASE_URL")
            .unwrap_or_else(|_| "https://chat.stream-io-api.com".into()),
    );
    let stats = run(&pool, &source, dry_run).await?;
    println!(
        "{}",
        serde_json::to_string_pretty(&serde_json::json!({"dryRun": dry_run, "stats": stats}))?
    );
    Ok(())
}
