use async_trait::async_trait;
use hmac::{Hmac, Mac};
use sha2::Sha256;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicUsize, Ordering},
};
use tapped_api_rs::{
    data::{database::MockDatabase, search::MockSearch},
    domain::mail_bridge::{
        EmailThread, InMemoryMailStore, MailBridge, MailStore, QueuedEmail, SqliteMailStore,
        StreamDelivery, StreamGateway,
    },
    state::AppStateDyn,
};

use super::helpers::spawn_app_with_state;

type HmacSha256 = Hmac<Sha256>;

#[derive(Default)]
struct RecordingStream {
    deliveries: Mutex<Vec<StreamDelivery>>,
    failures_remaining: AtomicUsize,
}

#[async_trait]
impl StreamGateway for RecordingStream {
    async fn send_message(&self, delivery: &StreamDelivery) -> anyhow::Result<()> {
        if self
            .failures_remaining
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |remaining| {
                remaining.checked_sub(1)
            })
            .is_ok()
        {
            anyhow::bail!("temporary Stream failure");
        }
        self.deliveries.lock().unwrap().push(delivery.clone());
        Ok(())
    }
}

fn sign(secret: &str, body: &[u8]) -> String {
    let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).unwrap();
    mac.update(body);
    hex::encode(mac.finalize().into_bytes())
}

async fn test_app() -> (
    super::helpers::TestApp,
    Arc<InMemoryMailStore>,
    Arc<RecordingStream>,
) {
    let store = Arc::new(InMemoryMailStore::default());
    store
        .upsert_thread(EmailThread {
            id: "thread-1".into(),
            performer_id: "artist-1".into(),
            performer_username: "the-band".into(),
            venue_id: "venue-1".into(),
            recipients: vec!["bookings@venue.example".into()],
            subject: "Performance Inquiry from The Band".into(),
            latest_message_id: "<initial@booking.tapped.ai>".into(),
        })
        .await
        .unwrap();
    let stream = Arc::new(RecordingStream::default());
    let state = AppStateDyn {
        database: Arc::new(MockDatabase),
        search: Arc::new(MockSearch),
        firebase_project_id: "test-project".into(),
        mail: MailBridge {
            store: store.clone(),
            stream: stream.clone(),
            stream_webhook_secret: "stream-secret".into(),
            ingress_secret: "ingress-secret".into(),
            service_secret: "service-secret".into(),
            booking_domain: "booking.tapped.ai".into(),
        },
    };
    (spawn_app_with_state(state).await, store, stream)
}

fn stream_payload() -> Vec<u8> {
    serde_json::to_vec(&serde_json::json!({
        "user": {"id": "artist-1", "username": "the-band"},
        "members": [
            {"user": {"id": "artist-1", "username": "the-band"}},
            {"user": {"id": "venue-1", "username": "venue"}}
        ],
        "message": {
            "id": "stream-message-1",
            "text": "Could we play next Friday?",
            "attachments": [{"image_url": "https://cdn.example/poster.jpg"}]
        }
    }))
    .unwrap()
}

#[tokio::test]
async fn sqlite_outbox_survives_process_restart_and_claims_once() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("mail.sqlite3");
    {
        let store = SqliteMailStore::open(path.to_str().unwrap()).unwrap();
        let thread = EmailThread {
            id: "durable-thread".into(),
            performer_id: "artist".into(),
            performer_username: "artist-name".into(),
            venue_id: "venue".into(),
            recipients: vec!["venue@example.com".into()],
            subject: "Inquiry".into(),
            latest_message_id: "<durable@booking.tapped.ai>".into(),
        };
        let email = QueuedEmail {
            event_id: "durable-event".into(),
            thread_id: thread.id.clone(),
            from: "artist-name@booking.tapped.ai".into(),
            to: thread.recipients.clone(),
            subject: thread.subject.clone(),
            text_body: "Hello".into(),
            html_body: None,
            message_id: thread.latest_message_id.clone(),
            in_reply_to: String::new(),
            references: String::new(),
            attachments: vec![],
            encoded_attachments: vec![],
        };
        assert!(
            store
                .create_thread_and_enqueue(thread, email)
                .await
                .unwrap()
        );
    }
    let reopened = SqliteMailStore::open(path.to_str().unwrap()).unwrap();
    let claimed = reopened.claim_outbound(10).unwrap();
    assert_eq!(claimed.len(), 1);
    assert_eq!(claimed[0].event_id, "durable-event");
    reopened.mark_outbound_sent("durable-event").unwrap();
    assert!(reopened.claim_outbound(10).unwrap().is_empty());
}

