use crate::{
    data::places::PlaceDetails,
    domain::models::{
        api_key::{ApiKey, hash_api_key},
        booking::Booking,
        opportunity::Opportunity,
        review::Review,
        user::UserModel,
    },
};
use anyhow::Result;
use axum::async_trait;
use firestore::{FirestoreDb, FirestoreResult, struct_path::path};
use futures::{TryStreamExt, stream::BoxStream};
use serde_json::{Value, json};
use tracing::instrument;

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

const GOOGLE_PLACES_CACHE: &str = "googlePlacesCache";
const API_KEYS: &str = "apiKeys";
const READINESS_DOC_ID: &str = "readiness-probe";

#[derive(Debug, Clone)]
pub struct Firestore {
    db: FirestoreDb,
}

impl Firestore {
    pub fn new(db: FirestoreDb) -> Self {
        Self { db }
    }

    async fn api_key_doc(&self, id: &str) -> Result<Option<ApiKey>> {
        Ok(self
            .db
            .fluent()
            .select()
            .by_id_in(API_KEYS)
            .obj()
            .one(id)
            .await?)
    }

    async fn migrate_legacy_api_key(&self, raw: &str, hashed: &str, legacy: ApiKey) -> Result<()> {
        let _: ApiKey = self
            .db
            .fluent()
            .update()
            .in_col(API_KEYS)
            .document_id(hashed)
            .object(&ApiKey {
                key: hashed.to_owned(),
                ..legacy
            })
            .execute()
            .await?;
        self.db
            .fluent()
            .delete()
            .from(API_KEYS)
            .document_id(raw)
            .execute()
            .await?;
        tracing::info!("migrated a legacy API key to its hashed document ID");
        Ok(())
    }
}

#[async_trait]
impl Database for Firestore {
    // The key is a credential: never record it in spans or logs.
    #[instrument(skip_all, fields(dependency = "firestore", otel.kind = "client", db.system.name = "firestore"))]
    async fn get_user_from_api_key(&self, api_key: &str) -> Result<Option<String>> {
        let hashed = hash_api_key(api_key);
        if let Some(doc) = self.api_key_doc(&hashed).await? {
            return Ok(Some(doc.user_id));
        }

        // Legacy keys are stored under the raw key; move them to the hashed ID on first use.
        let Some(legacy) = self.api_key_doc(api_key).await? else {
            return Ok(None);
        };
        let user_id = legacy.user_id.clone();
        if let Err(error) = self.migrate_legacy_api_key(api_key, &hashed, legacy).await {
            tracing::warn!(user_id, "failed to migrate legacy API key: {error:#}");
        }
        Ok(Some(user_id))
    }

    #[instrument(skip_all, fields(dependency = "firestore", otel.kind = "client", db.system.name = "firestore"))]
    async fn ping(&self) -> Result<()> {
        let _: Option<ApiKey> = self
            .db
            .fluent()
            .select()
            .by_id_in(API_KEYS)
            .obj()
            .one(READINESS_DOC_ID)
            .await?;
        Ok(())
    }

    #[instrument(skip(self), fields(dependency = "firestore", otel.kind = "client", db.system.name = "firestore"))]
    async fn get_user_by_id(&self, id: &str) -> Result<UserModel> {
        tracing::info!("getting user by id from Firestore: {}", id);

        let doc: Option<UserModel> = self
            .db
            .fluent()
            .select()
            .by_id_in("users")
            .obj()
            .one(id)
            .await?;

        tracing::info!("user found: {:?}", doc);
        match doc {
            Some(user) => Ok(user),
            None => Err(anyhow::anyhow!("user not found")),
        }
    }

    #[instrument(skip(self), fields(dependency = "firestore", otel.kind = "client", db.system.name = "firestore"))]
    async fn get_user_by_username(&self, username: &str) -> Result<UserModel> {
        tracing::info!("getting user by username from Firestore: '{}'", username);

        let object_stream: BoxStream<FirestoreResult<UserModel>> = self
            .db
            .fluent()
            .select()
            .from("users")
            .filter(|q| q.field(path!(UserModel::username)).eq(username))
            .obj()
            .stream_query_with_errors()
            .await?;

        let as_vec: Vec<UserModel> = object_stream.try_collect().await?;
        tracing::info!("users found: {:?}", as_vec.len());

        match as_vec.into_iter().nth(0) {
            None => Err(anyhow::anyhow!("user not found")),
            Some(user) => Ok(user),
        }
    }

    #[instrument(skip(self), fields(dependency = "firestore", otel.kind = "client", db.system.name = "firestore"))]
    async fn get_opportunity_by_id(&self, id: &str) -> Result<Opportunity> {
        let doc: Option<Opportunity> = self
            .db
            .fluent()
            .select()
            .by_id_in("opportunities")
            .obj()
            .one(id)
            .await?;
        doc.ok_or_else(|| anyhow::anyhow!("opportunity not found"))
    }

    #[instrument(skip(self), fields(dependency = "firestore", otel.kind = "client", db.system.name = "firestore"))]
    async fn get_bookings_by_reference_event_id(
        &self,
        reference_event_id: &str,
    ) -> Result<Vec<Booking>> {
        let object_stream: BoxStream<FirestoreResult<Booking>> = self
            .db
            .fluent()
            .select()
            .from("bookings")
            .filter(|q| q.field("referenceEventId").eq(reference_event_id))
            .obj()
            .stream_query_with_errors()
            .await?;
        Ok(object_stream.try_collect().await?)
    }

