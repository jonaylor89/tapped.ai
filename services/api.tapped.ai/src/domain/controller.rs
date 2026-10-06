use std::{collections::HashMap, time::Duration};

use crate::{
    data::search::{UserSearchOptions, UserSearchOptionsBuilder},
    domain::models::user::UserModel,
    errors::AppError,
    state::AppStateDyn,
};
use anyhow::Result;
use axum::{
    Json,
    extract::{Path, Query, State},
};
use futures::future;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use tracing::instrument;

use super::models::user::{GuardedPerformer, GuardedVenue};

#[derive(Debug, Deserialize, Serialize, JsonSchema)]
pub struct SearchParams {
    /// Free-text query matched against performer names, usernames and bios.
    query: Option<String>,
}

#[derive(Debug, Deserialize, JsonSchema)]
pub struct PerformerIdPath {
    /// The performer's user ID.
    id: String,
}

#[derive(Debug, Deserialize, JsonSchema)]
pub struct UsernamePath {
    /// The performer's username, without `@`.
    username: String,
}

#[derive(Debug, Deserialize, JsonSchema)]
pub struct LatLngPath {
    /// `<lat>,<lng>` in decimal degrees, e.g. `37.5407,-77.4360`.
    latlng: String,
}

fn parse_lat_lng(value: &str) -> Option<(f64, f64)> {
    let (lat, lng) = value.split_once(',')?;
    let lat: f64 = lat.trim().parse().ok()?;
    let lng: f64 = lng.trim().parse().ok()?;
    ((-90.0..=90.0).contains(&lat) && (-180.0..=180.0).contains(&lng)).then_some((lat, lng))
}

fn cached_response<T: Serialize>(
    state: &AppStateDyn,
    key: String,
    value: &T,
    ttl: Duration,
) -> Result<Json<serde_json::Value>, AppError> {
    let value = serde_json::to_value(value)
        .map_err(|error| AppError::internal("failed to serialize response", error))?;
    state.response_cache.insert(key, value.clone(), ttl);
    Ok(Json(value))
}

async fn transform_performer_id(id: String, state: &AppStateDyn) -> Result<GuardedPerformer> {
    let user = state.database.get_user_by_id(&id).await?;

    transform_performer(user, state).await
}

#[instrument(skip(state))]
async fn transform_performer(user: UserModel, state: &AppStateDyn) -> Result<GuardedPerformer> {
    let bookings = state
        .database
        .get_bookings_by_performer_id(&user.id)
        .await?;
    let guarded_bookings = bookings
        .into_iter()
        .map(|booking| booking.to_guarded())
        .collect();

    let reviews = state.database.get_reviews_by_performer_id(&user.id).await?;
    let guarded_reviews = reviews
        .into_iter()
        .map(|review| review.to_guarded())
        .collect();

    Ok(user.to_guarded_performer(guarded_bookings, guarded_reviews))
}

#[instrument(skip(state))]
async fn transform_venue(user: UserModel, state: &AppStateDyn) -> Result<GuardedVenue> {
    let bookings = state
        .database
        .get_bookings_by_booker_id(&user.id)
        .await
        .inspect_err(|e| tracing::error!("failed to get bookings: {:?}", e))
        .unwrap_or_default();
    let guarded_bookings = bookings
        .into_iter()
        .map(|booking| booking.to_guarded())
        .collect();

    let reviews = state
        .database
        .get_reviews_by_booker_id(&user.id)
        .await
        .inspect_err(|e| tracing::error!("failed to get reviews: {:?}", e))
        .unwrap_or_default();
    let guarded_reviews = reviews
        .into_iter()
        .map(|review| review.to_guarded())
        .collect();

    let guarded_venue = user.to_guarded_venue(guarded_bookings, guarded_reviews);

    Ok(guarded_venue)
}

pub async fn search_performers(
    State(state): State<AppStateDyn>,
    Query(params): Query<SearchParams>,
) -> Result<Json<serde_json::Value>, AppError> {
    tracing::info!("searching users with {:?}", params);
    let query = params.query.unwrap_or_default();
    let cache_key = format!("performer-search:{}", query.trim().to_lowercase());
    if let Some(value) = state.response_cache.get(&cache_key) {
        return Ok(Json(value));
    }
    let users = state
        .search
        .search_users(query, UserSearchOptions::default())
        .await
        .map_err(|error| AppError::upstream("search", error))?;

    let guarded_performers = future::try_join_all(
        users
            .into_iter()
            .map(|user| transform_performer(user, &state)),
    )
    .await
    .map_err(|error| AppError::internal("failed to load performers", error))?;

    cached_response(
        &state,
        cache_key,
        &guarded_performers,
        Duration::from_secs(60),
    )
}

