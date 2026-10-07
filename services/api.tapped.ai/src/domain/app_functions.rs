use axum::{
    Json,
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
};
use chrono::Utc;
use futures::future::join_all;
use jsonwebtoken::{Algorithm, EncodingKey, Header};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

use crate::{
    domain::{
        firebase_auth::FirebaseUser,
        venue_notifications::{self, IDEMPOTENCY_WINDOW, JobStatus, VenueNotificationJob},
    },
    errors::AppError,
    state::AppStateDyn,
};

#[derive(Debug, Serialize, JsonSchema)]
pub struct StreamUserTokenResponse {
    pub token: String,
}

/// Generates a Stream user token for the authenticated Firebase account only.
pub async fn stream_user_token(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
) -> Result<Json<StreamUserTokenResponse>, AppError> {
    let token = jsonwebtoken::encode(
        &Header::new(Algorithm::HS256),
        &serde_json::json!({
            "user_id": user.uid,
            "exp": chrono::Utc::now().timestamp() + 3_600,
        }),
        &EncodingKey::from_secret(state.mail.stream_webhook_secret.as_bytes()),
    )
    .map_err(|error| AppError::internal("failed to sign Stream token", error))?;
    Ok(Json(StreamUserTokenResponse { token }))
}

/// The largest request accepted; the iOS client sends one opportunity per apply.
pub const MAX_OPPORTUNITIES_PER_NOTIFICATION: usize = 50;
const IDEMPOTENCY_KEY_HEADER: &str = "idempotency-key";

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct NotifyVenueOfInterestedOpportunities {
    pub opportunity_ids: Vec<String>,
    #[serde(default)]
    pub note: String,
}

#[derive(Debug, Serialize, JsonSchema)]
pub struct NotifyVenueResponse {
    /// Poll `GET /app/v1/opportunity-venue-notifications/{job_id}` for the outcome.
    pub job_id: String,
    pub status: JobStatus,
    /// Venues with an email queued. `null` until the job has completed.
    pub venues_notified: Option<usize>,
}

impl From<VenueNotificationJob> for NotifyVenueResponse {
    fn from(job: VenueNotificationJob) -> Self {
        Self {
            job_id: job.id,
            status: job.status,
            venues_notified: job.venues_notified,
        }
    }
}

/// Replaces the legacy callable. Firebase identity is deliberately the sole source of performer ID.
///
/// Only validates and records a job; composing and queueing the venue emails, the Stream mirror
/// and Slack run in [`venue_notifications::run_worker`]. A retry of the same request (same
/// `Idempotency-Key` header, or the same opportunities and note) within
/// [`venue_notifications::IDEMPOTENCY_WINDOW`] returns the original job.
pub async fn notify_venue_of_interested_opportunities(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    headers: HeaderMap,
    Json(command): Json<NotifyVenueOfInterestedOpportunities>,
) -> Result<(StatusCode, Json<NotifyVenueResponse>), AppError> {
    if command.opportunity_ids.is_empty() {
        return Err(AppError::unprocessable("opportunityIds must not be empty"));
    }
    if command.opportunity_ids.len() > MAX_OPPORTUNITIES_PER_NOTIFICATION {
        return Err(AppError::unprocessable(format!(
            "at most {MAX_OPPORTUNITIES_PER_NOTIFICATION} opportunityIds per request"
        )));
    }
    let client_key = headers
        .get(IDEMPOTENCY_KEY_HEADER)
        .map(|value| value.to_str().map(str::trim))
        .transpose()
        .map_err(|_| AppError::bad_request("Idempotency-Key must be ASCII"))?
        .filter(|key| !key.is_empty());

    let opportunities = join_all(
        command
            .opportunity_ids
            .iter()
            .map(|id| state.database.get_opportunity_by_id(id)),
    )
    .await;
    if !opportunities.iter().any(Result::is_ok) {
        return Err(AppError::unprocessable("no valid opportunities were found"));
    }

    let key = venue_notifications::idempotency_key(
        &user.uid,
        client_key,
        &command.opportunity_ids,
        &command.note,
    );
    let dedupe_since = Utc::now().timestamp() - IDEMPOTENCY_WINDOW.as_secs() as i64;
    let job = state
        .mail
        .store
        .enqueue_venue_notification(
            VenueNotificationJob::new(user.uid, key, command.opportunity_ids, command.note),
            dedupe_since,
        )
        .await
        .map_err(|error| AppError::internal("failed to record venue notification job", error))?;
    Ok((StatusCode::ACCEPTED, Json(job.into())))
}