    #[instrument(skip(self), fields(dependency = "firestore", otel.kind = "client", db.system.name = "firestore"))]
    async fn get_bookings_by_performer_id(&self, performer_id: &str) -> Result<Vec<Booking>> {
        tracing::info!(
            "getting bookings by performer id from Firestore: '{}'",
            performer_id
        );

        let object_stream: BoxStream<FirestoreResult<Booking>> = self
            .db
            .fluent()
            .select()
            .from("bookings")
            .filter(|q| {
                q.for_all([
                    // q.field(path!(Booking::requestee_id)).eq(performer_id),
                    q.field("requesterId").eq(performer_id),
                    // q.field(path!(Booking::status)).eq(BookingStatus::Confirmed),
                    q.field("status").eq("confirmed"),
                ])
            })
            .obj()
            .stream_query_with_errors()
            .await?;

        let as_vec: Vec<Booking> = object_stream.try_collect().await?;
        tracing::info!("bookings found: {:?}", as_vec.len());

        Ok(as_vec)
    }

    #[instrument(skip(self), fields(dependency = "firestore", otel.kind = "client", db.system.name = "firestore"))]
    async fn get_bookings_by_booker_id(&self, booker_id: &str) -> Result<Vec<Booking>> {
        tracing::info!(
            "getting bookings by booker id from Firestore: '{}'",
            booker_id
        );

        let object_stream: BoxStream<FirestoreResult<Booking>> = self
            .db
            .fluent()
            .select()
            .from("bookings")
            .filter(|q| {
                q.for_all([
                    // q.field(path!(Booking::requester_id)).eq(performer_id),
                    q.field("requesterId").eq(booker_id),
                    // q.field(path!(Booking::status)).eq(BookingStatus::Confirmed),
                    q.field("status").eq("confirmed"),
                ])
            })
            .obj()
            .stream_query_with_errors()
            .await?;

        let as_vec: Vec<Booking> = object_stream.try_collect().await?;
        tracing::info!("bookings found: {:?}", as_vec.len());

        Ok(as_vec)
    }

    #[instrument(skip(self), fields(dependency = "firestore", otel.kind = "client", db.system.name = "firestore"))]
    async fn get_reviews_by_performer_id(&self, performer_id: &str) -> Result<Vec<Review>> {
        tracing::info!(
            "getting reviews by performer id from Firestore: '{}'",
            performer_id
        );

        let object_stream: BoxStream<FirestoreResult<Review>> = self
            .db
            .fluent()
            .select()
            .from("reviews")
            .filter(|q| {
                q.for_all([
                    // q.field(path!(Review::performer_id)).eq(performer_id),
                    q.field("performerId").eq(performer_id),
                    // q.field(path!(Review::review_type)).eq(ReviewType::Performer),
                    q.field("type").eq("performer"),
                ])
            })
            .obj()
            .stream_query_with_errors()
            .await?;

        let as_vec: Vec<Review> = object_stream.try_collect().await?;
        tracing::info!("reviews found: {:?}", as_vec.len());

        Ok(as_vec)
    }

    #[instrument(skip(self), fields(dependency = "firestore", otel.kind = "client", db.system.name = "firestore"))]
    async fn get_reviews_by_booker_id(&self, booker_id: &str) -> Result<Vec<Review>> {
        tracing::info!(
            "getting reviews by booker id from Firestore: '{}'",
            booker_id
        );

        let object_stream: BoxStream<FirestoreResult<Review>> = self
            .db
            .fluent()
            .select()
            .from("reviews")
            .filter(|q| {
                q.for_all([
                    // q.field(path!(Review::booker_id)).eq(booker_id),
                    q.field("bookerId").eq(booker_id),
                    // q.field(path!(Review::review_type)).eq(ReviewType::Booker),
                    q.field("type").eq("booker"),
                ])
            })
            .obj()
            .stream_query_with_errors()
            .await?;

        let as_vec: Vec<Review> = object_stream.try_collect().await?;
        tracing::info!("reviews found: {:?}", as_vec.len());

        Ok(as_vec)
    }

    #[instrument(skip(self), fields(dependency = "firestore", otel.kind = "client", db.system.name = "firestore"))]
    async fn get_cached_place(&self, place_id: &str) -> Result<Option<PlaceDetails>> {
        let doc: Option<PlaceDetails> = self
            .db
            .fluent()
            .select()
            .by_id_in(GOOGLE_PLACES_CACHE)
            .obj()
            .one(place_id)
            .await?;

        Ok(doc)
    }

    #[instrument(skip(self), fields(dependency = "firestore", otel.kind = "client", db.system.name = "firestore"))]
    async fn set_cached_place(&self, place: &PlaceDetails) -> Result<()> {
        let _: PlaceDetails = self
            .db
            .fluent()
            .update()
            .in_col(GOOGLE_PLACES_CACHE)
            .document_id(&place.place_id)
            .object(place)
            .execute()
            .await?;

        Ok(())
    }

    #[instrument(skip(self), fields(dependency = "firestore", otel.kind = "client", db.system.name = "firestore"))]
    async fn get_user_doc_by_username(&self, username: &str) -> Result<Option<Value>> {
        let docs: Vec<Value> = self
            .db
            .fluent()
            .select()
            .from("users")
            .filter(|q| q.field("username").eq(username))
            .limit(1)
            .obj()
            .query()
            .await?;

        Ok(docs.into_iter().next())
    }

    #[instrument(skip(self), fields(dependency = "firestore", otel.kind = "client", db.system.name = "firestore"))]
    async fn get_opportunity_doc(&self, id: &str) -> Result<Option<Value>> {
        let doc: Option<Value> = self
            .db
            .fluent()
            .select()
            .by_id_in("opportunities")
            .obj()
            .one(id)
            .await?;

        Ok(doc)
    }
}
