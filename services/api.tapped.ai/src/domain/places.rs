//! Google Places proxy for the apps. Clients never hold a Places key: every request goes through
//! the process-local response cache, then the Firestore `googlePlacesCache` collection (place
//! details only), and only then to Google, which bills per request.
//!
//! Place details and autocomplete are public (the web app has no signed-in user); photos and
//! reverse geocoding require Firebase auth. Google spend is bounded by the daily quota caps on
//! the Places API project.

use std::time::Duration;

use axum::{
    Json,
    extract::{Path, Query, State},
};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize, de::DeserializeOwned};

use crate::{
    data::places::{AutocompletePrediction, PlaceDetails},
    domain::firebase_auth::FirebaseUser,
    errors::AppError,
    state::AppStateDyn,
};

const AUTOCOMPLETE_TTL: Duration = Duration::from_secs(6 * 60 * 60);
const PLACE_TTL: Duration = Duration::from_secs(24 * 60 * 60);
const MISSING_PLACE_TTL: Duration = Duration::from_secs(60 * 60);
// Photo URIs returned by Google are short-lived.
const PHOTO_TTL: Duration = Duration::from_secs(30 * 60);
const REVERSE_GEOCODE_TTL: Duration = Duration::from_secs(24 * 60 * 60);

const MAX_QUERY_LEN: usize = 200;
// Google allows at most five `includedPrimaryTypes`.
const MAX_AUTOCOMPLETE_TYPES: usize = 5;
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