/// The outcome of a job created by [`notify_venue_of_interested_opportunities`]. Jobs are only
/// visible to the performer who created them.
pub async fn get_venue_notification(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(job_id): Path<String>,
) -> Result<Json<NotifyVenueResponse>, AppError> {
    let job = state
        .mail
        .store
        .venue_notification(&job_id)
        .await
        .map_err(|error| AppError::internal("failed to read venue notification job", error))?
        .filter(|job| job.performer_id == user.uid)
        .ok_or_else(|| AppError::not_found("venue notification job not found"))?;
    Ok(Json(job.into()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        data::{database::Database, search::MockSearch},
        domain::{
            mail_bridge::{InMemoryMailStore, MailBridge, StreamDelivery, StreamGateway},
            models::{
                booking::{Booking, BookingStatus},
                opportunity::Opportunity,
                review::Review,
                user::UserModel,
            },
            venue_notifications::process_due,
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
        async fn get_user_from_api_key(&self, _: &str) -> anyhow::Result<Option<String>> {
            Ok(None)
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
                spotify: std::sync::Arc::new(crate::data::spotify::MockSpotify),
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

    async fn notify(
        state: &AppStateDyn,
        headers: HeaderMap,
        opportunity_ids: &[&str],
        note: &str,
    ) -> Result<NotifyVenueResponse, AppError> {
        let (status, Json(response)) = notify_venue_of_interested_opportunities(
            State(state.clone()),
            artist(),
            headers,
            Json(NotifyVenueOfInterestedOpportunities {
                opportunity_ids: opportunity_ids.iter().map(|id| id.to_string()).collect(),
                note: note.into(),
            }),
        )
        .await?;
        assert_eq!(status, StatusCode::ACCEPTED);
        Ok(response)
    }

    async fn job(state: &AppStateDyn, id: &str) -> NotifyVenueResponse {
        get_venue_notification(State(state.clone()), artist(), Path(id.into()))
            .await
            .unwrap()
            .0
    }

    #[tokio::test]
    async fn notification_is_accepted_before_any_email_work() {
        let (state, store, stream) = state();
        let response = notify(&state, HeaderMap::new(), &["valid"], "")
            .await
            .unwrap();
        assert_eq!(response.status, JobStatus::Queued);
        assert_eq!(response.venues_notified, None);
        assert!(store.outbound().is_empty());
        assert!(stream.deliveries.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn notification_groups_and_skips_invalid_opportunities() {
        let (state, store, stream) = state();
        let response = notify(
            &state,
            HeaderMap::new(),
            &[
                "valid",
                "also-valid",
                "owned",
                "claimed",
                "no-email",
                "missing-reference",
                "missing",
            ],
            "Available now",
        )
        .await
        .unwrap();
        assert_eq!(process_due(&state).await.unwrap(), 1);
        let finished = job(&state, &response.job_id).await;
        assert_eq!(finished.status, JobStatus::Completed);
        assert_eq!(finished.venues_notified, Some(1));
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
        notify(&state, HeaderMap::new(), &["valid"], "")
            .await
            .unwrap();
        notify(&state, HeaderMap::new(), &["valid"], "different request")
            .await
            .unwrap();
        process_due(&state).await.unwrap();
        process_due(&state).await.unwrap();
        let queued = store.outbound();
        assert_eq!(queued.len(), 2);
        assert_eq!(queued[0].thread_id, queued[1].thread_id);
        assert_eq!(queued[1].in_reply_to, queued[0].message_id);
    }

    #[tokio::test]
    async fn retried_requests_reuse_the_job_and_send_one_email() {
        let (state, store, stream) = state();
        let first = notify(&state, HeaderMap::new(), &["valid", "also-valid"], "hi")
            .await
            .unwrap();
        let reordered = notify(&state, HeaderMap::new(), &["also-valid", "valid"], "hi")
            .await
            .unwrap();
        assert_eq!(first.job_id, reordered.job_id);
        process_due(&state).await.unwrap();
        let after_completion = notify(&state, HeaderMap::new(), &["valid", "also-valid"], "hi")
            .await
            .unwrap();
        assert_eq!(after_completion.job_id, first.job_id);
        assert_eq!(after_completion.status, JobStatus::Completed);
        assert_eq!(process_due(&state).await.unwrap(), 0);
        assert_eq!(store.outbound().len(), 1);
        assert_eq!(stream.deliveries.lock().unwrap().len(), 1);
    }

    #[tokio::test]
    async fn idempotency_key_header_identifies_the_request() {
        let (state, _, _) = state();
        let mut headers = HeaderMap::new();
        headers.insert(IDEMPOTENCY_KEY_HEADER, "apply-1".parse().unwrap());
        let first = notify(&state, headers.clone(), &["valid"], "a")
            .await
            .unwrap();
        let retry = notify(&state, headers, &["valid"], "edited").await.unwrap();
        assert_eq!(first.job_id, retry.job_id);
        let mut other = HeaderMap::new();
        other.insert(IDEMPOTENCY_KEY_HEADER, "apply-2".parse().unwrap());
        let second = notify(&state, other, &["valid"], "a").await.unwrap();
        assert_ne!(first.job_id, second.job_id);
    }

    #[tokio::test]
    async fn a_retried_job_does_not_send_a_second_email() {
        let (state, store, _) = state();
        let response = notify(&state, HeaderMap::new(), &["valid"], "")
            .await
            .unwrap();
        process_due(&state).await.unwrap();
        // Simulate a crash after the email was queued but before the job was marked complete.
        {
            let mut jobs = store.venue_notification_jobs.lock().unwrap();
            jobs[0].status = JobStatus::Queued;
            jobs[0].available_at = 0;
        }
        assert_eq!(process_due(&state).await.unwrap(), 1);
        assert_eq!(store.outbound().len(), 1);
        assert_eq!(job(&state, &response.job_id).await.venues_notified, Some(1));
    }

    #[tokio::test]
    async fn venue_auto_reply_uses_a_frozen_stream_message_instead_of_email() {
        let (state, store, stream) = state();
        let response = notify(&state, HeaderMap::new(), &["auto-reply"], "")
            .await
            .unwrap();
        process_due(&state).await.unwrap();
        assert_eq!(job(&state, &response.job_id).await.venues_notified, Some(0));
        assert!(store.outbound().is_empty());
        let deliveries = stream.deliveries.lock().unwrap();
        assert_eq!(deliveries.len(), 1);
        assert_eq!(deliveries[0].sender_id, "venue-auto");
        assert!(deliveries[0].frozen);
    }

    #[tokio::test]
    async fn invalid_requests_are_rejected_without_a_job() {
        let (state, store, _) = state();
        for ids in [vec![], vec!["missing"]] {
            assert_eq!(
                notify(&state, HeaderMap::new(), &ids, "")
                    .await
                    .unwrap_err()
                    .status,
                StatusCode::UNPROCESSABLE_ENTITY
            );
        }
        let too_many = vec!["valid"; MAX_OPPORTUNITIES_PER_NOTIFICATION + 1];
        assert_eq!(
            notify(&state, HeaderMap::new(), &too_many, "")
                .await
                .unwrap_err()
                .status,
            StatusCode::UNPROCESSABLE_ENTITY
        );
        assert!(store.venue_notification_jobs.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn jobs_are_only_visible_to_their_performer() {
        let (state, _, _) = state();
        let response = notify(&state, HeaderMap::new(), &["valid"], "")
            .await
            .unwrap();
        let other = FirebaseUser {
            uid: "other".into(),
            email: None,
        };
        let error = get_venue_notification(State(state), other, Path(response.job_id))
            .await
            .unwrap_err();
        assert_eq!(error.status, StatusCode::NOT_FOUND);
    }
}
