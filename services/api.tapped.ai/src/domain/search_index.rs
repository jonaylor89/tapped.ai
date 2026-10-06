//! User search indexing. Firestore `users/{uid}` is the source of truth; this keeps the Typesense
//! `users` collection in step with it. Documents are flattened the way the original Firestore to
//! Typesense import stored them (`performerInfo.label`, `location.placeId`, ...), with `location`
//! as a `[lat, lng]` geopoint so the existing `query_by` fields and geo filters keep working.

use std::{collections::HashSet, ops::AddAssign, sync::Arc, time::Duration};

use anyhow::Result;
use axum::{Json, extract::State};
use chrono::{DateTime, SecondsFormat, TimeDelta, Utc};
use futures::StreamExt;
use schemars::JsonSchema;
use serde::Serialize;
use serde_json::{Map, Value, json};

use crate::{
    data::{database::Database, search::Search},
    domain::{
        firebase_auth::FirebaseUser,
        public_docs::{PRIVATE_USER_FIELD_PREFIXES, PRIVATE_USER_FIELDS},
    },
    errors::AppError,
    state::AppStateDyn,
};

const BATCH_SIZE: usize = 250;
/// Re-scans a little before the previous run so clock skew can't skip a sign-up.
const RECONCILE_OVERLAP: TimeDelta = TimeDelta::minutes(2);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub enum UserIndexStatus {
    /// The user's search document was upserted.
    Indexed,
    /// The user is missing, deleted, or shadow-banned, so any search document was removed.
    Removed,
}

