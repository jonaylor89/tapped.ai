use super::user::Location;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Booking {
    pub id: String,
    pub name: String,
    pub note: String,
    pub requester_id: Option<String>,
    pub requestee_id: String,
    #[serde(default)]
    pub status: BookingStatus,
    #[serde(default)]
    pub rate: f64,
    pub location: Option<Location>,
    #[serde(with = "firestore::serialize_as_timestamp")]
    pub start_time: DateTime<Utc>,
    #[serde(with = "firestore::serialize_as_timestamp")]
    pub end_time: DateTime<Utc>,
    #[serde(with = "firestore::serialize_as_timestamp")]
    pub timestamp: DateTime<Utc>,
    pub flier_url: Option<String>,
    pub event_url: Option<String>,
    pub venue_id: Option<String>,
    pub reference_event_id: Option<String>,
}

impl Booking {
    pub fn to_guarded(&self) -> GuardedBooking {
        GuardedBooking {
            id: self.id.clone(),
            title: self.name.clone(),
            description: self.note.clone(),
            booker_id: self.requester_id.clone(),
            performer_id: self.requestee_id.clone(),
            rate: self.rate,
            location: self.location.clone(),
            start_time: self.start_time.to_rfc3339(),
            end_time: self.end_time.to_rfc3339(),
            flier_url: self.flier_url.clone(),
            event_url: self.event_url.clone(),
            venue_id: self.venue_id.clone(),
            reference_event_id: self.reference_event_id.clone(),
        }
    }
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GuardedBooking {
    pub id: String,
    pub title: String,
    pub description: String,
    pub booker_id: Option<String>,
    pub performer_id: String,
    pub rate: f64,
    pub location: Option<Location>, // Assuming Location struct can be used here. Adjust as necessary.
    pub start_time: String,         // Assuming Timestamp as a String. Adjust as necessary.
    pub end_time: String,           // Assuming Timestamp as a String. Adjust as necessary.
    pub flier_url: Option<String>,
    pub event_url: Option<String>,
    pub venue_id: Option<String>,
    pub reference_event_id: Option<String>,
}

#[derive(Debug, Deserialize, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum BookingStatus {
    #[default]
    Confirmed,
    Pending,
    Canceled,
}