pub async fn get_performer_username(
    State(state): State<AppStateDyn>,
    Path(UsernamePath { username }): Path<UsernamePath>,
) -> Result<Json<serde_json::Value>, AppError> {
    let cache_key = format!("performer-username:{}", username.to_lowercase());
    if let Some(value) = state.response_cache.get(&cache_key) {
        return Ok(Json(value));
    }
    let user = state
        .database
        .get_user_by_username(&username)
        .await
        .map_err(|error| {
            tracing::debug!("performer lookup failed: {error:#}");
            AppError::not_found(format!("no performer with username '{username}'"))
        })?;

    let guarded_performer = transform_performer(user, &state)
        .await
        .map_err(|error| AppError::internal("failed to load performer", error))?;

    cached_response(
        &state,
        cache_key,
        &guarded_performer,
        Duration::from_secs(300),
    )
}

pub async fn get_performer(
    State(state): State<AppStateDyn>,
    Path(PerformerIdPath { id }): Path<PerformerIdPath>,
) -> Result<Json<serde_json::Value>, AppError> {
    let cache_key = format!("performer-id:{id}");
    if let Some(value) = state.response_cache.get(&cache_key) {
        return Ok(Json(value));
    }
    let user = state.database.get_user_by_id(&id).await.map_err(|error| {
        tracing::debug!("performer lookup failed: {error:#}");
        AppError::not_found(format!("no performer with id '{id}'"))
    })?;

    let bookings = state
        .database
        .get_bookings_by_performer_id(&id)
        .await
        .map_err(|error| AppError::internal("failed to load performer", error))?;

    let guarded_bookings = bookings
        .into_iter()
        .map(|booking| booking.to_guarded())
        .collect();

    let reviews = state
        .database
        .get_reviews_by_performer_id(&id)
        .await
        .map_err(|error| AppError::internal("failed to load performer", error))?;

    let guarded_reviews = reviews
        .into_iter()
        .map(|review| review.to_guarded())
        .collect();

    let guarded_user = user.to_guarded_performer(guarded_bookings, guarded_reviews);

    cached_response(&state, cache_key, &guarded_user, Duration::from_secs(300))
}

#[derive(Debug, Deserialize, Serialize, JsonSchema)]
pub struct LocationResponse {
    pub venues: Vec<GuardedVenue>,
    pub top_performers: Vec<GuardedPerformer>,
    pub genres: HashMap<String, f64>,
}

pub async fn get_location(
    State(state): State<AppStateDyn>,
    Path(LatLngPath { latlng }): Path<LatLngPath>,
) -> Result<Json<serde_json::Value>, AppError> {
    let (lat, lng) = parse_lat_lng(&latlng).ok_or_else(|| {
        AppError::bad_request("expected `<lat>,<lng>` in decimal degrees, e.g. 37.5407,-77.4360")
    })?;
    let cache_key = format!("location:{lat:.4},{lng:.4}");
    if let Some(value) = state.response_cache.get(&cache_key) {
        return Ok(Json(value));
    }

    let options = UserSearchOptionsBuilder::default()
        .lat(Some(lat))
        .lng(Some(lng))
        .radius(Some(100_000))
        .build()
        .map_err(|e| AppError::internal("failed to build search options", e))?;
    let venues: Vec<UserModel> = state
        .search
        .search_users(" ".into(), options)
        .await
        .map_err(|e| AppError::upstream("search", e))?;

    tracing::info!("found {} venues", venues.len());

    let guarded_venues = future::try_join_all(
        venues
            .into_iter()
            .map(|venue| transform_venue(venue, &state)),
    )
    .await
    .map_err(|e| AppError::internal("failed to load venues", e))?;

    let top_guarded_performers = future::try_join_all(
        guarded_venues
            .iter()
            .flat_map(|venue| venue.top_performer_ids.clone())
            .map(|id| transform_performer_id(id, &state)),
    )
    .await
    .map_err(|e| AppError::internal("failed to load top performers", e))?;

    tracing::info!("found {} performers", top_guarded_performers.len());

    let genres = guarded_venues
        .iter()
        .flat_map(|venue| venue.genres.iter().map(|genre| genre.to_string()))
        .collect::<Vec<String>>();
    let genre_count = genres.len();

    let genre_map = genres.into_iter().fold(HashMap::new(), |mut acc, genre| {
        acc.entry(genre)
            .and_modify(|count| *count += 1)
            .or_insert(1);
        acc
    });

    let normalized_genres: HashMap<String, f64> = genre_map
        .into_iter()
        .map(|(genre, count)| (genre, count as f64 / genre_count as f64))
        .collect();

    let res = LocationResponse {
        venues: guarded_venues,
        top_performers: top_guarded_performers,
        genres: normalized_genres,
    };

    cached_response(&state, cache_key, &res, Duration::from_secs(300))
}

#[cfg(test)]
mod tests {
    use super::parse_lat_lng;

    #[test]
    fn parses_lat_lng_pairs() {
        assert_eq!(parse_lat_lng("37.5407,-77.4360"), Some((37.5407, -77.4360)));
        assert_eq!(parse_lat_lng(" 0 , 0 "), Some((0.0, 0.0)));
    }

    #[test]
    fn rejects_malformed_lat_lng() {
        for value in [
            "", "abc", "37.5", "37.5,", ",1", "1,2,3", "91,0", "0,181", "NaN,0",
        ] {
            assert_eq!(parse_lat_lng(value), None, "{value}");
        }
    }
}
