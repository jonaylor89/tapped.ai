use async_trait::async_trait;
use axum::{
    Json,
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};
use tapped_api_rs::{
    data::{database::Database, search::MockSearch},
    domain::{
        app_functions::{
            NotifyVenueOfInterestedOpportunities, get_venue_notification,
            notify_venue_of_interested_opportunities,
        },
        firebase_auth::FirebaseUser,
        mail_bridge::{MailBridge, MailStore, SqliteMailStore, StreamDelivery, StreamGateway},
        mail_composer::{ComposeVenueEmail, ComposedEmail, EmailComposer},
        models::{
            booking::{Booking, BookingStatus},
            opportunity::Opportunity,
            review::Review,
            user::UserModel,
        },
        venue_notifications::{JobStatus, process_due},
    },
    state::AppStateDyn,
};

use super::helpers::spawn_app;

struct GigDatabase;

#[async_trait]
impl Database for GigDatabase {
    async fn get_user_from_api_key(&self, _: &str) -> anyhow::Result<Option<String>> {
        Ok(None)
    }

    async fn get_user_by_id(&self, id: &str) -> anyhow::Result<UserModel> {
        Ok(serde_json::from_value(match id {
            "artist" => serde_json::json!({
                "id": id, "email": "artist@example.com", "username": "the-band", "deleted": false
            }),
            "venue" => serde_json::json!({
                "id": id, "email": "venue@example.com", "username": "the-venue", "deleted": false,
                "unclaimed": true, "venueInfo": {"bookingEmail": "booking@venue.example"}
            }),
            _ => serde_json::json!({
                "id": id, "email": "other@example.com", "username": "other act", "deleted": false
            }),
        })?)
    }

    async fn get_user_by_username(&self, _: &str) -> anyhow::Result<UserModel> {
        unreachable!()
    }

    async fn get_opportunity_by_id(&self, id: &str) -> anyhow::Result<Opportunity> {
        anyhow::ensure!(id == "gig", "not found");
        Ok(Opportunity {
            id: id.into(),
            user_id: "venue".into(),
            reference_event_id: Some("event".into()),
            title: "Friday showcase".into(),
            start_time: chrono::Utc::now(),
        })
    }

