use std::{collections::HashMap, time::Duration};

use crate::{
    data::search::{UserSearchOptions, UserSearchOptionsBuilder},
    domain::models::user::UserModel,
    state::AppStateDyn,
};
use anyhow::Result;
use axum::{
    Json,
    extract::{Path, Query, State},
    http::StatusCode,
};
use futures::future;
use serde::{Deserialize, Serialize};
use tracing::instrument;

use super::models::user::{GuardedPerformer, GuardedVenue};

#[derive(Debug, Deserialize, Serialize)]
pub struct SearchParams {
    query: Option<String>,
}

fn cached_response<T: Serialize>(
    state: &AppStateDyn,
    key: String,
    value: &T,
    ttl: Duration,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let value = serde_json::to_value(value).map_err(|error| {
        tracing::error!("failed to serialize cached response: {error}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;
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
        .map_err(|e| {
            tracing::error!("failed to get bookings: {:?}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })
        .unwrap_or_default();
    let guarded_bookings = bookings
        .into_iter()
        .map(|booking| booking.to_guarded())
        .collect();

    let reviews = state
        .database
        .get_reviews_by_booker_id(&user.id)
        .await
        .map_err(|e| {
            tracing::error!("failed to get reviews: {:?}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })
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
) -> Result<Json<serde_json::Value>, StatusCode> {
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
        .map_err(|error| {
            tracing::error!("{error}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let guarded_performers = future::try_join_all(
        users
            .into_iter()
            .map(|user| transform_performer(user, &state)),
    )
    .await
    .unwrap();

    cached_response(
        &state,
        cache_key,
        &guarded_performers,
        Duration::from_secs(60),
    )
}

pub async fn get_performer_username(
    State(state): State<AppStateDyn>,
    Path(username): Path<String>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let cache_key = format!("performer-username:{}", username.to_lowercase());
    if let Some(value) = state.response_cache.get(&cache_key) {
        return Ok(Json(value));
    }
    let user = state
        .database
        .get_user_by_username(&username)
        .await
        .map_err(|error| {
            tracing::error!("{error}");
            StatusCode::NOT_FOUND
        })?;

    let guarded_performer = transform_performer(user, &state).await.map_err(|error| {
        tracing::error!("{error}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    cached_response(
        &state,
        cache_key,
        &guarded_performer,
        Duration::from_secs(300),
    )
}

pub async fn get_performer(
    State(state): State<AppStateDyn>,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let cache_key = format!("performer-id:{id}");
    if let Some(value) = state.response_cache.get(&cache_key) {
        return Ok(Json(value));
    }
    let user = state.database.get_user_by_id(&id).await.map_err(|error| {
        tracing::error!("{error}");
        StatusCode::NOT_FOUND
    })?;

    let bookings = state
        .database
        .get_bookings_by_performer_id(&id)
        .await
        .map_err(|error| {
            tracing::error!("{error}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let guarded_bookings = bookings
        .into_iter()
        .map(|booking| booking.to_guarded())
        .collect();

    let reviews = state
        .database
        .get_reviews_by_performer_id(&id)
        .await
        .map_err(|error| {
            tracing::error!("{error}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let guarded_reviews = reviews
        .into_iter()
        .map(|review| review.to_guarded())
        .collect();

    let guarded_user = user.to_guarded_performer(guarded_bookings, guarded_reviews);

    cached_response(&state, cache_key, &guarded_user, Duration::from_secs(300))
}

#[derive(Debug, Deserialize, Serialize)]
pub struct LocationResponse {
    pub venues: Vec<GuardedVenue>,
    pub top_performers: Vec<GuardedPerformer>,
    pub genres: HashMap<String, f64>,
}

pub async fn get_location(
    State(state): State<AppStateDyn>,
    Path(latlng): Path<String>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let mut latlng = latlng.split(",");
    let lat = latlng.next().unwrap();
    let lng = latlng.next().unwrap();

    let lat: f64 = lat.parse().map_err(|_| StatusCode::BAD_REQUEST)?;
    let lng: f64 = lng.parse().map_err(|_| StatusCode::BAD_REQUEST)?;
    let cache_key = format!("location:{lat:.4},{lng:.4}");
    if let Some(value) = state.response_cache.get(&cache_key) {
        return Ok(Json(value));
    }

    let options = UserSearchOptionsBuilder::default()
        .lat(Some(lat))
        .lng(Some(lng))
        .radius(Some(100_000))
        .build()
        .map_err(|e| {
            tracing::error!("failed to build search options: {:?}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    let venues: Vec<UserModel> = state
        .search
        .search_users(" ".into(), options)
        .await
        .map_err(|e| {
            tracing::error!("failed to search users: {:?}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    tracing::info!("found {} venues", venues.len());

    let guarded_venues = future::try_join_all(
        venues
            .into_iter()
            .map(|venue| transform_venue(venue, &state)),
    )
    .await
    .map_err(|e| {
        tracing::error!("failed to transform venues: {:?}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let top_guarded_performers = future::try_join_all(
        guarded_venues
            .iter()
            .flat_map(|venue| venue.top_performer_ids.clone())
            .map(|id| transform_performer_id(id, &state)),
    )
    .await
    .map_err(|e| {
        tracing::error!("failed to get top performers: {:?}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

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
