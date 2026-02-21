use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Review {
    pub id: String,
    pub booker_id: String,
    pub performer_id: String,
    pub booking_id: String,
    #[serde(with = "firestore::serialize_as_timestamp")]
    pub timestamp: DateTime<Utc>,
    pub overall_rating: f64,
    pub overall_review: String,

    #[serde(rename = "type")]
    pub review_type: ReviewType,
}

impl Review {
    pub fn to_guarded(&self) -> GuardedReview {
        GuardedReview {
            id: self.id.clone(),
            performer_id: self.performer_id.clone(),
            booker_id: self.booker_id.clone(),
            booking_id: self.booking_id.clone(),
            rating: self.overall_rating,
            text: self.overall_review.clone(),
        }
    }
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GuardedReview {
    pub id: String,
    pub performer_id: String,
    pub booker_id: String,
    pub booking_id: String,
    pub rating: f64,
    pub text: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ReviewType {
    Performer,
    Booker,
}
