use anyhow::Result;
use redis::AsyncCommands;

use super::places::PlaceDetails;

/// Shared Google Places cache. Entries are intentionally ephemeral: Google place details can
/// change, while retaining them for three months avoids repeatedly paying for stable locations.
#[derive(Clone, Debug)]
pub struct RedisPlaceCache {
    client: redis::Client,
}

impl RedisPlaceCache {
    pub const TTL_SECONDS: u64 = 90 * 24 * 60 * 60;

    pub fn from_env() -> Result<Option<Self>> {
        let Ok(url) = std::env::var("REDIS_URL") else {
            tracing::warn!("REDIS_URL is not set; using the legacy Firestore Google Places cache");
            return Ok(None);
        };
        Ok(Some(Self {
            client: redis::Client::open(url)?,
        }))
    }

    fn key(place_id: &str) -> String {
        format!("places:details:{place_id}")
    }

    pub async fn get(&self, place_id: &str) -> Result<Option<PlaceDetails>> {
        let mut connection = self.client.get_multiplexed_async_connection().await?;
        let value: Option<String> = connection.get(Self::key(place_id)).await?;
        value
            .map(|value| serde_json::from_str(&value).map_err(Into::into))
            .transpose()
    }

    pub async fn set(&self, place: &PlaceDetails) -> Result<()> {
        let value = serde_json::to_string(place)?;
        let mut connection = self.client.get_multiplexed_async_connection().await?;
        let _: () = connection
            .set_ex(Self::key(&place.place_id), value, Self::TTL_SECONDS)
            .await?;
        Ok(())
    }
}
