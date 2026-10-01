use axum::{Json, extract::State, http::StatusCode};
use jsonwebtoken::{Algorithm, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

use crate::{
    domain::{
        firebase_auth::FirebaseUser,
        mail_bridge::{EmailThread, QueuedEmail, StreamDelivery, notify_slack},
        mail_composer::{ComposeVenueEmail, OpportunityContext},
        models::opportunity::Opportunity,
    },
    state::AppStateDyn,
};

#[derive(Debug, Serialize)]
pub struct StreamUserTokenResponse {
    pub token: String,
}

/// Generates a Stream user token for the authenticated Firebase account only.
pub async fn stream_user_token(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
) -> Result<Json<StreamUserTokenResponse>, StatusCode> {
    let token = jsonwebtoken::encode(
        &Header::new(Algorithm::HS256),
        &serde_json::json!({
            "user_id": user.uid,
            "exp": chrono::Utc::now().timestamp() + 3_600,
        }),
        &EncodingKey::from_secret(state.mail.stream_webhook_secret.as_bytes()),
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(Json(StreamUserTokenResponse { token }))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NotifyVenueOfInterestedOpportunities {
    pub opportunity_ids: Vec<String>,
    #[serde(default)]
    pub note: String,
}

#[derive(Debug, Serialize)]
pub struct NotifyVenueResponse {
    pub venues_notified: usize,
}

struct VenueOpportunities {
    opportunities: Vec<Opportunity>,
    other_performers: Vec<String>,
}

/// Replaces the legacy callable. Firebase identity is deliberately the sole source of performer ID.
pub async fn notify_venue_of_interested_opportunities(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Json(command): Json<NotifyVenueOfInterestedOpportunities>,
) -> Result<Json<NotifyVenueResponse>, StatusCode> {
    if command.opportunity_ids.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }

    let mut opportunities = Vec::new();
    for opportunity_id in &command.opportunity_ids {
        if let Ok(opportunity) = state.database.get_opportunity_by_id(opportunity_id).await {
            opportunities.push(opportunity);
        }
    }
    if opportunities.is_empty() {
        return Err(StatusCode::UNPROCESSABLE_ENTITY);
    }

    let mut by_venue: HashMap<String, VenueOpportunities> = HashMap::new();
    for opportunity in opportunities {
        if opportunity.user_id == user.uid {
            continue;
        }
        let Some(reference_event_id) = opportunity.reference_event_id.as_deref() else {
            continue;
        };
        let Ok(bookings) = state
            .database
            .get_bookings_by_reference_event_id(reference_event_id)
            .await
        else {
            continue;
        };
        let Some(venue_id) = bookings
            .iter()
            .find_map(|booking| booking.requester_id.as_deref())
            .map(str::to_owned)
        else {
            continue;
        };
        let mut other_performers = Vec::new();
        for booking in bookings {
            if let Ok(performer) = state.database.get_user_by_id(&booking.requestee_id).await {
                let name = performer.display_name().to_string();
                if !name.is_empty() && !other_performers.contains(&name) {
                    other_performers.push(name);
                }
            }
        }
        let entry = by_venue.entry(venue_id).or_insert(VenueOpportunities {
            opportunities: vec![],
            other_performers: vec![],
        });
        entry.opportunities.push(opportunity);
        for performer in other_performers {
            if !entry.other_performers.contains(&performer) {
                entry.other_performers.push(performer);
            }
        }
    }

    let performer = state
        .database
        .get_user_by_id(&user.uid)
        .await
        .map_err(|_| StatusCode::NOT_FOUND)?;
    if performer.username.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }

    let mut venues_notified = 0;
    for (venue_id, context) in by_venue {
        let Ok(venue) = state.database.get_user_by_id(&venue_id).await else {
            continue;
        };
        // Legacy email outreach was only sent to unclaimed venues.
        if !venue.is_unclaimed() {
            continue;
        }
        let Some(recipient) = venue.booking_email().map(str::to_owned) else {
            continue;
        };
        let existing = state
            .mail
            .store
            .thread_for_stream(&user.uid, &venue_id)
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        if existing.is_none()
            && let Some(auto_reply) = venue.auto_reply()
        {
            if let Err(error) = state
                .mail
                .stream
                .send_message(&StreamDelivery {
                    event_id: format!("venue-auto-reply:{}:{}", user.uid, venue_id),
                    thread_id: String::new(),
                    sender_id: venue_id.clone(),
                    receiver_id: user.uid.clone(),
                    text: auto_reply.to_owned(),
                    frozen: true,
                })
                .await
            {
                tracing::warn!(?error, "failed to send venue auto-reply");
            }
            continue;
        }
        let previous_messages = match existing.as_ref() {
            Some(thread) => state
                .mail
                .store
                .messages_for_thread(&thread.id)
                .await
                .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?,
            None => vec![],
        };
        let composed = state
            .mail
            .composer
            .compose(ComposeVenueEmail {
                performer_display_name: performer.display_name().to_owned(),
                performer_username: performer.username.clone(),
                performer_genres: performer.performer_genres().to_vec(),
                performer_press_kit_url: performer.press_kit_url().map(str::to_owned),
                performer_social_links: performer.social_links(),
                venue_name: venue.display_name().to_owned(),
                note: command.note.clone(),
                opportunities: context
                    .opportunities
                    .iter()
                    .map(|opportunity| OpportunityContext {
                        title: opportunity.title.clone(),
                        date: opportunity.start_time.format("%Y-%m-%d").to_string(),
                        other_performers: context.other_performers.clone(),
                    })
                    .collect(),
                previous_messages,
            })
            .await
            .map_err(|error| {
                tracing::error!(?error, "failed to compose venue email");
                StatusCode::SERVICE_UNAVAILABLE
            })?;
        let event_id = format!("opportunity-notification:{}", Uuid::new_v4());
        let message_id = format!("<{}@{}>", Uuid::new_v4(), state.mail.booking_domain);
        let generated_body = composed.generated_body.clone();
        let is_new_thread = existing.is_none();
        let queued = if let Some(thread) = existing {
            state
                .mail
                .store
                .enqueue_outbound(QueuedEmail {
                    event_id,
                    thread_id: thread.id,
                    from: format!("{}@{}", performer.username, state.mail.booking_domain),
                    to: thread.recipients,
                    cc: vec![],
                    subject: thread.subject,
                    text_body: composed.text_body,
                    html_body: Some(composed.html_body),
                    message_id,
                    in_reply_to: thread.latest_message_id.clone(),
                    references: thread.latest_message_id,
                    attachments: vec![],
                    encoded_attachments: vec![],
                })
                .await
        } else {
            let thread_id = Uuid::new_v4().to_string();
            state
                .mail
                .store
                .create_thread_and_enqueue(
                    EmailThread {
                        id: thread_id.clone(),
                        performer_id: user.uid.clone(),
                        performer_username: performer.username.clone(),
                        venue_id: venue_id.clone(),
                        recipients: vec![recipient.clone()],
                        subject: composed.subject.clone(),
                        latest_message_id: message_id.clone(),
                    },
                    QueuedEmail {
                        event_id,
                        thread_id,
                        from: format!("{}@{}", performer.username, state.mail.booking_domain),
                        to: vec![recipient],
                        cc: state.mail.founder_cc.clone(),
                        subject: composed.subject,
                        text_body: composed.text_body,
                        html_body: Some(composed.html_body),
                        message_id,
                        in_reply_to: String::new(),
                        references: String::new(),
                        attachments: vec![],
                        encoded_attachments: vec![],
                    },
                )
                .await
        }
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        if queued
            && is_new_thread
            && let Err(error) = state
                .mail
                .stream
                .send_message(&StreamDelivery {
                    event_id: format!("venue-contact:{}:{}", user.uid, venue_id),
                    thread_id: String::new(),
                    sender_id: user.uid.clone(),
                    receiver_id: venue_id.clone(),
                    text: generated_body,
                    frozen: true,
                })
                .await
        {
            tracing::warn!(?error, "failed to mirror venue contact to Stream");
        }
        if queued {
            notify_slack(
                state.mail.slack_webhook_url.as_deref(),
                "new venue contact email",
                &format!("{} => {}", performer.display_name(), venue.display_name()),
            )
            .await;
            venues_notified += 1;
        }
    }

    Ok(Json(NotifyVenueResponse { venues_notified }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        data::{database::Database, search::MockSearch},
        domain::{
            mail_bridge::{InMemoryMailStore, MailBridge, StreamGateway},
            models::{
                booking::{Booking, BookingStatus},
                review::Review,
                user::UserModel,
            },
        },
    };
    use async_trait::async_trait;
    use chrono::Utc;
    use std::{
        collections::HashMap,
        sync::{Arc, Mutex},
    };

    #[derive(Default)]
    struct RecordingStream {
        deliveries: Mutex<Vec<StreamDelivery>>,
    }
    #[async_trait]
    impl StreamGateway for RecordingStream {
        async fn send_message(&self, delivery: &StreamDelivery) -> anyhow::Result<()> {
            self.deliveries.lock().unwrap().push(delivery.clone());
            Ok(())
        }
    }

    struct TestDatabase {
        users: HashMap<String, serde_json::Value>,
        opportunities: HashMap<String, Opportunity>,
        bookings: HashMap<String, Vec<(String, String)>>,
    }
    #[async_trait]
    impl Database for TestDatabase {
        async fn get_user_from_api_key(&self, _: &str) -> anyhow::Result<String> {
            unreachable!()
        }
        async fn get_user_by_id(&self, id: &str) -> anyhow::Result<UserModel> {
            self.users
                .get(id)
                .cloned()
                .map(serde_json::from_value)
                .transpose()?
                .ok_or_else(|| anyhow::anyhow!("not found"))
        }
        async fn get_user_by_username(&self, _: &str) -> anyhow::Result<UserModel> {
            unreachable!()
        }
        async fn get_opportunity_by_id(&self, id: &str) -> anyhow::Result<Opportunity> {
            self.opportunities
                .get(id)
                .cloned()
                .ok_or_else(|| anyhow::anyhow!("not found"))
        }
        async fn get_bookings_by_reference_event_id(
            &self,
            id: &str,
        ) -> anyhow::Result<Vec<Booking>> {
            Ok(self
                .bookings
                .get(id)
                .into_iter()
                .flatten()
                .map(|(venue, performer)| booking(venue, performer))
                .collect())
        }
        async fn get_bookings_by_performer_id(&self, _: &str) -> anyhow::Result<Vec<Booking>> {
            unreachable!()
        }
        async fn get_bookings_by_booker_id(&self, _: &str) -> anyhow::Result<Vec<Booking>> {
            unreachable!()
        }
        async fn get_reviews_by_performer_id(&self, _: &str) -> anyhow::Result<Vec<Review>> {
            unreachable!()
        }
        async fn get_reviews_by_booker_id(&self, _: &str) -> anyhow::Result<Vec<Review>> {
            unreachable!()
        }
    }

    fn user(
        id: &str,
        username: &str,
        unclaimed: bool,
        booking_email: Option<&str>,
    ) -> serde_json::Value {
        serde_json::json!({
            "id": id, "email": format!("{id}@example.com"), "username": username, "deleted": false,
            "unclaimed": unclaimed,
            "venueInfo": booking_email.map(|email| serde_json::json!({"bookingEmail": email}))
        })
    }
    fn booking(venue: &str, performer: &str) -> Booking {
        Booking {
            id: "booking".into(),
            name: String::new(),
            note: String::new(),
            requester_id: Some(venue.into()),
            requestee_id: performer.into(),
            status: BookingStatus::Confirmed,
            rate: 0.0,
            location: None,
            start_time: Utc::now(),
            end_time: Utc::now(),
            timestamp: Utc::now(),
            flier_url: None,
            event_url: None,
            venue_id: None,
            reference_event_id: Some("event-1".into()),
        }
    }
    fn state() -> (AppStateDyn, Arc<InMemoryMailStore>, Arc<RecordingStream>) {
        let store = Arc::new(InMemoryMailStore::default());
        let stream = Arc::new(RecordingStream::default());
        let database = TestDatabase {
            users: HashMap::from([
                ("artist".into(), user("artist", "the-band", false, None)),
                (
                    "venue-a".into(),
                    user("venue-a", "venue a", true, Some("a@example.com")),
                ),
                (
                    "venue-claimed".into(),
                    user(
                        "venue-claimed",
                        "claimed",
                        false,
                        Some("claimed@example.com"),
                    ),
                ),
                ("other".into(), user("other", "other act", false, None)),
                (
                    "venue-auto".into(),
                    serde_json::json!({
                        "id": "venue-auto", "email": "auto@example.com", "username": "auto venue",
                        "deleted": false, "unclaimed": true,
                        "venueInfo": {"bookingEmail": "auto@example.com", "autoReply": "Thanks, we'll reply soon"}
                    }),
                ),
                (
                    "venue-no-email".into(),
                    user("venue-no-email", "no email", true, None),
                ),
            ]),
            opportunities: HashMap::from([
                (
                    "valid".into(),
                    Opportunity {
                        id: "valid".into(),
                        user_id: "owner".into(),
                        reference_event_id: Some("event-1".into()),
                        title: "Friday showcase".into(),
                        start_time: Utc::now(),
                    },
                ),
                (
                    "also-valid".into(),
                    Opportunity {
                        id: "also-valid".into(),
                        user_id: "owner".into(),
                        reference_event_id: Some("event-1".into()),
                        title: "Saturday showcase".into(),
                        start_time: Utc::now(),
                    },
                ),
                (
                    "owned".into(),
                    Opportunity {
                        id: "owned".into(),
                        user_id: "artist".into(),
                        reference_event_id: Some("event-1".into()),
                        title: "Owned".into(),
                        start_time: Utc::now(),
                    },
                ),
                (
                    "claimed".into(),
                    Opportunity {
                        id: "claimed".into(),
                        user_id: "owner".into(),
                        reference_event_id: Some("event-claimed".into()),
                        title: "Claimed venue".into(),
                        start_time: Utc::now(),
                    },
                ),
                (
                    "no-email".into(),
                    Opportunity {
                        id: "no-email".into(),
                        user_id: "owner".into(),
                        reference_event_id: Some("event-no-email".into()),
                        title: "No email venue".into(),
                        start_time: Utc::now(),
                    },
                ),
                (
                    "auto-reply".into(),
                    Opportunity {
                        id: "auto-reply".into(),
                        user_id: "owner".into(),
                        reference_event_id: Some("event-auto".into()),
                        title: "Auto reply venue".into(),
                        start_time: Utc::now(),
                    },
                ),
                (
                    "missing-reference".into(),
                    Opportunity {
                        id: "missing-reference".into(),
                        user_id: "owner".into(),
                        reference_event_id: None,
                        title: "No reference".into(),
                        start_time: Utc::now(),
                    },
                ),
            ]),
            bookings: HashMap::from([
                ("event-1".into(), vec![("venue-a".into(), "other".into())]),
                (
                    "event-claimed".into(),
                    vec![("venue-claimed".into(), "other".into())],
                ),
                (
                    "event-no-email".into(),
                    vec![("venue-no-email".into(), "other".into())],
                ),
                (
                    "event-auto".into(),
                    vec![("venue-auto".into(), "other".into())],
                ),
            ]),
        };
        (
            AppStateDyn {
                database: Arc::new(database),
                search: Arc::new(MockSearch),
                firebase_project_id: "test".into(),
                response_cache: Default::default(),
                places: std::sync::Arc::new(crate::data::places::MockPlaces),
                mail: MailBridge {
                    store: store.clone(),
                    stream: stream.clone(),
                    stream_webhook_secret: "stream-secret".into(),
                    ingress_secret: String::new(),
                    service_secret: String::new(),
                    booking_domain: "booking.tapped.ai".into(),
                    composer: Arc::new(crate::domain::mail_composer::StaticEmailComposer),
                    founder_cc: vec!["founder@tapped.ai".into()],
                    slack_webhook_url: None,
                },
            },
            store,
            stream,
        )
    }
    fn artist() -> FirebaseUser {
        FirebaseUser {
            uid: "artist".into(),
            email: None,
        }
    }

    #[tokio::test]
    async fn stream_token_uses_authenticated_firebase_uid() {
        let (state, _, _) = state();
        let Json(response) = stream_user_token(State(state), artist()).await.unwrap();
        let token = jsonwebtoken::decode::<serde_json::Value>(
            &response.token,
            &jsonwebtoken::DecodingKey::from_secret(b"stream-secret"),
            &jsonwebtoken::Validation::new(Algorithm::HS256),
        )
        .unwrap();
        assert_eq!(token.claims["user_id"], "artist");
    }

    #[tokio::test]
    async fn notification_groups_and_skips_invalid_opportunities() {
        let (state, store, stream) = state();
        let Json(response) = notify_venue_of_interested_opportunities(
            State(state),
            artist(),
            Json(NotifyVenueOfInterestedOpportunities {
                opportunity_ids: vec![
                    "valid".into(),
                    "also-valid".into(),
                    "owned".into(),
                    "claimed".into(),
                    "no-email".into(),
                    "missing-reference".into(),
                ],
                note: "Available now".into(),
            }),
        )
        .await
        .unwrap();
        assert_eq!(response.venues_notified, 1);
        let queued = store.outbound();
        assert_eq!(queued.len(), 1);
        assert_eq!(queued[0].to, ["a@example.com"]);
        assert!(queued[0].text_body.contains("Friday showcase"));
        assert!(queued[0].text_body.contains("Saturday showcase"));
        assert!(queued[0].text_body.contains("other act"));
        assert_eq!(queued[0].cc, ["founder@tapped.ai"]);
        let deliveries = stream.deliveries.lock().unwrap();
        assert_eq!(deliveries.len(), 1);
        assert!(deliveries[0].frozen);
    }

    #[tokio::test]
    async fn notification_appends_to_an_existing_thread() {
        let (state, store, _) = state();
        let request = NotifyVenueOfInterestedOpportunities {
            opportunity_ids: vec!["valid".into()],
            note: String::new(),
        };
        let _ =
            notify_venue_of_interested_opportunities(State(state.clone()), artist(), Json(request))
                .await
                .unwrap();
        let _ = notify_venue_of_interested_opportunities(
            State(state),
            artist(),
            Json(NotifyVenueOfInterestedOpportunities {
                opportunity_ids: vec!["valid".into()],
                note: "different request".into(),
            }),
        )
        .await
        .unwrap();
        let queued = store.outbound();
        assert_eq!(queued.len(), 2);
        assert_eq!(queued[0].thread_id, queued[1].thread_id);
        assert_eq!(queued[1].in_reply_to, queued[0].message_id);
    }

    #[tokio::test]
    async fn venue_auto_reply_uses_a_frozen_stream_message_instead_of_email() {
        let (state, store, stream) = state();
        let Json(response) = notify_venue_of_interested_opportunities(
            State(state),
            artist(),
            Json(NotifyVenueOfInterestedOpportunities {
                opportunity_ids: vec!["auto-reply".into()],
                note: String::new(),
            }),
        )
        .await
        .unwrap();
        assert_eq!(response.venues_notified, 0);
        assert!(store.outbound().is_empty());
        let deliveries = stream.deliveries.lock().unwrap();
        assert_eq!(deliveries.len(), 1);
        assert_eq!(deliveries[0].sender_id, "venue-auto");
        assert!(deliveries[0].frozen);
    }

    #[tokio::test]
    async fn missing_opportunities_are_rejected() {
        let (state, store, _) = state();
        assert_eq!(
            notify_venue_of_interested_opportunities(
                State(state),
                artist(),
                Json(NotifyVenueOfInterestedOpportunities {
                    opportunity_ids: vec!["missing".into()],
                    note: String::new()
                })
            )
            .await
            .unwrap_err(),
            StatusCode::UNPROCESSABLE_ENTITY
        );
        assert!(store.outbound().is_empty());
    }
}
