//! Public, unauthenticated reads for the web app's server-rendered pages (profile and
//! opportunity link previews, `/compare`). They replace the legacy `getUserByUsername` and
//! `getOpportunityById` Cloud Functions, which returned whole Firestore documents.
//!
//! Documents keep their Firestore shape (the web app's `UserModel` / `Opportunity`), minus
//! private fields.

use std::time::Duration;

use axum::{
    Json,
    extract::{Path, State},
};
use serde_json::{Map, Value};

use crate::{errors::AppError, state::AppStateDyn};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
pub struct UsernamePath {
    /// The user's username, without `@`.
    username: String,
}

#[derive(Debug, Deserialize, JsonSchema)]
pub struct OpportunityIdPath {
    /// The opportunity document ID.
    opportunity_id: String,
}

const PUBLIC_DOC_TTL: Duration = Duration::from_secs(5 * 60);

/// Top-level `users` fields that must never leave the backend.
pub(crate) const PRIVATE_USER_FIELDS: &[&str] = &[
    "email",
    "phoneNumber",
    "stripeConnectedAccountId",
    "stripeCustomerId",
    "emailNotifications",
    "pushNotifications",
    "aiCredits",
    "airtableId",
    "latestAppVersion",
    "shadowBanned",
    "source",
];
/// Legacy flattened notification settings (`emailNotificationsAppReleases`, ...).
pub(crate) const PRIVATE_USER_FIELD_PREFIXES: &[&str] =
    &["emailNotifications", "pushNotifications"];
const PRIVATE_VENUE_INFO_FIELDS: &[&str] = &["bookingEmail", "phoneNumber"];

fn is_safe_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 128
        && value
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
        && !value.contains("..")
}

fn is_deleted(doc: &Map<String, Value>) -> bool {
    doc.get("deleted").and_then(Value::as_bool).unwrap_or(false)
}

/// Removes metadata the Firestore client adds when decoding into JSON.
fn strip_firestore_metadata(doc: &mut Map<String, Value>) {
    doc.retain(|key, _| !key.starts_with("_firestore"));
}

fn public_user(doc: Value) -> Option<Value> {
    let Value::Object(mut doc) = doc else {
        return None;
    };
    if is_deleted(&doc) {
        return None;
    }
    strip_firestore_metadata(&mut doc);
    doc.retain(|key, _| {
        !PRIVATE_USER_FIELDS.contains(&key.as_str())
            && !PRIVATE_USER_FIELD_PREFIXES
                .iter()
                .any(|prefix| key.starts_with(prefix))
    });
    if let Some(Value::Object(venue_info)) = doc.get_mut("venueInfo") {
        venue_info.retain(|key, _| !PRIVATE_VENUE_INFO_FIELDS.contains(&key.as_str()));
    }
    Some(Value::Object(doc))
}

fn public_opportunity(doc: Value) -> Option<Value> {
    let Value::Object(mut doc) = doc else {
        return None;
    };
    if is_deleted(&doc) {
        return None;
    }
    strip_firestore_metadata(&mut doc);
    Some(Value::Object(doc))
}

async fn cached_doc<F, Fut>(
    state: &AppStateDyn,
    cache_key: String,
    load: F,
) -> Result<Json<Value>, AppError>
where
    F: FnOnce() -> Fut,
    Fut: Future<Output = anyhow::Result<Option<Value>>>,
{
    // `null` caches a miss.
    if let Some(value) = state.response_cache.get(&cache_key) {
        return match value {
            Value::Null => Err(AppError::not_found("not found")),
            value => Ok(Json(value)),
        };
    }

    let doc = load()
        .await
        .map_err(|error| AppError::internal(&format!("failed to load {cache_key}"), error))?;
    let value = doc.unwrap_or(Value::Null);
    state
        .response_cache
        .insert(cache_key, value.clone(), PUBLIC_DOC_TTL);

    match value {
        Value::Null => Err(AppError::not_found("not found")),
        value => Ok(Json(value)),
    }
}

pub async fn get_public_user_by_username(
    State(state): State<AppStateDyn>,
    Path(UsernamePath { username }): Path<UsernamePath>,
) -> Result<Json<Value>, AppError> {
    if !is_safe_id(&username) {
        return Err(AppError::bad_request("invalid ID"));
    }
    let database = state.database.clone();
    cached_doc(&state, format!("public-user:{username}"), || async move {
        Ok(database
            .get_user_doc_by_username(&username)
            .await?
            .and_then(public_user))
    })
    .await
}

pub async fn get_public_opportunity(
    State(state): State<AppStateDyn>,
    Path(OpportunityIdPath { opportunity_id }): Path<OpportunityIdPath>,
) -> Result<Json<Value>, AppError> {
    if !is_safe_id(&opportunity_id) {
        return Err(AppError::bad_request("invalid ID"));
    }
    let database = state.database.clone();
    cached_doc(
        &state,
        format!("public-opportunity:{opportunity_id}"),
        || async move {
            Ok(database
                .get_opportunity_doc(&opportunity_id)
                .await?
                .and_then(public_opportunity))
        },
    )
    .await
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn removes_private_user_fields() {
        let user = public_user(json!({
            "id": "u1",
            "username": "dj_nova",
            "email": "nova@example.com",
            "phoneNumber": "+1555",
            "stripeCustomerId": "cus_1",
            "emailNotificationsAppReleases": true,
            "pushNotifications": { "directMessages": true },
            "venueInfo": { "capacity": 200, "bookingEmail": "book@example.com" },
            "_firestore_id": "u1",
        }))
        .unwrap();

        assert_eq!(
            user,
            json!({
                "id": "u1",
                "username": "dj_nova",
                "venueInfo": { "capacity": 200 },
            })
        );
    }

    #[test]
    fn hides_deleted_documents() {
        assert_eq!(public_user(json!({ "id": "u1", "deleted": true })), None);
        assert_eq!(
            public_opportunity(json!({ "id": "o1", "deleted": true })),
            None
        );
    }

    #[test]
    fn validates_ids() {
        assert!(is_safe_id("noah_kahan"));
        assert!(is_safe_id("2b1f6c3e-opportunity"));
        assert!(!is_safe_id("../users"));
        assert!(!is_safe_id("a/b"));
        assert!(!is_safe_id(""));
    }
}
