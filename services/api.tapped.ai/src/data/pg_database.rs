use anyhow::{Result, anyhow};
use axum::async_trait;
use serde::de::DeserializeOwned;
use serde_json::Value;
use sqlx::PgPool;

use crate::{
    data::database::Database,
    domain::models::{
        api_key::hash_api_key, booking::Booking, opportunity::Opportunity, review::Review,
        user::UserModel,
    },
};

/// The only production repository for migrated documents. Never falls back to Firestore.
#[derive(Clone)]
pub struct PostgresDatabase {
    pub pool: PgPool,
}

impl PostgresDatabase {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
    async fn one<T: DeserializeOwned>(&self, sql: &str, key: &str) -> Result<T> {
        let value: Option<Value> = sqlx::query_scalar(sql)
            .bind(key)
            .fetch_optional(&self.pool)
            .await?;
        serde_json::from_value(value.ok_or_else(|| anyhow!("not found"))?).map_err(Into::into)
    }
    async fn many<T: DeserializeOwned>(&self, sql: &str, key: &str) -> Result<Vec<T>> {
        let values: Vec<Value> = sqlx::query_scalar(sql)
            .bind(key)
            .fetch_all(&self.pool)
            .await?;
        values
            .into_iter()
            .map(|v| serde_json::from_value(v).map_err(Into::into))
            .collect()
    }
}

#[async_trait]
impl Database for PostgresDatabase {
    async fn ping(&self) -> Result<()> {
        // Probe the serving projection, not merely TCP connectivity.
        sqlx::query("SELECT id FROM api_users LIMIT 1")
            .execute(&self.pool)
            .await?;
        Ok(())
    }
    async fn get_user_from_api_key(&self, key: &str) -> Result<Option<String>> {
        Ok(sqlx::query_scalar("SELECT k.user_id FROM api_keys k JOIN users u ON u.id=k.user_id WHERE k.key_hash=$1 AND NOT u.deleted")
           .bind(hash_api_key(key)).fetch_optional(&self.pool).await?)
    }
    async fn get_user_by_id(&self, id: &str) -> Result<UserModel> {
        self.one(
            "SELECT doc FROM api_users WHERE id=$1 AND NOT (doc->>'deleted')::boolean",
            id,
        )
        .await
    }
    async fn get_user_by_username(&self, username: &str) -> Result<UserModel> {
        self.one("SELECT doc FROM api_users WHERE lower(doc->>'username')=lower($1) AND NOT (doc->>'deleted')::boolean",username).await
    }
    async fn get_opportunity_by_id(&self, id: &str) -> Result<Opportunity> {
        self.one(
            "SELECT doc FROM api_opportunities WHERE id=$1 AND NOT (doc->>'deleted')::boolean",
            id,
        )
        .await
    }
    async fn get_bookings_by_reference_event_id(&self, id: &str) -> Result<Vec<Booking>> {
        self.many("SELECT v.doc FROM api_bookings v JOIN bookings b USING(id) WHERE b.reference_event_id=$1 ORDER BY b.start_time DESC NULLS LAST,b.id DESC",id).await
    }
    async fn get_bookings_by_performer_id(&self, id: &str) -> Result<Vec<Booking>> {
        self.many("SELECT v.doc FROM api_bookings v JOIN bookings b USING(id) WHERE b.requestee_id=$1 AND b.status='confirmed' ORDER BY b.start_time DESC NULLS LAST,b.id DESC",id).await
    }
    async fn get_bookings_by_booker_id(&self, id: &str) -> Result<Vec<Booking>> {
        self.many("SELECT v.doc FROM api_bookings v JOIN bookings b USING(id) WHERE b.requester_id=$1 AND b.status='confirmed' ORDER BY b.start_time DESC NULLS LAST,b.id DESC",id).await
    }
    async fn get_reviews_by_performer_id(&self, id: &str) -> Result<Vec<Review>> {
        self.many("SELECT v.doc FROM api_reviews v JOIN reviews r USING(id,review_type,reviewee_id) WHERE r.reviewee_id=$1 AND r.review_type='performer' ORDER BY r.occurred_at DESC NULLS LAST,r.id DESC",id).await
    }
    async fn get_reviews_by_booker_id(&self, id: &str) -> Result<Vec<Review>> {
        self.many("SELECT v.doc FROM api_reviews v JOIN reviews r USING(id,review_type,reviewee_id) WHERE r.reviewee_id=$1 AND r.review_type='booker' ORDER BY r.occurred_at DESC NULLS LAST,r.id DESC",id).await
    }
    async fn get_user_doc_by_username(&self, username: &str) -> Result<Option<Value>> {
        Ok(
            sqlx::query_scalar("SELECT doc FROM api_users WHERE lower(doc->>'username')=lower($1)")
                .bind(username)
                .fetch_optional(&self.pool)
                .await?,
        )
    }
    async fn get_opportunity_doc(&self, id: &str) -> Result<Option<Value>> {
        Ok(
            sqlx::query_scalar("SELECT doc FROM api_opportunities WHERE id=$1")
                .bind(id)
                .fetch_optional(&self.pool)
                .await?,
        )
    }
}