#[tokio::test]
async fn existing_thread_id_cannot_be_reassigned_to_another_performer() {
    let directory = tempfile::tempdir().unwrap();
    let store =
        SqliteMailStore::open(directory.path().join("mail.sqlite3").to_str().unwrap()).unwrap();
    let make_thread = |performer_id: &str| EmailThread {
        id: "shared-thread-id".into(),
        performer_id: performer_id.into(),
        performer_username: performer_id.into(),
        venue_id: "venue".into(),
        recipients: vec!["venue@example.com".into()],
        subject: "Inquiry".into(),
        latest_message_id: format!("<{performer_id}@booking.tapped.ai>"),
    };
    let make_email = |thread: &EmailThread, event_id: &str| QueuedEmail {
        event_id: event_id.into(),
        thread_id: thread.id.clone(),
        from: format!("{}@booking.tapped.ai", thread.performer_username),
        to: thread.recipients.clone(),
        subject: thread.subject.clone(),
        text_body: "Hello".into(),
        html_body: None,
        message_id: thread.latest_message_id.clone(),
        in_reply_to: String::new(),
        references: String::new(),
        attachments: vec![],
        encoded_attachments: vec![],
    };

    let original = make_thread("artist-1");
    store
        .create_thread_and_enqueue(original.clone(), make_email(&original, "event-1"))
        .await
        .unwrap();
    let attacker = make_thread("artist-2");
    assert!(
        store
            .create_thread_and_enqueue(attacker.clone(), make_email(&attacker, "event-2"))
            .await
            .is_err()
    );
    assert!(
        store
            .thread_for_stream("artist-2", "venue")
            .await
            .unwrap()
            .is_none()
    );
    assert_eq!(store.claim_outbound(10).unwrap().len(), 1);
}

#[tokio::test]
async fn creating_email_thread_requires_firebase_authentication() {
    let (app, store, _) = test_app().await;
    let response = app
        .api_client
        .post(format!("{}/app/v1/venue-email-threads", app.address))
        .json(&serde_json::json!({
            "id": "new-thread", "venue_id": "venue-1", "performer_username": "the-band",
            "recipients": ["venue@example.com"], "subject": "Inquiry", "text_body": "Hello"
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), reqwest::StatusCode::UNAUTHORIZED);
    assert!(store.outbound().is_empty());
}

#[tokio::test]
async fn stream_message_is_queued_as_a_threaded_email() {
    let (app, store, _) = test_app().await;
    let body = stream_payload();
    let response = app
        .api_client
        .post(format!("{}/webhooks/stream/before-message", app.address))
        .header("x-signature", sign("stream-secret", &body))
        .body(body)
        .send()
        .await
        .unwrap();

    assert_eq!(response.status(), reqwest::StatusCode::OK);
    let queued = store.outbound();
    assert_eq!(queued.len(), 1);
    assert_eq!(queued[0].from, "the-band@booking.tapped.ai");
    assert_eq!(queued[0].to, vec!["bookings@venue.example"]);
    assert_eq!(queued[0].in_reply_to, "<initial@booking.tapped.ai>");
    assert_eq!(queued[0].references, "<initial@booking.tapped.ai>");
    assert_eq!(
        queued[0].attachments,
        vec!["https://cdn.example/poster.jpg"]
    );
}

#[tokio::test]
async fn duplicate_stream_webhook_does_not_queue_duplicate_email() {
    let (app, store, _) = test_app().await;
    let body = stream_payload();
    for _ in 0..2 {
        let response = app
            .api_client
            .post(format!("{}/webhooks/stream/before-message", app.address))
            .header("x-signature", sign("stream-secret", &body))
            .body(body.clone())
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), reqwest::StatusCode::OK);
    }
    assert_eq!(store.outbound().len(), 1);
}

