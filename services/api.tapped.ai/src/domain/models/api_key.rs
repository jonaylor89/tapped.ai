use ::serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ApiKey {
    pub key: String,
    pub user_id: String,

    #[serde(with = "firestore::serialize_as_timestamp")]
    pub timestamp: DateTime<Utc>,
}
