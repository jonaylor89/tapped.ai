use std::{collections::BTreeMap, future::Future, time::Duration};

use aide::OperationOutput;
use axum::{
    Json,
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use schemars::JsonSchema;
use serde::Serialize;

use crate::state::AppStateDyn;

const PROBE_TIMEOUT: Duration = Duration::from_secs(3);

#[derive(Debug, Serialize, JsonSchema)]
pub struct Health {
    pub status: String,
}

#[derive(Debug, Serialize, JsonSchema)]
pub struct Version {
    pub version: String,
}

#[derive(Debug, Serialize, JsonSchema)]
pub struct Readiness {
    /// `ok` when every dependency responded, otherwise `unavailable`.
    pub status: String,
    /// Per-dependency result: `ok`, `error` or `timeout`.
    pub checks: BTreeMap<String, String>,
}

/// A 503 carrying the failing [`Readiness`] checks.
pub struct NotReady(Readiness);

impl IntoResponse for NotReady {
    fn into_response(self) -> Response {
        (StatusCode::SERVICE_UNAVAILABLE, Json(self.0)).into_response()
    }
}

// Documented explicitly on the route.
impl OperationOutput for NotReady {
    type Inner = Readiness;
}

/// Liveness: the process is up and serving requests. Doesn't touch dependencies.
pub async fn health() -> Json<Health> {
    Json(Health {
        status: "ok".into(),
    })
}

pub async fn version() -> Json<Version> {
    Json(Version {
        version: env!("CARGO_PKG_VERSION").into(),
    })
}

async fn probe(name: &str, check: impl Future<Output = anyhow::Result<()>>) -> String {
    match tokio::time::timeout(PROBE_TIMEOUT, check).await {
        Ok(Ok(())) => "ok".into(),
        Ok(Err(error)) => {
            tracing::warn!("readiness check {name} failed: {error:#}");
            "error".into()
        }
        Err(_) => {
            tracing::warn!("readiness check {name} timed out");
            "timeout".into()
        }
    }
}

/// Readiness: Firestore, Typesense and the mail store all answer. Deploys gate on this.
pub async fn ready(State(state): State<AppStateDyn>) -> Result<Json<Readiness>, NotReady> {
    let (firestore, typesense, mail_store) = tokio::join!(
        probe("firestore", state.database.ping()),
        probe("typesense", state.search.ping()),
        probe("mail_store", state.mail.store.ping()),
    );
    let checks = BTreeMap::from([
        ("firestore".to_owned(), firestore),
        ("typesense".to_owned(), typesense),
        ("mail_store".to_owned(), mail_store),
    ]);
    if checks.values().all(|result| result == "ok") {
        Ok(Json(Readiness {
            status: "ok".into(),
            checks,
        }))
    } else {
        Err(NotReady(Readiness {
            status: "unavailable".into(),
            checks,
        }))
    }
}
