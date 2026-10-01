//! Google Places proxy for the apps. Clients never hold a Places key: every request goes through
//! the process-local response cache, then the Firestore `googlePlacesCache` collection (place
//! details only), and only then to Google, which bills per request.
//!
//! Place details are public (server-rendered web pages have no user); everything else requires
//! Firebase auth.

use std::time::Duration;

use axum::{
    Json,
    extract::{Path, Query, State},
    http::StatusCode,
};
use serde::{Deserialize, Serialize, de::DeserializeOwned};

use crate::{
    data::places::{AutocompletePrediction, PlaceDetails},
    domain::firebase_auth::FirebaseUser,
    state::AppStateDyn,
};

const AUTOCOMPLETE_TTL: Duration = Duration::from_secs(6 * 60 * 60);
const PLACE_TTL: Duration = Duration::from_secs(24 * 60 * 60);
const MISSING_PLACE_TTL: Duration = Duration::from_secs(60 * 60);
// Photo URIs returned by Google are short-lived.
const PHOTO_TTL: Duration = Duration::from_secs(30 * 60);
const REVERSE_GEOCODE_TTL: Duration = Duration::from_secs(24 * 60 * 60);

const MAX_QUERY_LEN: usize = 200;
const DEFAULT_PHOTO_HEIGHT_PX: u32 = 400;
const MAX_PHOTO_HEIGHT_PX: u32 = 4_800;

fn cached<T: DeserializeOwned>(state: &AppStateDyn, key: &str) -> Option<T> {
    state
        .response_cache
        .get(key)
        .and_then(|value| serde_json::from_value(value).ok())
}

fn store<T: Serialize>(state: &AppStateDyn, key: String, value: &T, ttl: Duration) {
    if let Ok(value) = serde_json::to_value(value) {
        state.response_cache.insert(key, value, ttl);
    }
}

fn upstream_error(error: anyhow::Error) -> StatusCode {
    tracing::error!("google places request failed: {error:#}");
    StatusCode::BAD_GATEWAY
}

fn normalize_query(query: &str) -> String {
    query
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}

/// Place IDs and photo names are interpolated into Google URL paths.
fn is_safe_path(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 1_024
        && !value.contains("..")
        && value
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '/'))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AutocompleteParams {
    query: String,
    session_token: Option<String>,
}