fn upstream_error(error: anyhow::Error) -> AppError {
    AppError::upstream("Google Places", error)
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

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct AutocompleteParams {
    query: String,
    /// Comma-separated primary types, e.g. `locality` or `(cities)`.
    types: Option<String>,
    session_token: Option<String>,
}

fn parse_types(types: Option<&str>) -> Option<Vec<String>> {
    let mut types: Vec<String> = types
        .unwrap_or_default()
        .split(',')
        .map(str::trim)
        .filter(|t| !t.is_empty())
        .map(str::to_owned)
        .collect();
    let valid = types.len() <= MAX_AUTOCOMPLETE_TYPES
        && types.iter().all(|t| {
            t.len() <= 64
                && t.chars()
                    .all(|c| c.is_ascii_lowercase() || matches!(c, '_' | '(' | ')'))
        });
    types.sort();
    valid.then_some(types)
}

pub async fn autocomplete_places(
    State(state): State<AppStateDyn>,
    Query(params): Query<AutocompleteParams>,
) -> Result<Json<Vec<AutocompletePrediction>>, AppError> {
    let query = normalize_query(&params.query);
    if query.is_empty() {
        return Ok(Json(vec![]));
    }
    if query.len() > MAX_QUERY_LEN {
        return Err(AppError::bad_request(format!(
            "query must be at most {MAX_QUERY_LEN} characters"
        )));
    }
    let types = parse_types(params.types.as_deref()).ok_or_else(|| {
        AppError::bad_request(format!(
            "types must be at most {MAX_AUTOCOMPLETE_TYPES} comma-separated Google place types"
        ))
    })?;

    let cache_key = format!("places-autocomplete:{}|{query}", types.join(","));
    if let Some(predictions) = cached(&state, &cache_key) {
        return Ok(Json(predictions));
    }

    let predictions = state
        .places
        .autocomplete(&query, &types, params.session_token.as_deref())
        .await
        .map_err(upstream_error)?;
    store(&state, cache_key, &predictions, AUTOCOMPLETE_TTL);

    Ok(Json(predictions))
}

#[derive(Debug, Deserialize, JsonSchema)]
pub struct PlaceIdPath {
    /// A Google place ID.
    place_id: String,
}

fn place_not_found() -> AppError {
    AppError::not_found("place not found")
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct PlaceParams {
    session_token: Option<String>,
}

pub async fn get_place(
    State(state): State<AppStateDyn>,
    Path(PlaceIdPath { place_id }): Path<PlaceIdPath>,
    Query(params): Query<PlaceParams>,
) -> Result<Json<PlaceDetails>, AppError> {
    place_details(&state, &place_id, params.session_token.as_deref())
        .await
        .map(Json)
}

/// Process cache, then Firestore `googlePlacesCache`, then Google.
async fn place_details(
    state: &AppStateDyn,
    place_id: &str,
    session_token: Option<&str>,
) -> Result<PlaceDetails, AppError> {
    if !is_safe_path(place_id) || place_id.contains('/') {
        return Err(AppError::bad_request("invalid place ID"));
    }

    let cache_key = format!("place:{place_id}");
    if let Some(place) = cached::<Option<PlaceDetails>>(state, &cache_key) {
        return place.ok_or_else(place_not_found);
    }

    let stored = match state.database.get_cached_place(place_id).await {
        Ok(stored) => stored,
        Err(error) => {
            tracing::warn!("failed to read googlePlacesCache/{place_id}: {error:#}");
            None
        }
    };
    if let Some(place) = stored.as_ref().filter(|place| !place.is_legacy()) {
        store(state, cache_key, &Some(place), PLACE_TTL);
        return Ok(place.clone());
    }

    let fetched = match state.places.place_details(place_id, session_token).await {
        Ok(fetched) => fetched,
        // A legacy document is still better than nothing.
        Err(error) => match stored {
            Some(place) => {
                tracing::error!("google places request failed: {error:#}");
                return Ok(place);
            }
            None => return Err(upstream_error(error)),
        },
    };

    let Some(mut place) = fetched else {
        store(state, cache_key, &None::<PlaceDetails>, MISSING_PLACE_TTL);
        return Err(place_not_found());
    };
    // Google may return a refreshed ID; keep the document keyed by the ID clients store.
    place.place_id = place_id.to_owned();
    place.geohash = stored.and_then(|stored| stored.geohash);
    if let Err(error) = state.database.set_cached_place(&place).await {
        tracing::warn!("failed to write googlePlacesCache/{place_id}: {error:#}");
    }
    store(state, cache_key, &Some(&place), PLACE_TTL);

    Ok(place)
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct PhotoParams {
    name: String,
    max_height_px: Option<u32>,
}

#[derive(Debug, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct PhotoResponse {
    photo_uri: Option<String>,
}

pub async fn get_place_photo(
    State(state): State<AppStateDyn>,
    _user: FirebaseUser,
    Query(params): Query<PhotoParams>,
) -> Result<Json<PhotoResponse>, AppError> {
    if !is_safe_path(&params.name)
        || !params.name.starts_with("places/")
        || !params.name.contains("/photos/")
    {
        return Err(AppError::bad_request(
            "name must be a Google photo resource name: places/<id>/photos/<id>",
        ));
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

#[derive(Debug, Deserialize, JsonSchema)]
pub struct ReverseGeocodeParams {
    pub lat: f64,
    pub lng: f64,
}

#[derive(Debug, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ReverseGeocodeResponse {
    place_id: Option<String>,
}

/// Locality place ID for a coordinate. Coordinates are rounded to ~100m for caching.
pub async fn reverse_geocode(
    State(state): State<AppStateDyn>,
    _user: FirebaseUser,
    Query(params): Query<ReverseGeocodeParams>,
) -> Result<Json<ReverseGeocodeResponse>, AppError> {
    Ok(Json(ReverseGeocodeResponse {
        place_id: locality_place_id(&state, &params).await?,
    }))
}

/// Locality place details for a coordinate: `reverse-geocode` and `places/{placeId}` in one
/// request, so the app makes a single round trip.
pub async fn get_locality_place(
    State(state): State<AppStateDyn>,
    _user: FirebaseUser,
    Query(params): Query<ReverseGeocodeParams>,
) -> Result<Json<PlaceDetails>, AppError> {
    let place_id = locality_place_id(&state, &params)
        .await?
        .ok_or_else(place_not_found)?;
    place_details(&state, &place_id, None).await.map(Json)
}

async fn locality_place_id(
    state: &AppStateDyn,
    params: &ReverseGeocodeParams,
) -> Result<Option<String>, AppError> {
    if !(-90.0..=90.0).contains(&params.lat) || !(-180.0..=180.0).contains(&params.lng) {
        return Err(AppError::bad_request(
            "lat must be in [-90, 90] and lng in [-180, 180]",
        ));
    }
    let lat = (params.lat * 1_000.0).round() / 1_000.0;
    let lng = (params.lng * 1_000.0).round() / 1_000.0;

    let cache_key = format!("place-reverse-geocode:{lat:.3},{lng:.3}");
    if let Some(response) = cached::<ReverseGeocodeResponse>(state, &cache_key) {
        return Ok(response.place_id);
    }

    let response = ReverseGeocodeResponse {
        place_id: state
            .places
            .place_id_by_lat_lng(lat, lng)
            .await
            .map_err(upstream_error)?,
    };
    store(state, cache_key, &response, REVERSE_GEOCODE_TTL);

    Ok(response.place_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_queries_for_cache_keys() {
        assert_eq!(normalize_query("  The   Camel\tRVA "), "the camel rva");
    }

    #[test]
    fn parses_autocomplete_types() {
        assert_eq!(parse_types(None), Some(vec![]));
        assert_eq!(
            parse_types(Some("locality, (cities)")),
            Some(vec!["(cities)".to_owned(), "locality".to_owned()])
        );
        assert_eq!(parse_types(Some("locality&key=x")), None);
        assert_eq!(parse_types(Some("a,b,c,d,e,f")), None);
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
