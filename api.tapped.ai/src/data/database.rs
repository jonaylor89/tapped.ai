use crate::domain::models::{api_key::ApiKey, booking::Booking, review::Review, user::UserModel};
use anyhow::Result;
use axum::async_trait;
use firestore::{FirestoreDb, FirestoreResult, struct_path::path};
use futures::{TryStreamExt, stream::BoxStream};
use tracing::instrument;

#[derive(Debug, Clone, Default)]
pub struct MockDatabase;

#[async_trait]
impl Database for MockDatabase {
    async fn get_user_from_api_key(&self, _api_key: &str) -> Result<String> {
        Ok("mock-user-id".to_string())
    }

    async fn get_user_by_id(&self, id: &str) -> Result<UserModel> {
        Ok(UserModel::default_with_id(id.to_string()))
    }

    async fn get_user_by_username(&self, username: &str) -> Result<UserModel> {
        Ok(UserModel::default_with_username(username.to_string()))
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
}

#[async_trait]
pub trait Database: Send + Sync {
    async fn get_user_from_api_key(&self, api_key: &str) -> Result<String>;
    async fn get_user_by_id(&self, id: &str) -> Result<UserModel>;
    async fn get_user_by_username(&self, username: &str) -> Result<UserModel>;
    async fn get_bookings_by_performer_id(&self, performer_id: &str) -> Result<Vec<Booking>>;
    async fn get_bookings_by_booker_id(&self, booker_id: &str) -> Result<Vec<Booking>>;
    async fn get_reviews_by_performer_id(&self, performer_id: &str) -> Result<Vec<Review>>;
    async fn get_reviews_by_booker_id(&self, booker_id: &str) -> Result<Vec<Review>>;
}

#[derive(Debug, Clone)]
pub struct Firestore {
    db: FirestoreDb,
}

impl Firestore {
    pub fn new(db: FirestoreDb) -> Self {
        Self { db }
    }
}

#[async_trait]
impl Database for Firestore {
    #[instrument]
    async fn get_user_from_api_key(&self, api_key: &str) -> Result<String> {
        tracing::info!("getting user from Firestore by API key: '{}'", api_key);

        let doc: Option<ApiKey> = self
            .db
            .fluent()
            .select()
            .by_id_in("apiKeys")
            .obj()
            .one(api_key)
            .await?;

        match doc {
            Some(api_key) => Ok(api_key.user_id),
            None => Err(anyhow::anyhow!("api key not found")),
        }
    }

    #[instrument]
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

    #[instrument]
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

    #[instrument]
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

    #[instrument]
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

    #[instrument]
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

    #[instrument]
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
}