#[derive(Debug, Serialize, JsonSchema)]
pub struct SyncUserResponse {
    pub status: UserIndexStatus,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct SyncStats {
    pub indexed: usize,
    pub removed: usize,
    pub rejected: usize,
}

impl AddAssign for SyncStats {
    fn add_assign(&mut self, other: Self) {
        self.indexed += other.indexed;
        self.removed += other.removed;
        self.rejected += other.rejected;
    }
}

/// Re-indexes the signed-in user from `users/{uid}`. The UID comes from the Firebase ID token.
pub async fn sync_current_user(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
) -> Result<Json<SyncUserResponse>, AppError> {
    let status = sync_user(state.database.as_ref(), state.search.as_ref(), &user.uid)
        .await
        .map_err(|error| AppError::upstream("search index", error))?;
    Ok(Json(SyncUserResponse { status }))
}

pub async fn sync_user(
    database: &dyn Database,
    search: &dyn Search,
    id: &str,
) -> Result<UserIndexStatus> {
    match database
        .get_user_doc(id)
        .await?
        .and_then(user_search_document)
    {
        Some(document) => {
            let rejected = search.upsert_users(vec![document]).await?;
            anyhow::ensure!(rejected == 0, "Typesense rejected the user document");
            Ok(UserIndexStatus::Indexed)
        }
        None => {
            search.delete_user(id).await?;
            Ok(UserIndexStatus::Removed)
        }
    }
}

/// Indexes users whose `timestamp` (sign-up time) is at or after `since`.
pub async fn sync_users_created_since(
    database: &dyn Database,
    search: &dyn Search,
    since: DateTime<Utc>,
) -> Result<SyncStats> {
    let docs = database.get_user_docs_created_since(since).await?;
    let mut stats = SyncStats::default();
    let mut docs = docs.into_iter().peekable();
    while docs.peek().is_some() {
        stats += sync_user_docs(search, docs.by_ref().take(BATCH_SIZE).collect()).await?;
    }
    Ok(stats)
}

/// Re-indexes every Firestore user. With `prune`, also removes search documents whose Firestore
/// user no longer exists.
pub async fn sync_all_users(
    database: &dyn Database,
    search: &dyn Search,
    prune: bool,
) -> Result<SyncStats> {
    let mut docs = database.stream_user_docs().await?;
    let mut seen = HashSet::new();
    let mut batch = Vec::with_capacity(BATCH_SIZE);
    let mut stats = SyncStats::default();
    while let Some(doc) = docs.next().await {
        let doc = doc?;
        if let Some(id) = doc_id(&doc) {
            seen.insert(id.to_owned());
        }
        batch.push(doc);
        if batch.len() == BATCH_SIZE {
            stats += sync_user_docs(search, std::mem::take(&mut batch)).await?;
            tracing::info!(seen = seen.len(), ?stats, "user search sync progress");
        }
    }
    stats += sync_user_docs(search, batch).await?;

    if prune {
        anyhow::ensure!(
            !seen.is_empty(),
            "refusing to prune: Firestore returned no users"
        );
        for id in search.list_user_ids().await? {
            if !seen.contains(&id) {
                search.delete_user(&id).await?;
                stats.removed += 1;
            }
        }
    }
    Ok(stats)
}

async fn sync_user_docs(search: &dyn Search, docs: Vec<Value>) -> Result<SyncStats> {
    let mut stats = SyncStats::default();
    let mut documents = Vec::with_capacity(docs.len());
    for doc in docs {
        let id = doc_id(&doc).map(str::to_owned);
        match (user_search_document(doc), id) {
            (Some(document), _) => documents.push(document),
            (None, Some(id)) => {
                search.delete_user(&id).await?;
                stats.removed += 1;
            }
            (None, None) => {}
        }
    }
    let count = documents.len();
    let rejected = search.upsert_users(documents).await?;
    stats.indexed += count - rejected;
    stats.rejected += rejected;
    Ok(stats)
}

/// Polls for sign-ups so users from app builds that never call `/app/v1/search/users/sync` (or
/// whose call failed) still become searchable. Profile edits rely on the sync call and backfill.
pub fn spawn_new_user_reconciler(
    database: Arc<dyn Database>,
    search: Arc<dyn Search>,
    interval: Duration,
    lookback: TimeDelta,
) {
    tokio::spawn(async move {
        let mut since = Utc::now() - lookback;
        let mut ticker = tokio::time::interval(interval);
        ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        loop {
            ticker.tick().await;
            let started = Utc::now();
            match sync_users_created_since(database.as_ref(), search.as_ref(), since).await {
                Ok(stats) => {
                    if stats != SyncStats::default() {
                        tracing::info!(?stats, %since, "indexed new users");
                    }
                    since = started - RECONCILE_OVERLAP;
                }
                Err(error) => tracing::error!(error = %error, "new-user search sync failed"),
            }
        }
    });
}

fn doc_id(doc: &Value) -> Option<&str> {
    doc.get("_firestore_id")
        .or_else(|| doc.get("id"))
        .and_then(Value::as_str)
        .filter(|id| !id.is_empty())
}

fn flag(doc: &Map<String, Value>, key: &str) -> bool {
    doc.get(key).and_then(Value::as_bool).unwrap_or(false)
}

/// `email` stays: existing documents have it and `UserModel` (partner API search) requires it.
fn is_private(key: &str) -> bool {
    key != "email"
        && (PRIVATE_USER_FIELDS.contains(&key)
            || PRIVATE_USER_FIELD_PREFIXES
                .iter()
                .any(|prefix| key.starts_with(prefix)))
}

/// The Typesense document for a raw `users` document, or `None` if the user shouldn't be
/// searchable (deleted or shadow-banned).
pub fn user_search_document(doc: Value) -> Option<Value> {
    let Value::Object(doc) = doc else {
        return None;
    };
    if flag(&doc, "deleted") || flag(&doc, "shadowBanned") {
        return None;
    }
    let id = doc_id(&Value::Object(doc.clone()))?.to_owned();

    let mut out = Map::new();
    for (key, value) in doc {
        if key.starts_with("_firestore") || is_private(&key) {
            continue;
        }
        flatten_into(&mut out, key, value);
    }

    let geopoint = match (
        out.get("location.lat").and_then(Value::as_f64),
        out.get("location.lng").and_then(Value::as_f64),
    ) {
        (Some(lat), Some(lng)) => Some(json!([lat, lng])),
        _ => None,
    };
    match geopoint {
        Some(point) => out.insert("location".into(), point),
        None => out.remove("location"),
    };

    out.insert("id".into(), Value::String(id));
    for (field, default) in [
        ("username", json!("")),
        ("artistName", json!("")),
        ("bio", json!("")),
        ("occupations", json!([])),
        ("deleted", json!(false)),
        ("unclaimed", json!(false)),
    ] {
        out.entry(field).or_insert(default);
    }
    Some(Value::Object(out))
}

fn flatten_into(out: &mut Map<String, Value>, key: String, value: Value) {
    match value {
        Value::Null => {}
        Value::Object(map) => {
            for (child, value) in map {
                flatten_into(out, format!("{key}.{child}"), value);
            }
        }
        // Typesense can't index arrays of objects without nested fields.
        Value::Array(items) if items.iter().any(|item| item.is_object() || item.is_array()) => {}
        Value::Array(items) => {
            out.insert(
                key,
                Value::Array(items.into_iter().filter(|item| !item.is_null()).collect()),
            );
        }
        Value::String(text) => {
            out.insert(key, Value::String(normalize_timestamp(text)));
        }
        value => {
            out.insert(key, value);
        }
    }
}

/// Firestore timestamps decode as RFC 3339 strings; existing documents use `...T04:24:41.634Z`.
fn normalize_timestamp(text: String) -> String {
    match DateTime::parse_from_rfc3339(&text) {
        Ok(time) => time
            .with_timezone(&Utc)
            .to_rfc3339_opts(SecondsFormat::Millis, true),
        Err(_) => text,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::data::{database::MockDatabase, search::UserSearchOptions};
    use crate::domain::models::user::UserModel;
    use axum::async_trait;
    use std::sync::Mutex;

    #[derive(Default)]
    struct RecordingSearch {
        upserts: Mutex<Vec<Value>>,
        deletes: Mutex<Vec<String>>,
        indexed_ids: Vec<String>,
    }

    #[async_trait]
    impl Search for RecordingSearch {
        async fn search_users(&self, _: String, _: UserSearchOptions) -> Result<Vec<UserModel>> {
            Ok(vec![])
        }

        async fn upsert_users(&self, documents: Vec<Value>) -> Result<usize> {
            self.upserts.lock().unwrap().extend(documents);
            Ok(0)
        }

        async fn delete_user(&self, id: &str) -> Result<()> {
            self.deletes.lock().unwrap().push(id.to_owned());
            Ok(())
        }

        async fn list_user_ids(&self) -> Result<Vec<String>> {
            Ok(self.indexed_ids.clone())
        }
    }

    #[test]
    fn flattens_users_like_the_existing_index() {
        let document = user_search_document(json!({
            "_firestore_id": "u1",
            "_firestore_updated": "2026-10-06T16:33:00Z",
            "id": "u1",
            "username": "dj_nova",
            "artistName": "DJ Nova",
            "email": "nova@example.com",
            "stripeCustomerId": "cus_1",
            "phoneNumber": "+1555",
            "pushNotifications": { "directMessages": true },
            "deleted": false,
            "timestamp": "2026-10-06T16:33:00.5+00:00",
            "occupations": ["DJ"],
            "location": { "placeId": "place-1", "lat": 40.71, "lng": -74.0 },
            "performerInfo": { "label": "Independent", "genres": ["house", null], "rating": 5 },
            "venueInfo": { "type": "club", "photos": [{ "url": "x" }] },
            "profilePicture": null,
        }))
        .unwrap();

        assert_eq!(
            document,
            json!({
                "id": "u1",
                "username": "dj_nova",
                "artistName": "DJ Nova",
                "bio": "",
                "email": "nova@example.com",
                "deleted": false,
                "unclaimed": false,
                "timestamp": "2026-10-06T16:33:00.500Z",
                "occupations": ["DJ"],
                "location": [40.71, -74.0],
                "location.placeId": "place-1",
                "location.lat": 40.71,
                "location.lng": -74.0,
                "performerInfo.label": "Independent",
                "performerInfo.genres": ["house"],
                "performerInfo.rating": 5,
                "venueInfo.type": "club",
            })
        );
    }

    #[test]
    fn drops_locations_without_coordinates() {
        let document =
            user_search_document(json!({ "id": "u1", "location": { "placeId": "p" } })).unwrap();
        assert!(document.get("location").is_none());
        assert_eq!(document["location.placeId"], "p");
    }

    #[test]
    fn skips_hidden_users() {
        assert_eq!(
            user_search_document(json!({ "id": "u1", "deleted": true })),
            None
        );
        assert_eq!(
            user_search_document(json!({ "id": "u1", "shadowBanned": true })),
            None
        );
        assert_eq!(user_search_document(json!({ "username": "no-id" })), None);
    }

    #[tokio::test]
    async fn sync_user_upserts_or_removes() {
        let search = RecordingSearch::default();

        let status = sync_user(&MockDatabase, &search, "u1").await.unwrap();
        assert_eq!(status, UserIndexStatus::Indexed);
        let upserts = search.upserts.lock().unwrap().clone();
        assert_eq!(upserts.len(), 1);
        assert_eq!(upserts[0]["id"], "u1");
        assert_eq!(upserts[0]["location"], json!([40.7128, -74.006]));
        assert!(upserts[0].get("stripeCustomerId").is_none());

        for id in ["deleted-user", "missing-user"] {
            let status = sync_user(&MockDatabase, &search, id).await.unwrap();
            assert_eq!(status, UserIndexStatus::Removed);
        }
        assert_eq!(
            *search.deletes.lock().unwrap(),
            vec!["deleted-user".to_owned(), "missing-user".to_owned()]
        );
    }

    #[tokio::test]
    async fn prune_refuses_an_empty_firestore() {
        let search = RecordingSearch {
            indexed_ids: vec!["u1".into()],
            ..Default::default()
        };
        assert!(sync_all_users(&MockDatabase, &search, true).await.is_err());
        assert!(search.deletes.lock().unwrap().is_empty());
    }
}
