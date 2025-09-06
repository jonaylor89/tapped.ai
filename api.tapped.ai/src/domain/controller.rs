use std::collections::HashMap;

use crate::{
    data::search::{UserSearchOptions, UserSearchOptionsBuilder},
    domain::models::user::UserModel,
    state::AppStateDyn,
};
use anyhow::Result;
use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    Json,
};
use futures::future;
use serde::{Deserialize, Serialize};
use tracing::instrument;

use super::models::user::{GuardedPerformer, GuardedVenue};

#[derive(Debug, Deserialize, Serialize)]
pub struct SearchParams {
    query: Option<String>,
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
) -> Result<Json<Vec<GuardedPerformer>>, StatusCode> {
    tracing::info!("searching users with {:?}", params);
    let query = params.query.unwrap_or_default();
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

    Ok(Json(guarded_performers))
}

pub async fn get_performer_username(
    State(state): State<AppStateDyn>,
    Path(username): Path<String>,
) -> Result<Json<GuardedPerformer>, StatusCode> {
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

    Ok(Json(guarded_performer))
}

pub async fn get_performer(
    State(state): State<AppStateDyn>,
    Path(id): Path<String>,
) -> Result<Json<GuardedPerformer>, StatusCode> {
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

    Ok(Json(guarded_user))
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
) -> Result<Json<LocationResponse>, StatusCode> {
    let mut latlng = latlng.split(",");
    let lat = latlng.next().unwrap();
    let lng = latlng.next().unwrap();

    let lat: f64 = lat.parse().map_err(|_| StatusCode::BAD_REQUEST)?;
    let lng: f64 = lng.parse().map_err(|_| StatusCode::BAD_REQUEST)?;

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

    Ok(Json(res))
}
