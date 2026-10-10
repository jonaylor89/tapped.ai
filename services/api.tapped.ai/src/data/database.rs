use crate::{
    data::places::PlaceDetails,
    domain::models::{booking::Booking, opportunity::Opportunity, review::Review, user::UserModel},
};
use anyhow::Result;
use axum::async_trait;
use serde_json::{Value, json};

#[derive(Debug, Clone, Default)]
pub struct MockDatabase;

/// Public-document lookups for this ID or username find nothing in [`MockDatabase`].
pub const MOCK_MISSING_ID: &str = "missing";

#[async_trait]
impl Database for MockDatabase {
    async fn get_user_from_api_key(&self, api_key: &str) -> Result<Option<String>> {
        Ok((!api_key.starts_with("invalid")).then(|| "mock-user-id".to_string()))
    }

    async fn get_user_by_id(&self, id: &str) -> Result<UserModel> {
        Ok(UserModel::default_with_id(id.to_string()))
    }

    async fn get_user_by_username(&self, username: &str) -> Result<UserModel> {
        Ok(UserModel::default_with_username(username.to_string()))
    }

    async fn get_opportunity_by_id(&self, id: &str) -> Result<Opportunity> {
        Ok(Opportunity {
            id: id.to_string(),
            ..Default::default()
        })
    }

    async fn get_bookings_by_reference_event_id(
        &self,
        _reference_event_id: &str,
    ) -> Result<Vec<Booking>> {
        Ok(vec![])
    }

    async fn get_bookings_by_performer_id(&self, _performer_id: &str) -> Result<Vec<Booking>> {
        Ok(vec![])
    }

    async fn get_bookings_by_booker_id(&self, _booker_id: &str) -> Result<Vec<Booking>> {
        Ok(vec![])
    }

    async fn get_reviews_by_performer_id(&self, _performer_id: &str) -> Result<Vec<Review>> {
        Ok(vec![])
    }

    async fn get_reviews_by_booker_id(&self, _booker_id: &str) -> Result<Vec<Review>> {
        Ok(vec![])
    }

    async fn get_user_doc_by_username(&self, username: &str) -> Result<Option<Value>> {
        if username == MOCK_MISSING_ID {
            return Ok(None);
        }
        Ok(Some(json!({
            "id": "mock-user-id",
            "username": username,
            "artistName": "Mock Artist",
            "email": "private@example.com",
            "stripeCustomerId": "cus_private",
            "deleted": false,
            "venueInfo": { "capacity": 100, "bookingEmail": "private@example.com" },
            "_firestore_id": "mock-user-id",
        })))
    }

    async fn get_opportunity_doc(&self, id: &str) -> Result<Option<Value>> {
        if id == MOCK_MISSING_ID {
            return Ok(None);
        }
        Ok(Some(json!({
            "id": id,
            "title": "Mock Opportunity",
            "flierUrl": "https://example.com/flier.png",
            "deleted": false,
        })))
    }
}

#[async_trait]
pub trait Database: Send + Sync {
    /// The user ID owning `api_key`, or `None` if the key doesn't exist.
    async fn get_user_from_api_key(&self, api_key: &str) -> Result<Option<String>>;
    /// Cheap round trip used by `/health/ready`.
    async fn ping(&self) -> Result<()> {
        Ok(())
    }
    async fn get_user_by_id(&self, id: &str) -> Result<UserModel>;
    async fn get_user_by_username(&self, username: &str) -> Result<UserModel>;
    async fn get_opportunity_by_id(&self, id: &str) -> Result<Opportunity>;
    async fn get_bookings_by_reference_event_id(
        &self,
        reference_event_id: &str,
    ) -> Result<Vec<Booking>>;
    async fn get_bookings_by_performer_id(&self, performer_id: &str) -> Result<Vec<Booking>>;
    async fn get_bookings_by_booker_id(&self, booker_id: &str) -> Result<Vec<Booking>>;
    async fn get_reviews_by_performer_id(&self, performer_id: &str) -> Result<Vec<Review>>;
    async fn get_reviews_by_booker_id(&self, booker_id: &str) -> Result<Vec<Review>>;

    /// Persistent Google Places cache shared by every client (`googlePlacesCache`).
    async fn get_cached_place(&self, _place_id: &str) -> Result<Option<PlaceDetails>> {
        Ok(None)
    }

    async fn set_cached_place(&self, _place: &PlaceDetails) -> Result<()> {
        Ok(())
    }

    /// The raw `users` document, for public pages that need the web app's `UserModel` shape.
    async fn get_user_doc_by_username(&self, _username: &str) -> Result<Option<Value>> {
        Ok(None)
    }

    /// The raw `opportunities` document.
    async fn get_opportunity_doc(&self, _id: &str) -> Result<Option<Value>> {
        Ok(None)
    }
}