    async fn get_bookings_by_reference_event_id(&self, _: &str) -> anyhow::Result<Vec<Booking>> {
        Ok(vec![Booking {
            id: "booking".into(),
            name: String::new(),
            note: String::new(),
            requester_id: Some("venue".into()),
            requestee_id: "other".into(),
            status: BookingStatus::Confirmed,
            rate: 0.0,
            location: None,
            start_time: chrono::Utc::now(),
            end_time: chrono::Utc::now(),
            timestamp: chrono::Utc::now(),
            flier_url: None,
            event_url: None,
            venue_id: None,
            reference_event_id: Some("event".into()),
        }])
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

/// Fails while `down` is set, like an OpenAI outage.
#[derive(Default)]
struct FlakyComposer {
    down: AtomicBool,
}

#[async_trait]
impl EmailComposer for FlakyComposer {
    async fn compose(&self, request: ComposeVenueEmail) -> anyhow::Result<ComposedEmail> {
        anyhow::ensure!(!self.down.load(Ordering::SeqCst), "composer timed out");
        let body = format!("Hi {}", request.venue_name);
        Ok(ComposedEmail {
            subject: "Booking inquiry".into(),
            generated_body: body.clone(),
            text_body: body.clone(),
            html_body: body,
        })
    }
}

fn state(
    store: Arc<dyn MailStore>,
    stream: Arc<RecordingStream>,
    composer: Arc<FlakyComposer>,
) -> AppStateDyn {
    AppStateDyn {
        database: Arc::new(GigDatabase),
        search: Arc::new(MockSearch),
        firebase_project_id: "test".into(),
        mail: MailBridge {
            store,
            stream,
            stream_webhook_secret: "stream-secret".into(),
            ingress_secret: String::new(),
            service_secret: String::new(),
            booking_domain: "booking.tapped.ai".into(),
            composer,
            founder_cc: vec![],
            slack_webhook_url: None,
        },
        response_cache: Default::default(),
        places: Arc::new(tapped_api_rs::data::places::MockPlaces),
        spotify: Arc::new(tapped_api_rs::data::spotify::MockSpotify),
    }
}

fn artist() -> FirebaseUser {
    FirebaseUser {
        uid: "artist".into(),
        email: None,
    }
}

async fn apply(state: &AppStateDyn) -> (StatusCode, serde_json::Value) {
    let (status, Json(body)) = notify_venue_of_interested_opportunities(
        State(state.clone()),
        artist(),
        HeaderMap::new(),
        Json(NotifyVenueOfInterestedOpportunities {
            opportunity_ids: vec!["gig".into()],
            note: "We'd love to play".into(),
        }),
    )
    .await
    .unwrap();
    (status, serde_json::to_value(body).unwrap())
}

#[tokio::test]
async fn job_status_route_requires_firebase_authentication() {
    let app = spawn_app().await;
    let response = app
        .api_client
        .get(format!(
            "{}/app/v1/opportunity-venue-notifications/some-job",
            app.address
        ))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), reqwest::StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn queued_job_survives_a_restart_and_sends_one_email() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("mail.sqlite3");
    let path = path.to_str().unwrap();
    let stream = Arc::new(RecordingStream::default());
    let composer = Arc::new(FlakyComposer::default());

    let job_id = {
        let store = Arc::new(SqliteMailStore::open(path).unwrap());
        let (status, body) = apply(&state(store.clone(), stream.clone(), composer.clone())).await;
        assert_eq!(status, StatusCode::ACCEPTED);
        assert_eq!(body["status"], "queued");
        assert!(body["venues_notified"].is_null());
        assert!(store.claim_outbound(10).unwrap().is_empty());
        body["job_id"].as_str().unwrap().to_owned()
    };

    let store = Arc::new(SqliteMailStore::open(path).unwrap());
    let state = state(store.clone(), stream.clone(), composer);
    assert_eq!(process_due(&state).await.unwrap(), 1);
    let Json(job) = get_venue_notification(State(state.clone()), artist(), Path(job_id.clone()))
        .await
        .unwrap();
    assert_eq!(job.status, JobStatus::Completed);
    assert_eq!(job.venues_notified, Some(1));

    // The client retrying the same apply gets the finished job back and nothing is resent.
    let (status, body) = apply(&state).await;
    assert_eq!(status, StatusCode::ACCEPTED);
    assert_eq!(body["job_id"], job_id.as_str());
    assert_eq!(body["status"], "completed");
    assert_eq!(process_due(&state).await.unwrap(), 0);

    let queued = store.claim_outbound(10).unwrap();
    assert_eq!(queued.len(), 1);
    assert_eq!(queued[0].to, ["booking@venue.example"]);
    assert_eq!(queued[0].from, "the-band@booking.tapped.ai");
    assert_eq!(stream.deliveries.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn a_failed_composition_is_retried_later_without_blocking_the_request() {
    let directory = tempfile::tempdir().unwrap();
    let store = Arc::new(
        SqliteMailStore::open(directory.path().join("mail.sqlite3").to_str().unwrap()).unwrap(),
    );
    let composer = Arc::new(FlakyComposer::default());
    composer.down.store(true, Ordering::SeqCst);
    let state = state(
        store.clone(),
        Arc::new(RecordingStream::default()),
        composer,
    );

    let (status, body) = apply(&state).await;
    assert_eq!(status, StatusCode::ACCEPTED);
    assert_eq!(process_due(&state).await.unwrap(), 1);
    let Json(job) = get_venue_notification(
        State(state.clone()),
        artist(),
        Path(body["job_id"].as_str().unwrap().into()),
    )
    .await
    .unwrap();
    assert_eq!(job.status, JobStatus::Queued);
    // Backed off, so not immediately due again.
    assert_eq!(process_due(&state).await.unwrap(), 0);
    assert!(store.claim_outbound(10).unwrap().is_empty());
}
