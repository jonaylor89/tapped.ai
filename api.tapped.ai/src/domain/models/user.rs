use super::{booking::GuardedBooking, review::GuardedReview};
// use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize)]
pub struct TicketRange {
    min: u64,
    max: u64,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Location {
    place_id: String,
    lat: f64,
    lng: f64,
}

#[derive(Debug, Deserialize, Serialize, Default, Clone)]
#[serde(rename_all = "camelCase")]
pub struct SocialFollowing {
    youtube_channel_id: Option<String>,
    tiktok_handle: Option<String>,
    #[serde(default)]
    tiktok_followers: u32,
    instagram_handle: Option<String>,
    #[serde(default)]
    instagram_followers: u32,
    twitter_handle: Option<String>,
    #[serde(default)]
    twitter_followers: u32,
    facebook_handle: Option<String>,
    #[serde(default)]
    facebook_followers: u32,
    spotify_url: Option<String>,
    soundcloud_handle: Option<String>,
    #[serde(default)]
    soundcloud_followers: u32,
    audius_handle: Option<String>,
    #[serde(default)]
    audius_followers: u32,
    twitch_handle: Option<String>,
    #[serde(default)]
    twitch_followers: u32,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct BookerInfo {
    rating: Option<f64>,
    #[serde(default)]
    review_count: u32,
}

#[derive(Debug, Deserialize, Serialize, Default, Clone)]
#[serde(rename_all = "camelCase")]
pub enum PerformerCategory {
    #[default]
    Undiscovered,
    Emerging,
    HometownHero,
    Mainstream,
    Legendary,
}

impl PerformerCategory {
    fn ticket_price_range(&self) -> TicketRange {
        match self {
            PerformerCategory::Undiscovered => TicketRange { min: 0, max: 1000 },
            PerformerCategory::Emerging => TicketRange {
                min: 1000,
                max: 2000,
            },
            PerformerCategory::HometownHero => TicketRange {
                min: 2000,
                max: 4000,
            },
            PerformerCategory::Mainstream => TicketRange {
                min: 4000,
                max: 7500,
            },
            PerformerCategory::Legendary => TicketRange {
                min: 7500,
                max: 100000,
            },
        }
    }
}

#[derive(Debug, Deserialize, Serialize, Default, Clone)]
#[serde(rename_all = "camelCase")]
pub struct PerformerInfo {
    press_kit_url: Option<String>,
    #[serde(default)]
    genres: Vec<String>,
    rating: Option<f64>,
    #[serde(default)]
    review_count: u32,
    #[serde(default)]
    label: String,

    #[serde(default)]
    category: PerformerCategory,
    spotify_id: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VenueInfo {
    #[serde(default)]
    genres: Vec<String>,
    booking_email: Option<String>,
    auto_reply: Option<String>,
    capacity: Option<u32>,
    ideal_performer_profile: Option<String>,
    production_info: Option<String>,
    front_of_house: Option<String>,
    monitors: Option<String>,
    microphones: Option<String>,
    lights: Option<String>,
    #[serde(default)]
    top_performer_ids: Vec<String>,
}

#[derive(Debug, Deserialize, Serialize, Default)]
#[serde(rename_all = "camelCase")]
struct EmailNotifications {
    #[serde(default)]
    app_releases: bool,
    #[serde(default)]
    tapped_updates: bool,
    #[serde(default)]
    booking_requests: bool,
    #[serde(default)]
    direct_messages: bool,
}

#[derive(Debug, Deserialize, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct PushNotifications {
    #[serde(default)]
    app_releases: bool,
    #[serde(default)]
    tapped_updates: bool,
    #[serde(default)]
    booking_requests: bool,
    #[serde(default)]
    direct_messages: bool,
}

#[derive(Debug, Deserialize, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct UserModel {
    pub id: String,
    pub email: String,
    #[serde(default)]
    unclaimed: bool,
    // #[serde(with = "firestore::serialize_as_timestamp")]
    // timestamp: DateTime<Utc>,
    pub username: String,
    #[serde(default)]
    artist_name: String,
    #[serde(default)]
    bio: String,
    #[serde(default)]
    occupations: Vec<String>,
    profile_picture: Option<String>,
    location: Option<Location>,
    performer_info: Option<PerformerInfo>,
    venue_info: Option<VenueInfo>,
    booker_info: Option<BookerInfo>,
    #[serde(default)]
    email_notifications: EmailNotifications,
    #[serde(default)]
    push_notifications: PushNotifications,
    deleted: bool,
    #[serde(default)]
    social_following: SocialFollowing,
    stripe_connected_account_id: Option<String>,
    stripe_customer_id: Option<String>,
}

impl UserModel {
    pub fn total_audience_size(&self) -> u32 {
        let social_following = &self.social_following;

        (social_following.twitter_followers)
            + (social_following.instagram_followers)
            + (social_following.tiktok_followers)
    }

