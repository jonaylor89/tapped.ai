use axum::{Router, body::Bytes, http::HeaderMap, routing::post};
use std::sync::{Arc, Mutex};
use tapped_api_rs::domain::{
    mail_bridge::{EncodedAttachment, QueuedEmail},
    mail_worker::{submit_postmark, submit_smtp},
};
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    net::TcpListener,
};

#[tokio::test]
async fn worker_submits_thread_headers_and_body_over_smtp() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let captured = Arc::new(Mutex::new(String::new()));
    let server_capture = captured.clone();

    let server = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let (read, mut write) = socket.into_split();
        let mut read = BufReader::new(read);
        write.write_all(b"220 test SMTP\r\n").await.unwrap();
        loop {
            let mut line = String::new();
            if read.read_line(&mut line).await.unwrap() == 0 {
                break;
            }
            if line == "DATA\r\n" {
                write.write_all(b"354 continue\r\n").await.unwrap();
                loop {
                    line.clear();
                    read.read_line(&mut line).await.unwrap();
                    if line == ".\r\n" {
                        break;
                    }
                    server_capture.lock().unwrap().push_str(&line);
                }
                write.write_all(b"250 queued\r\n").await.unwrap();
            } else if line == "QUIT\r\n" {
                write.write_all(b"221 bye\r\n").await.unwrap();
                break;
            } else if line.starts_with("EHLO") {
                write
                    .write_all(b"250-test\r\n250 8BITMIME\r\n")
                    .await
                    .unwrap();
            } else {
                write.write_all(b"250 ok\r\n").await.unwrap();
            }
        }
    });

    submit_smtp(
        &address.to_string(),
        &QueuedEmail {
            event_id: "event-1".into(),
            thread_id: "thread-1".into(),
            from: "artist@booking.tapped.ai".into(),
            to: vec!["venue@example.com".into()],
            subject: "Performance Inquiry".into(),
            text_body: "Can we play?".into(),
            html_body: None,
            message_id: "<new@booking.tapped.ai>".into(),
            in_reply_to: "<old@example.com>".into(),
            references: "<old@example.com>".into(),
            attachments: vec![],
            encoded_attachments: vec![EncodedAttachment {
                name: "hello.txt".into(),
                content_type: "text/plain".into(),
                content: "aGVsbG8=".into(),
            }],
        },
    )
    .await
    .unwrap();
    server.await.unwrap();

    let message = captured.lock().unwrap();
    assert!(message.contains("From: artist@booking.tapped.ai\r\n"));
    assert!(message.contains("To: venue@example.com\r\n"));
    assert!(message.contains("Message-ID: <new@booking.tapped.ai>\r\n"));
    assert!(message.contains("In-Reply-To: <old@example.com>\r\n"));
    assert!(message.contains("References: <old@example.com>\r\n"));
    assert!(message.contains("Can we play?"));
    assert!(message.contains("filename=\"hello.txt\""));
    assert!(message.contains("aGVsbG8="));
}

#[tokio::test]
async fn worker_submits_threaded_email_through_postmark() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let captured = Arc::new(Mutex::new(None));
    let server_capture = captured.clone();
    let app = Router::new().route(
        "/email",
        post(move |headers: HeaderMap, body: Bytes| {
            let server_capture = server_capture.clone();
            async move {
                *server_capture.lock().unwrap() = Some((headers, body));
                r#"{"ErrorCode":0,"Message":"OK","MessageID":"postmark-id"}"#
            }
        }),
    );
    let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    let email = QueuedEmail {
        event_id: "event-2".into(),
        thread_id: "thread-2".into(),
        from: "artist@booking.tapped.ai".into(),
        to: vec!["venue@example.com".into()],
        subject: "Performance Inquiry".into(),
        text_body: "Can we play?".into(),
        html_body: Some("<p>Can we play?</p>".into()),
        message_id: "<new@booking.tapped.ai>".into(),
        in_reply_to: "<old@example.com>".into(),
        references: "<old@example.com>".into(),
        attachments: vec![],
        encoded_attachments: vec![EncodedAttachment {
            name: "hello.txt".into(),
            content_type: "text/plain".into(),
            content: "aGVsbG8=".into(),
        }],
    };

    submit_postmark(
        &reqwest::Client::new(),
        &format!("http://{address}/email"),
        "postmark-token",
        &email,
    )
    .await
    .unwrap();
    server.abort();

    let captured = captured.lock().unwrap();
    let (headers, body) = captured.as_ref().unwrap();
    assert_eq!(headers["x-postmark-server-token"], "postmark-token");
    let payload: serde_json::Value = serde_json::from_slice(body).unwrap();
    assert_eq!(payload["From"], "artist@booking.tapped.ai");
    assert_eq!(payload["To"], "venue@example.com");
    assert_eq!(payload["MessageStream"], "outbound");
    assert_eq!(payload["Attachments"][0]["Content"], "aGVsbG8=");
    assert!(payload["Headers"]
        .as_array()
        .unwrap()
        .iter()
        .any(|header| header["Name"] == "In-Reply-To" && header["Value"] == "<old@example.com>"));
}