#[tokio::test]
async fn signed_service_email_is_queued_without_postmark() {
    let (app, store, _) = test_app().await;
    let body = serde_json::to_vec(&serde_json::json!({
        "From": "no-reply@tapped.ai", "To": "fan@example.com", "Subject": "Welcome",
        "HtmlBody": "<strong>Hello</strong>", "MessageStream": "outbound",
        "Headers": [{"Name": "Message-ID", "Value": "<welcome-1@tapped.ai>"}],
        "Attachments": [{"Name": "hello.txt", "ContentType": "text/plain", "Content": "aGVsbG8="}]
    }))
    .unwrap();
    let timestamp = chrono::Utc::now().timestamp().to_string();
    let signed = [timestamp.as_bytes(), b".", b"", b".", body.as_slice()].concat();
    let response = app
        .api_client
        .post(format!("{}/internal/mail/outbound", app.address))
        .header("x-tapped-timestamp", &timestamp)
        .header("x-tapped-signature", sign("service-secret", &signed))
        .body(body)
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), reqwest::StatusCode::ACCEPTED);
    let queued = store.outbound();
    assert_eq!(queued.len(), 1);
    assert_eq!(
        queued[0].html_body.as_deref(),
        Some("<strong>Hello</strong>")
    );
    assert_eq!(queued[0].encoded_attachments[0].name, "hello.txt");
}

#[tokio::test]
async fn invalid_stream_signature_is_rejected() {
    let (app, store, _) = test_app().await;
    let response = app
        .api_client
        .post(format!("{}/webhooks/stream/before-message", app.address))
        .header("x-signature", "bad")
        .body(stream_payload())
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), reqwest::StatusCode::UNAUTHORIZED);
    assert!(store.outbound().is_empty());
}

#[tokio::test]
async fn email_reply_is_delivered_to_stream_exactly_once() {
    let (app, store, stream) = test_app().await;
    let stream_body = stream_payload();
    app.api_client
        .post(format!("{}/webhooks/stream/before-message", app.address))
        .header("x-signature", sign("stream-secret", &stream_body))
        .body(stream_body)
        .send()
        .await
        .unwrap();
    let outbound_message_id = store.outbound()[0].message_id.clone();

    let raw_email = format!(
        "From: Booker <bookings@venue.example>\r\nTo: the-band@booking.tapped.ai\r\nSubject: Re: Performance Inquiry\r\nMessage-ID: <venue-reply-1@venue.example>\r\nIn-Reply-To: {outbound_message_id}\r\nReferences: <initial@booking.tapped.ai> {outbound_message_id}\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nYes, Friday works.\r\n"
    ).into_bytes();
    let timestamp = chrono::Utc::now().timestamp().to_string();
    let signed = [timestamp.as_bytes(), b".", b"", b".", raw_email.as_slice()].concat();

    for _ in 0..2 {
        let response = app
            .api_client
            .post(format!("{}/internal/mail/inbound", app.address))
            .header("x-tapped-timestamp", &timestamp)
            .header("x-tapped-signature", sign("ingress-secret", &signed))
            .body(raw_email.clone())
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), reqwest::StatusCode::OK);
    }

    let deliveries = stream.deliveries.lock().unwrap();
    assert_eq!(deliveries.len(), 1);
    assert_eq!(deliveries[0].sender_id, "venue-1");
    assert_eq!(deliveries[0].receiver_id, "artist-1");
    assert_eq!(deliveries[0].text, "Yes, Friday works.");
}

#[tokio::test]
async fn signed_smtp_envelope_recipient_takes_precedence_over_to_header() {
    let (app, _, stream) = test_app().await;
    let raw = b"From: venue@example.com\r\nTo: somebody-else@example.com\r\nMessage-ID: <envelope@venue.example>\r\nIn-Reply-To: <initial@booking.tapped.ai>\r\n\r\nEnvelope routed".to_vec();
    let timestamp = chrono::Utc::now().timestamp().to_string();
    let envelope = "the-band@booking.tapped.ai";
    let signed = [
        timestamp.as_bytes(),
        b".",
        envelope.as_bytes(),
        b".",
        raw.as_slice(),
    ]
    .concat();
    let response = app
        .api_client
        .post(format!("{}/internal/mail/inbound", app.address))
        .header("x-tapped-timestamp", &timestamp)
        .header("x-tapped-envelope-to", envelope)
        .header("x-tapped-signature", sign("ingress-secret", &signed))
        .body(raw)
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), reqwest::StatusCode::OK);
    assert_eq!(stream.deliveries.lock().unwrap()[0].text, "Envelope routed");
}

