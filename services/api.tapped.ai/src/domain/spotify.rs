//! Spotify lookups for signed-in users (replaces the `getArtistBySpotifyId` and
//! `getTopTracksByArtistId` callables). The Spotify app credentials stay server-side.

use std::time::Duration;

use axum::{
    Json,
    extract::{Path, Query, State},
};
use schemars::JsonSchema;
use serde::Deserialize;
use serde_json::Value;

use crate::{domain::firebase_auth::FirebaseUser, errors::AppError, state::AppStateDyn};

const SPOTIFY_TTL: Duration = Duration::from_secs(60 * 60);

/// Spotify IDs are base62; they are interpolated into Spotify URL paths.
fn is_valid_spotify_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 64 && id.chars().all(|c| c.is_ascii_alphanumeric())
}

/// ISO 3166-1 alpha-2 country code, or `from_token`.
fn is_valid_market(market: &str) -> bool {
    market == "from_token" || (market.len() == 2 && market.chars().all(|c| c.is_ascii_uppercase()))
}

fn upstream_error(error: anyhow::Error) -> AppError {
    AppError::upstream("Spotify", error)
}

#[derive(Debug, Deserialize, JsonSchema)]
pub struct ArtistIdPath {
    /// A Spotify artist ID (base62), e.g. `4Z8W4fKeB5YxbusRsdQVPb`.
    artist_id: String,
}

fn cached_or_none(state: &AppStateDyn, key: &str) -> Option<Value> {
    state.response_cache.get(key)
}

pub async fn get_spotify_artist(
    State(state): State<AppStateDyn>,
    _user: FirebaseUser,
    Path(ArtistIdPath { artist_id }): Path<ArtistIdPath>,
) -> Result<Json<Value>, AppError> {
    if !is_valid_spotify_id(&artist_id) {
        return Err(AppError::bad_request(
            "artist_id must be a Spotify artist ID",
        ));
    }
    let cache_key = format!("spotify-artist:{artist_id}");
    if let Some(artist) = cached_or_none(&state, &cache_key) {
        return Ok(Json(artist));
    }

    let artist = state
        .spotify
        .artist(&artist_id)
        .await
        .map_err(upstream_error)?
        .ok_or_else(|| AppError::not_found("Spotify artist not found"))?;
    state
        .response_cache
        .insert(cache_key, artist.clone(), SPOTIFY_TTL);
    Ok(Json(artist))
}

#[derive(Debug, Deserialize, JsonSchema)]
pub struct TopTracksParams {
    /// ISO 3166-1 alpha-2 country code (e.g. `US`), or `from_token`.
    market: Option<String>,
}

pub async fn get_spotify_artist_top_tracks(
    State(state): State<AppStateDyn>,
    _user: FirebaseUser,
    Path(ArtistIdPath { artist_id }): Path<ArtistIdPath>,
    Query(params): Query<TopTracksParams>,
) -> Result<Json<Value>, AppError> {
    let market = params.market.as_deref();
    if !is_valid_spotify_id(&artist_id) {
        return Err(AppError::bad_request(
            "artist_id must be a Spotify artist ID",
        ));
    }
    if market.is_some_and(|m| !is_valid_market(m)) {
        return Err(AppError::bad_request(
            "market must be an ISO 3166-1 alpha-2 country code or from_token",
        ));
    }
    let cache_key = format!(
        "spotify-top-tracks:{artist_id}:{}",
        market.unwrap_or_default()
    );
    if let Some(tracks) = cached_or_none(&state, &cache_key) {
        return Ok(Json(tracks));
    }

    let tracks = state
        .spotify
        .top_tracks(&artist_id, market)
        .await
        .map_err(upstream_error)?
        .ok_or_else(|| AppError::not_found("Spotify artist not found"))?;
    state
        .response_cache
        .insert(cache_key, tracks.clone(), SPOTIFY_TTL);
    Ok(Json(tracks))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::data::{
        database::MockDatabase,
        places::MockPlaces,
        search::MockSearch,
        spotify::{MOCK_MISSING_ARTIST_ID, MockSpotify},
    };
    use axum::http::StatusCode;
    use std::sync::Arc;

    fn state() -> AppStateDyn {
        AppStateDyn {
            database: Arc::new(MockDatabase),
            search: Arc::new(MockSearch),
            firebase_project_id: "test-project".into(),
            mail: crate::domain::mail_bridge::MailBridge::disabled(),
            response_cache: Default::default(),
            place_cache: None,
            places: Arc::new(MockPlaces),
            spotify: Arc::new(MockSpotify),
            postgres: None,
        }
    }

    fn artist(id: &str) -> Path<ArtistIdPath> {
        Path(ArtistIdPath {
            artist_id: id.into(),
        })
    }

    fn user() -> FirebaseUser {
        FirebaseUser {
            uid: "user-1".into(),
            email: None,
        }
    }

    #[test]
    fn validates_ids_and_markets() {
        assert!(is_valid_spotify_id("4Z8W4fKeB5YxbusRsdQVPb"));
        assert!(!is_valid_spotify_id(""));
        assert!(!is_valid_spotify_id("4Z8W/../me"));
        assert!(!is_valid_spotify_id("abc?market=US"));
        assert!(is_valid_market("US"));
        assert!(is_valid_market("from_token"));
        assert!(!is_valid_market("us"));
        assert!(!is_valid_market("USA"));
    }

    #[tokio::test]
    async fn returns_spotify_artist_json() {
        let Json(artist) =
            get_spotify_artist(State(state()), user(), artist("4Z8W4fKeB5YxbusRsdQVPb"))
                .await
                .unwrap();
        assert_eq!(artist["id"], "4Z8W4fKeB5YxbusRsdQVPb");
        assert_eq!(artist["name"], "Mock Artist");
    }

    #[tokio::test]
    async fn unknown_artist_is_not_found() {
        let result =
            get_spotify_artist(State(state()), user(), artist(MOCK_MISSING_ARTIST_ID)).await;
        assert_eq!(result.unwrap_err().status, StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn returns_top_tracks() {
        let Json(tracks) = get_spotify_artist_top_tracks(
            State(state()),
            user(),
            artist("4Z8W4fKeB5YxbusRsdQVPb"),
            Query(TopTracksParams {
                market: Some("US".into()),
            }),
        )
        .await
        .unwrap();
        assert_eq!(tracks["tracks"][0]["name"], "Mock Track");
    }

    #[tokio::test]
    async fn rejects_invalid_market() {
        let result = get_spotify_artist_top_tracks(
            State(state()),
            user(),
            artist("4Z8W4fKeB5YxbusRsdQVPb"),
            Query(TopTracksParams {
                market: Some("us&x=1".into()),
            }),
        )
        .await;
        assert_eq!(result.unwrap_err().status, StatusCode::BAD_REQUEST);
    }
}
