//! Spotify Web API with app (client-credentials) tokens. Used to prefill onboarding from an
//! artist's Spotify profile and to show their top tracks.

use std::time::{Duration, Instant};

use anyhow::{Result, bail};
use axum::async_trait;
use reqwest::StatusCode;
use serde::Deserialize;
use serde_json::Value;
use tokio::sync::Mutex;
use tracing::instrument;

const TOKEN_URL: &str = "https://accounts.spotify.com/api/token";
const API_BASE_URL: &str = "https://api.spotify.com/v1";
// Refresh app tokens a little before Spotify expires them.
const TOKEN_EXPIRY_MARGIN: Duration = Duration::from_secs(60);

/// Artist and top-track responses are Spotify's JSON, unchanged, so existing clients
/// (`SpotifyArtist`/`SpotifyTrack` in Flutter) keep parsing them.
#[async_trait]
pub trait Spotify: Send + Sync {
    async fn artist(&self, artist_id: &str) -> Result<Option<Value>>;
    async fn top_tracks(&self, artist_id: &str, market: Option<&str>) -> Result<Option<Value>>;
}

#[derive(Debug, Clone, Default)]
pub struct MockSpotify;

pub const MOCK_MISSING_ARTIST_ID: &str = "missing";

#[async_trait]
impl Spotify for MockSpotify {
    async fn artist(&self, artist_id: &str) -> Result<Option<Value>> {
        if artist_id == MOCK_MISSING_ARTIST_ID {
            return Ok(None);
        }
        Ok(Some(serde_json::json!({
            "id": artist_id,
            "uri": format!("spotify:artist:{artist_id}"),
            "name": "Mock Artist",
            "genres": ["indie"],
            "images": [],
        })))
    }

    async fn top_tracks(&self, artist_id: &str, _market: Option<&str>) -> Result<Option<Value>> {
        if artist_id == MOCK_MISSING_ARTIST_ID {
            return Ok(None);
        }
        Ok(Some(serde_json::json!({
            "tracks": [{ "id": "mock-track", "name": "Mock Track" }],
        })))
    }
}

struct AppToken {
    access_token: String,
    expires_at: Instant,
}

pub struct SpotifyHttp {
    client: reqwest::Client,
    client_id: String,
    client_secret: String,
    token: Mutex<Option<AppToken>>,
}

impl std::fmt::Debug for SpotifyHttp {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SpotifyHttp").finish_non_exhaustive()
    }
}

#[derive(Deserialize)]
struct TokenResponse {
    access_token: String,
    expires_in: u64,
}

impl SpotifyHttp {
    pub fn new(client_id: String, client_secret: String) -> Self {
        Self {
            client: crate::http::client(),
            client_id,
            client_secret,
            token: Mutex::new(None),
        }
    }

    async fn access_token(&self) -> Result<String> {
        if self.client_id.is_empty() || self.client_secret.is_empty() {
            bail!("SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET are not configured");
        }
        let mut token = self.token.lock().await;
        if let Some(token) = token.as_ref().filter(|t| t.expires_at > Instant::now()) {
            return Ok(token.access_token.clone());
        }
        let response: TokenResponse = self
            .client
            .post(TOKEN_URL)
            .basic_auth(&self.client_id, Some(&self.client_secret))
            .form(&[("grant_type", "client_credentials")])
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        let access_token = response.access_token.clone();
        *token = Some(AppToken {
            access_token: response.access_token,
            expires_at: Instant::now() + Duration::from_secs(response.expires_in)
                - TOKEN_EXPIRY_MARGIN,
        });
        Ok(access_token)
    }

    /// `None` when Spotify doesn't know the ID (404) or rejects it as malformed (400).
    async fn get(&self, path: &str, query: &[(&str, &str)]) -> Result<Option<Value>> {
        let access_token = self.access_token().await?;
        let response = self
            .client
            .get(format!("{API_BASE_URL}{path}"))
            .bearer_auth(access_token)
            .query(query)
            .send()
            .await?;
        if matches!(
            response.status(),
            StatusCode::NOT_FOUND | StatusCode::BAD_REQUEST
        ) {
            return Ok(None);
        }
        Ok(Some(response.error_for_status()?.json().await?))
    }
}

#[async_trait]
impl Spotify for SpotifyHttp {
    #[instrument(skip(self), fields(dependency = "spotify"))]
    async fn artist(&self, artist_id: &str) -> Result<Option<Value>> {
        self.get(&format!("/artists/{artist_id}"), &[]).await
    }

    #[instrument(skip(self), fields(dependency = "spotify"))]
    async fn top_tracks(&self, artist_id: &str, market: Option<&str>) -> Result<Option<Value>> {
        let query: Vec<(&str, &str)> = market.map(|m| ("market", m)).into_iter().collect();
        self.get(&format!("/artists/{artist_id}/top-tracks"), &query)
            .await
    }
}
