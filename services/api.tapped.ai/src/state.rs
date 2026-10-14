use crate::{
    data::{
        database::Database, places::Places, redis_places::RedisPlaceCache, search::Search,
        spotify::Spotify,
    },
    domain::mail_bridge::MailBridge,
};
use serde_json::Value;
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

/// A bounded, process-local cache for read-only API responses.
///
/// Values are serialized JSON so handlers can cache responses without requiring all API models
/// to be `Clone`. This keeps repeated public profile, search, and location requests from causing
/// additional Postgres reads. The short TTLs intentionally limit stale data.
#[derive(Clone, Default)]
pub struct ResponseCache {
    entries: Arc<Mutex<HashMap<String, CachedResponse>>>,
}

struct CachedResponse {
    value: Value,
    expires_at: Instant,
}

impl ResponseCache {
    const MAX_ENTRIES: usize = 1_000;

    pub fn get(&self, key: &str) -> Option<Value> {
        let mut entries = self.entries.lock().expect("response cache mutex poisoned");
        match entries.get(key) {
            Some(entry) if entry.expires_at > Instant::now() => Some(entry.value.clone()),
            Some(_) => {
                entries.remove(key);
                None
            }
            None => None,
        }
    }

    pub fn insert(&self, key: String, value: Value, ttl: Duration) {
        let mut entries = self.entries.lock().expect("response cache mutex poisoned");
        let now = Instant::now();
        entries.retain(|_, entry| entry.expires_at > now);
        if entries.len() >= Self::MAX_ENTRIES
            && let Some(key) = entries.keys().next().cloned()
        {
            entries.remove(&key);
        }
        entries.insert(
            key,
            CachedResponse {
                value,
                expires_at: now + ttl,
            },
        );
    }
}

#[derive(Clone)]
pub struct AppStateDyn {
    pub database: Arc<dyn Database>,
    pub search: Arc<dyn Search>,
    pub firebase_project_id: String,
    /// Accept unsigned Firebase Auth Emulator tokens (local stacks only, `demo-*` projects).
    pub firebase_auth_emulator: bool,
    /// Dedicated ingress credential for the retained transport-only Firebase Auth hooks.
    pub auth_webhook_secret: Option<String>,
    pub mail: MailBridge,
    pub response_cache: ResponseCache,
    /// Required production Redis cache; optional only in injected test states.
    pub place_cache: Option<RedisPlaceCache>,
    pub places: Arc<dyn Places>,
    pub spotify: Arc<dyn Spotify>,
    /// Required serving Postgres pool. `None` only in injected mock test states.
    pub postgres: Option<sqlx::PgPool>,
    /// R2 media uploads; `None` answers `POST /app/v1/uploads` with 503.
    pub media: Option<crate::domain::uploads::MediaUploads>,
}
