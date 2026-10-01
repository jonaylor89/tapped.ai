use serde::{Deserialize, Serialize};

/// The subset of an opportunity needed to notify its venue when a performer applies.
#[derive(Debug, Clone, Deserialize, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Opportunity {
    pub id: String,
    pub user_id: String,
    pub reference_event_id: Option<String>,
    pub title: String,
}
