use crate::helpers::spawn_app;
use std::sync::{Arc, Mutex};
use tapped_api_rs::tracing::get_subscriber;
use uuid::Uuid;

#[derive(Clone, Default)]
struct CapturedLogs(Arc<Mutex<Vec<u8>>>);

impl std::io::Write for CapturedLogs {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.0.lock().unwrap().extend_from_slice(buf);
        Ok(buf.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

impl<'a> tracing_subscriber::fmt::MakeWriter<'a> for CapturedLogs {
    type Writer = Self;

    fn make_writer(&'a self) -> Self::Writer {
        self.clone()
    }
}

impl CapturedLogs {
    fn lines(&self) -> Vec<serde_json::Value> {
        String::from_utf8(self.0.lock().unwrap().clone())
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect()
    }
}

#[tokio::test]
async fn echoes_a_valid_incoming_request_id() {
    let app = spawn_app().await;
    let response = app
        .api_client
        .get(format!("{}/health", app.address))
        .header("x-request-id", "ios-4f1c2b8e")
        .send()
        .await
        .unwrap();
    assert_eq!(response.headers()["x-request-id"], "ios-4f1c2b8e");
}

#[tokio::test]
async fn generates_a_uuid_when_the_request_id_is_missing_or_invalid() {
    let app = spawn_app().await;
    for header in [None, Some("has spaces"), Some("")] {
        let mut request = app.api_client.get(format!("{}/health", app.address));
        if let Some(header) = header {
            request = request.header("x-request-id", header);
        }
        let response = request.send().await.unwrap();
        let id = response.headers()["x-request-id"].to_str().unwrap();
        assert!(Uuid::parse_str(id).is_ok(), "{header:?} -> {id}");
    }
}

#[tokio::test]
async fn error_responses_carry_the_request_id() {
    let app = spawn_app().await;
    let response = app
        .api_client
        .get(format!("{}/nope", app.address))
        .header("x-request-id", "trace-404")
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), 404);
    assert_eq!(response.headers()["x-request-id"], "trace-404");
}

// `#[tokio::test]` runs the server on this thread, so the thread-local subscriber sees its logs.
#[tokio::test]
async fn logs_request_id_route_status_and_latency() {
    let logs = CapturedLogs::default();
    let _guard = tracing::subscriber::set_default(get_subscriber(
        "test".into(),
        "info".into(),
        logs.clone(),
    ));
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(format!("{}/app/v1/opportunities/opp-1", app.address))
        .header("x-request-id", "trace-latency")
        .send()
        .await
        .unwrap();
    assert!(response.status().is_success());

    let lines = logs.lines();
    let completed = lines
        .iter()
        .find(|line| {
            line["msg"]
                .as_str()
                .is_some_and(|msg| msg.ends_with("request completed"))
                && line["request_id"] == "trace-latency"
        })
        .unwrap_or_else(|| panic!("no request log line in {lines:#?}"));
    assert_eq!(
        completed["matched_path"],
        "/app/v1/opportunities/:opportunity_id"
    );
    assert_eq!(completed["method"], "GET");
    assert_eq!(completed["status"], 200);
    assert!(completed["latency_ms"].as_f64().unwrap() >= 0.0);
}
