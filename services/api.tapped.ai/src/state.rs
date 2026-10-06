use crate::{
    data::{database::Database, places::Places, search::Search, spotify::Spotify},
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
/// additional Firestore and Typesense reads. The short TTLs intentionally limit stale data.
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
    pub mail: MailBridge,
    pub response_cache: ResponseCache,
    pub places: Arc<dyn Places>,
    pub spotify: Arc<dyn Spotify>,
}
