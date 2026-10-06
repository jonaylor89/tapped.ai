//! Re-indexes Firestore users into the Typesense `users` collection.
//!
//! ```text
//! search_sync --all [--prune]   every user; --prune also removes search docs with no Firestore user
//! search_sync --since <RFC3339> users who signed up at or after the time
//! search_sync --user <uid>      one user
//! ```
//!
//! Needs the API's env (`FIREBASE_PROJECT_ID`, `GOOGLE_APPLICATION_CREDENTIALS`, `TYPESENSE_*`,
//! including `TYPESENSE_ADMIN_API_KEY`). See `platform/README.md`.

use color_eyre::eyre::{Result, WrapErr, bail, eyre};
use tapped_api_rs::{
    data::{database::Firestore, search::Typesense},
    domain::search_index::{sync_all_users, sync_user, sync_users_created_since},
    startup::firestore_db,
    tracing::{get_subscriber, init_subscriber},
};

const USAGE: &str = "usage: search_sync --all [--prune] | --since <RFC3339> | --user <uid>";

#[tokio::main]
async fn main() -> Result<()> {
    color_eyre::install()?;
    let _ = dotenvy::dotenv();
    init_subscriber(get_subscriber(
        "tapped-search-sync".into(),
        "info".into(),
        std::io::stdout,
    ));

    let args: Vec<String> = std::env::args().skip(1).collect();
    let args: Vec<&str> = args.iter().map(String::as_str).collect();

    let search = Typesense::from_env();
    if !search.can_write() {
        bail!("TYPESENSE_ADMIN_API_KEY is required");
    }
    let project_id =
        std::env::var("FIREBASE_PROJECT_ID").wrap_err("FIREBASE_PROJECT_ID is required")?;
    let database = Firestore::new(firestore_db(project_id).await?);

    match args.as_slice() {
        ["--all"] | ["--all", "--prune"] => {
            let stats = sync_all_users(&database, &search, args.contains(&"--prune"))
                .await
                .map_err(|error| eyre!("{error:#}"))?;
            tracing::info!(?stats, "user search sync finished");
        }
        ["--since", since] => {
            let since = chrono::DateTime::parse_from_rfc3339(since)
                .wrap_err("--since must be RFC 3339, e.g. 2026-01-01T00:00:00Z")?
                .to_utc();
            let stats = sync_users_created_since(&database, &search, since)
                .await
                .map_err(|error| eyre!("{error:#}"))?;
            tracing::info!(?stats, "user search sync finished");
        }
        ["--user", id] => {
            let status = sync_user(&database, &search, id)
                .await
                .map_err(|error| eyre!("{error:#}"))?;
            tracing::info!(user_id = id, ?status, "user search sync finished");
        }
        _ => bail!(USAGE),
    }
    Ok(())
}