pub async fn autocomplete_places(
    State(state): State<AppStateDyn>,
    _user: FirebaseUser,
    Query(params): Query<AutocompleteParams>,
) -> Result<Json<Vec<AutocompletePrediction>>, StatusCode> {
    let query = normalize_query(&params.query);
    if query.is_empty() {
        return Ok(Json(vec![]));
    }
    if query.len() > MAX_QUERY_LEN {
        return Err(StatusCode::BAD_REQUEST);
    }

    let cache_key = format!("places-autocomplete:{query}");
    if let Some(predictions) = cached(&state, &cache_key) {
        return Ok(Json(predictions));
    }

    let predictions = state
        .places
        .autocomplete(&query, params.session_token.as_deref())
        .await
        .map_err(upstream_error)?;
    store(&state, cache_key, &predictions, AUTOCOMPLETE_TTL);

    Ok(Json(predictions))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlaceParams {
    session_token: Option<String>,
}

pub async fn get_place(
    State(state): State<AppStateDyn>,
    Path(place_id): Path<String>,
    Query(params): Query<PlaceParams>,
) -> Result<Json<PlaceDetails>, StatusCode> {
    if !is_safe_path(&place_id) || place_id.contains('/') {
        return Err(StatusCode::BAD_REQUEST);
    }

    let cache_key = format!("place:{place_id}");
    if let Some(place) = cached::<Option<PlaceDetails>>(&state, &cache_key) {
        return place.map(Json).ok_or(StatusCode::NOT_FOUND);
    }

    let stored = match state.database.get_cached_place(&place_id).await {
        Ok(stored) => stored,
        Err(error) => {
            tracing::warn!("failed to read googlePlacesCache/{place_id}: {error:#}");
            None
        }
    };
    if let Some(place) = stored.as_ref().filter(|place| !place.is_legacy()) {
        store(&state, cache_key, &Some(place), PLACE_TTL);
        return Ok(Json(place.clone()));
    }

    let fetched = match state
        .places
        .place_details(&place_id, params.session_token.as_deref())
        .await
    {
        Ok(fetched) => fetched,
        // A legacy document is still better than nothing.
        Err(error) => match stored {
            Some(place) => {
                tracing::error!("google places request failed: {error:#}");
                return Ok(Json(place));
            }
            None => return Err(upstream_error(error)),
        },
    };

    let Some(mut place) = fetched else {
        store(&state, cache_key, &None::<PlaceDetails>, MISSING_PLACE_TTL);
        return Err(StatusCode::NOT_FOUND);
    };
    // Google may return a refreshed ID; keep the document keyed by the ID clients store.
    place.place_id = place_id.clone();
    place.geohash = stored.and_then(|stored| stored.geohash);
    if let Err(error) = state.database.set_cached_place(&place).await {
        tracing::warn!("failed to write googlePlacesCache/{place_id}: {error:#}");
    }
    store(&state, cache_key, &Some(&place), PLACE_TTL);

    Ok(Json(place))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PhotoParams {
    name: String,
    max_height_px: Option<u32>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PhotoResponse {
    photo_uri: Option<String>,
}

pub async fn get_place_photo(
    State(state): State<AppStateDyn>,
    _user: FirebaseUser,
    Query(params): Query<PhotoParams>,
) -> Result<Json<PhotoResponse>, StatusCode> {
    if !is_safe_path(&params.name)
        || !params.name.starts_with("places/")
        || !params.name.contains("/photos/")
    {
        return Err(StatusCode::BAD_REQUEST);
    }
    let max_height_px = params
        .max_height_px
        .unwrap_or(DEFAULT_PHOTO_HEIGHT_PX)
        .clamp(1, MAX_PHOTO_HEIGHT_PX);

    let cache_key = format!("place-photo:{}|{max_height_px}", params.name);
    if let Some(photo) = cached(&state, &cache_key) {
        return Ok(Json(photo));
    }

    let photo = PhotoResponse {
        photo_uri: state
            .places
            .photo_uri(&params.name, max_height_px)
            .await
            .map_err(upstream_error)?,
    };
    store(&state, cache_key, &photo, PHOTO_TTL);

    Ok(Json(photo))
}

#[derive(Debug, Deserialize)]
pub struct ReverseGeocodeParams {
    lat: f64,
    lng: f64,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReverseGeocodeResponse {
    place_id: Option<String>,
}

/// Locality place ID for a coordinate. Coordinates are rounded to ~100m for caching.
pub async fn reverse_geocode(
    State(state): State<AppStateDyn>,
    _user: FirebaseUser,
    Query(params): Query<ReverseGeocodeParams>,
) -> Result<Json<ReverseGeocodeResponse>, StatusCode> {
    if !(-90.0..=90.0).contains(&params.lat) || !(-180.0..=180.0).contains(&params.lng) {
        return Err(StatusCode::BAD_REQUEST);
    }
    let lat = (params.lat * 1_000.0).round() / 1_000.0;
    let lng = (params.lng * 1_000.0).round() / 1_000.0;

    let cache_key = format!("place-reverse-geocode:{lat:.3},{lng:.3}");
    if let Some(response) = cached(&state, &cache_key) {
        return Ok(Json(response));
    }

    let response = ReverseGeocodeResponse {
        place_id: state
            .places
            .place_id_by_lat_lng(lat, lng)
            .await
            .map_err(upstream_error)?,
    };
    store(&state, cache_key, &response, REVERSE_GEOCODE_TTL);

    Ok(Json(response))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_queries_for_cache_keys() {
        assert_eq!(normalize_query("  The   Camel\tRVA "), "the camel rva");
    }

    #[test]
    fn rejects_unsafe_place_paths() {
        assert!(is_safe_path("ChIJ--BFpguaEYgR-ty4yeQyDiQ"));
        assert!(is_safe_path("places/ChIJ123/photos/AXCi2Q_abc"));
        assert!(!is_safe_path("places/../../v1/foo"));
        assert!(!is_safe_path("ChIJ?key=abc"));
        assert!(!is_safe_path(""));
    }
}