    pub fn to_guarded_performer(
        &self,
        bookings: Vec<GuardedBooking>,
        reviews: Vec<GuardedReview>,
    ) -> GuardedPerformer {
        let audience = self.total_audience_size();
        let average_attendance = (audience as f64 / 250.0).round() as u32;
        let category = self
            .performer_info
            .as_ref()
            .map_or(PerformerCategory::Undiscovered, |info| {
                info.category.clone()
            });
        let user_ticket_range = category.ticket_price_range();

        GuardedPerformer {
            id: self.id.clone(),
            username: self.username.clone(),
            display_name: self.artist_name.clone(),
            bio: self.bio.clone(),
            profile_picture_url: self.profile_picture.clone(),
            location: self.location.clone(),
            social_following: self.social_following.clone(),
            press_kit_url: self
                .performer_info
                .as_ref()
                .and_then(|info| info.press_kit_url.clone()),
            genres: self
                .performer_info
                .as_ref()
                .map_or_else(Vec::new, |info| info.genres.clone()),
            spotify_id: self
                .performer_info
                .as_ref()
                .and_then(|info| info.spotify_id.clone()),
            average_attendance,
            average_ticket_range: user_ticket_range,
            bookings: Bookings {
                count: bookings.len(),
                items: bookings,
            },
            reviews: Reviews {
                count: reviews.len(),
                rating: if reviews.is_empty() {
                    0.0
                } else {
                    reviews.iter().map(|review| review.rating).sum::<f64>() / reviews.len() as f64
                },
                items: reviews,
            },
        }
    }

    pub fn to_guarded_venue(
        &self,
        bookings: Vec<GuardedBooking>,
        reviews: Vec<GuardedReview>,
    ) -> GuardedVenue {
        GuardedVenue {
            id: self.id.clone(),
            username: self.username.clone(),
            display_name: self.artist_name.clone(),
            bio: self.bio.clone(),
            profile_picture_url: self.profile_picture.clone(),
            location: self.location.clone(),
            booking_email: self
                .venue_info
                .as_ref()
                .and_then(|info| info.booking_email.clone()),
            capacity: self.venue_info.as_ref().and_then(|info| info.capacity),
            production_info: self
                .venue_info
                .as_ref()
                .and_then(|info| info.production_info.clone()),
            ideal_performer_profile: self
                .venue_info
                .as_ref()
                .and_then(|info| info.ideal_performer_profile.clone()),
            monitors: self
                .venue_info
                .as_ref()
                .and_then(|info| info.monitors.clone()),
            microphones: self
                .venue_info
                .as_ref()
                .and_then(|info| info.microphones.clone()),
            lights: self
                .venue_info
                .as_ref()
                .and_then(|info| info.lights.clone()),
            front_of_house: self
                .venue_info
                .as_ref()
                .and_then(|info| info.front_of_house.clone()),
            genres: self
                .venue_info
                .as_ref()
                .map_or_else(Vec::new, |info| info.genres.clone()),
            top_performer_ids: self
                .venue_info
                .as_ref()
                .map_or_else(Vec::new, |info| info.top_performer_ids.clone()),
            bookings: Bookings {
                count: bookings.len(),
                items: bookings,
            },
            reviews: Reviews {
                count: reviews.len(),
                rating: if reviews.is_empty() {
                    0.0
                } else {
                    reviews.iter().map(|review| review.rating).sum::<f64>() / reviews.len() as f64
                },
                items: reviews,
            },
        }
    }
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Bookings<T> {
    count: usize,
    items: Vec<T>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Reviews<T> {
    count: usize,
    rating: f64,
    items: Vec<T>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GuardedPerformer {
    id: String,
    username: String,
    display_name: String,
    bio: String,
    profile_picture_url: Option<String>,
    location: Option<Location>,
    social_following: SocialFollowing,
    press_kit_url: Option<String>,
    genres: Vec<String>,
    spotify_id: Option<String>,
    average_ticket_range: TicketRange,
    average_attendance: u32,
    bookings: Bookings<GuardedBooking>,
    reviews: Reviews<GuardedReview>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GuardedVenue {
    pub id: String,
    pub username: String,
    pub display_name: String,
    pub bio: String,
    pub profile_picture_url: Option<String>,
    pub location: Option<Location>,
    pub genres: Vec<String>,
    pub booking_email: Option<String>,
    pub capacity: Option<u32>,
    pub ideal_performer_profile: Option<String>,
    pub production_info: Option<String>,
    pub front_of_house: Option<String>,
    pub monitors: Option<String>,
    pub microphones: Option<String>,
    pub lights: Option<String>,
    pub top_performer_ids: Vec<String>,
    pub bookings: Bookings<GuardedBooking>,
    pub reviews: Reviews<GuardedReview>,
}