#[tokio::test]
async fn failed_stream_delivery_is_retried_without_losing_email() {
    let (app, store, stream) = test_app().await;
    let stream_body = stream_payload();
    app.api_client
        .post(format!("{}/webhooks/stream/before-message", app.address))
        .header("x-signature", sign("stream-secret", &stream_body))
        .body(stream_body)
        .send()
        .await
        .unwrap();
    let parent = store.outbound()[0].message_id.clone();
    let raw = format!(
        "From: Booker <bookings@venue.example>\r\nTo: the-band@booking.tapped.ai\r\nMessage-ID: <retry@venue.example>\r\nIn-Reply-To: {parent}\r\n\r\nRetry me"
    ).into_bytes();
    let timestamp = chrono::Utc::now().timestamp().to_string();
    let signed = [timestamp.as_bytes(), b".", b"", b".", raw.as_slice()].concat();
    stream.failures_remaining.store(1, Ordering::SeqCst);

    let first = app
        .api_client
        .post(format!("{}/internal/mail/inbound", app.address))
        .header("x-tapped-timestamp", &timestamp)
        .header("x-tapped-signature", sign("ingress-secret", &signed))
        .body(raw.clone())
        .send()
        .await
        .unwrap();
    assert_eq!(first.status(), reqwest::StatusCode::SERVICE_UNAVAILABLE);

    let second = app
        .api_client
        .post(format!("{}/internal/mail/inbound", app.address))
        .header("x-tapped-timestamp", &timestamp)
        .header("x-tapped-signature", sign("ingress-secret", &signed))
        .body(raw)
        .send()
        .await
        .unwrap();
    assert_eq!(second.status(), reqwest::StatusCode::OK);
    assert_eq!(stream.deliveries.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn stale_or_invalid_ingress_signatures_are_rejected() {
    let (app, _, stream) = test_app().await;
    let raw = b"From: x@example.com\r\nTo: the-band@booking.tapped.ai\r\nMessage-ID: <x@example.com>\r\nIn-Reply-To: <initial@booking.tapped.ai>\r\n\r\nHello".to_vec();
    let stale = (chrono::Utc::now().timestamp() - 301).to_string();
    let stale_signed = [stale.as_bytes(), b".", b"", b".", raw.as_slice()].concat();
    let stale_response = app
        .api_client
        .post(format!("{}/internal/mail/inbound", app.address))
        .header("x-tapped-timestamp", &stale)
        .header("x-tapped-signature", sign("ingress-secret", &stale_signed))
        .body(raw.clone())
        .send()
        .await
        .unwrap();
    assert_eq!(stale_response.status(), reqwest::StatusCode::UNAUTHORIZED);

    let current = chrono::Utc::now().timestamp().to_string();
    let invalid_response = app
        .api_client
        .post(format!("{}/internal/mail/inbound", app.address))
        .header("x-tapped-timestamp", current)
        .header("x-tapped-signature", "00")
        .body(raw)
        .send()
        .await
        .unwrap();
    assert_eq!(invalid_response.status(), reqwest::StatusCode::UNAUTHORIZED);
    assert!(stream.deliveries.lock().unwrap().is_empty());
}

#[tokio::test]
async fn inbound_email_with_unknown_thread_is_persisted_but_not_delivered() {
    let (app, store, stream) = test_app().await;
    let raw_email = b"From: x@example.com\r\nTo: the-band@booking.tapped.ai\r\nMessage-ID: <unknown@example.com>\r\nIn-Reply-To: <missing@booking.tapped.ai>\r\n\r\nHello".to_vec();
    let timestamp = chrono::Utc::now().timestamp().to_string();
    let signed = [timestamp.as_bytes(), b".", b"", b".", raw_email.as_slice()].concat();
    let response = app
        .api_client
        .post(format!("{}/internal/mail/inbound", app.address))
        .header("x-tapped-timestamp", &timestamp)
        .header("x-tapped-signature", sign("ingress-secret", &signed))
        .body(raw_email)
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), reqwest::StatusCode::NOT_FOUND);
    assert!(stream.deliveries.lock().unwrap().is_empty());
    assert_eq!(store.orphan_count(), 1);
}
