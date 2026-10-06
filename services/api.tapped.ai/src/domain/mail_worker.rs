use anyhow::{Context, bail};
use base64::{Engine, engine::general_purpose::STANDARD};
use reqwest::Client;
use serde::Serialize;
use std::sync::Arc;
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    net::TcpStream,
    time::{Duration, sleep},
};
use uuid::Uuid;

use super::mail_bridge::{EncodedAttachment, QueuedEmail, SqliteMailStore};

const POSTMARK_EMAIL_ENDPOINT: &str = "https://api.postmarkapp.com/email";

#[derive(Clone)]
pub enum MailTransport {
    Smtp {
        address: String,
    },
    Postmark {
        client: Client,
        server_token: String,
    },
}

fn safe_header(value: &str) -> String {
    value.replace(['\r', '\n'], " ")
}

const DOWNLOAD_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(60);

async fn download_attachments(email: &QueuedEmail) -> anyhow::Result<Vec<EncodedAttachment>> {
    let mut attachments = email.encoded_attachments.clone();
    for (index, url) in email.attachments.iter().enumerate() {
        let response = crate::http::client_with_timeout(DOWNLOAD_TIMEOUT)
            .get(url)
            .send()
            .await?
            .error_for_status()?;
        let content_type = response
            .headers()
            .get(reqwest::header::CONTENT_TYPE)
            .and_then(|value| value.to_str().ok())
            .unwrap_or("application/octet-stream")
            .to_owned();
        attachments.push(EncodedAttachment {
            name: format!("attachment-{}", index + 1),
            content_type,
            content: STANDARD.encode(response.bytes().await?),
        });
    }
    Ok(attachments)
}

async fn render_email(email: &QueuedEmail) -> anyhow::Result<Vec<u8>> {
    let boundary = format!("tapped-{}", Uuid::new_v4());
    let (body_type, body) = email
        .html_body
        .as_ref()
        .map(|html| ("text/html", html.as_str()))
        .unwrap_or(("text/plain", email.text_body.as_str()));
    let mut message = format!(
        "From: {}\r\nTo: {}\r\nCc: {}\r\nSubject: {}\r\nMessage-ID: {}\r\n",
        safe_header(&email.from),
        safe_header(&email.to.join(", ")),
        safe_header(&email.cc.join(", ")),
        safe_header(&email.subject),
        safe_header(&email.message_id),
    );
    if !email.in_reply_to.is_empty() {
        message.push_str(&format!(
            "In-Reply-To: {}\r\n",
            safe_header(&email.in_reply_to)
        ));
    }
    if !email.references.is_empty() {
        message.push_str(&format!(
            "References: {}\r\n",
            safe_header(&email.references)
        ));
    }
    message.push_str(&format!(
        "MIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=\"{}\"\r\n\r\n--{}\r\nContent-Type: {}; charset=utf-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\n{}\r\n",
        boundary,
        boundary,
        body_type,
        body.replace('\n', "\r\n"),
    ));

    for attachment in download_attachments(email).await? {
        let wrapped = attachment
            .content
            .as_bytes()
            .chunks(76)
            .map(|chunk| String::from_utf8_lossy(chunk).into_owned())
            .collect::<Vec<_>>()
            .join("\r\n");
        message.push_str(&format!(
            "--{}\r\nContent-Type: {}\r\nContent-Disposition: attachment; filename=\"{}\"\r\nContent-Transfer-Encoding: base64\r\n\r\n{}\r\n",
            boundary,
            safe_header(&attachment.content_type),
            safe_header(&attachment.name),
            wrapped,
        ));
    }
    message.push_str(&format!("--{}--\r\n", boundary));
    Ok(message.into_bytes())
}

async fn expect_success(
    reader: &mut BufReader<tokio::net::tcp::OwnedReadHalf>,
) -> anyhow::Result<()> {
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).await? == 0 {
            bail!("SMTP server disconnected")
        }
        if line.len() >= 4 && line.as_bytes()[3] == b' ' {
            let code: u16 = line[..3].parse().context("invalid SMTP response")?;
            if code >= 400 {
                bail!("SMTP rejected request: {}", line.trim())
            }
            return Ok(());
        }
    }
}

async fn command(
    writer: &mut tokio::net::tcp::OwnedWriteHalf,
    reader: &mut BufReader<tokio::net::tcp::OwnedReadHalf>,
    command: &str,
) -> anyhow::Result<()> {
    writer.write_all(command.as_bytes()).await?;
    writer.write_all(b"\r\n").await?;
    writer.flush().await?;
    expect_success(reader).await
}

pub async fn submit_smtp(address: &str, email: &QueuedEmail) -> anyhow::Result<()> {
    let stream = TcpStream::connect(address).await?;
    let (read, mut write) = stream.into_split();
    let mut read = BufReader::new(read);
    expect_success(&mut read).await?;
    command(&mut write, &mut read, "EHLO api.tapped.ai").await?;
    command(
        &mut write,
        &mut read,
        &format!("MAIL FROM:<{}>", safe_header(&email.from)),
    )
    .await?;
    for recipient in email.to.iter().chain(&email.cc) {
        command(
            &mut write,
            &mut read,
            &format!("RCPT TO:<{}>", safe_header(recipient)),
        )
        .await?;
    }
    command(&mut write, &mut read, "DATA").await?;
    let mime = render_email(email).await?;
    for line in mime.split(|byte| *byte == b'\n') {
        if line.first() == Some(&b'.') {
            write.write_all(b".").await?;
        }
        write.write_all(line).await?;
        if !line.ends_with(b"\r") {
            write.write_all(b"\r").await?;
        }
        write.write_all(b"\n").await?;
    }
    write.write_all(b".\r\n").await?;
    write.flush().await?;
    expect_success(&mut read).await?;
    let _ = command(&mut write, &mut read, "QUIT").await;
    Ok(())
}

#[derive(Serialize)]
#[serde(rename_all = "PascalCase")]
struct PostmarkHeader {
    name: String,
    value: String,
}

#[derive(Serialize)]
#[serde(rename_all = "PascalCase")]
struct PostmarkAttachment {
    name: String,
    content: String,
    content_type: String,
}

#[derive(Serialize)]
#[serde(rename_all = "PascalCase")]
struct PostmarkEmail {
    from: String,
    to: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    cc: String,
    subject: String,
    text_body: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    html_body: Option<String>,
    headers: Vec<PostmarkHeader>,
    attachments: Vec<PostmarkAttachment>,
    message_stream: &'static str,
}

pub async fn submit_postmark(
    client: &Client,
    endpoint: &str,
    server_token: &str,
    email: &QueuedEmail,
) -> anyhow::Result<()> {
    let mut headers = vec![PostmarkHeader {
        name: "Message-ID".into(),
        value: email.message_id.clone(),
    }];
    if !email.in_reply_to.is_empty() {
        headers.push(PostmarkHeader {
            name: "In-Reply-To".into(),
            value: email.in_reply_to.clone(),
        });
    }
    if !email.references.is_empty() {
        headers.push(PostmarkHeader {
            name: "References".into(),
            value: email.references.clone(),
        });
    }
    let attachments = download_attachments(email)
        .await?
        .into_iter()
        .map(|attachment| PostmarkAttachment {
            name: attachment.name,
            content: attachment.content,
            content_type: attachment.content_type,
        })
        .collect();
    let payload = PostmarkEmail {
        from: email.from.clone(),
        to: email.to.join(","),
        cc: email.cc.join(","),
        subject: email.subject.clone(),
        text_body: email.text_body.clone(),
        html_body: email.html_body.clone(),
        headers,
        attachments,
        message_stream: "outbound",
    };
    let response = client
        .post(endpoint)
        .header("X-Postmark-Server-Token", server_token)
        .json(&payload)
        .send()
        .await?;
    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        bail!("Postmark rejected email ({status}): {body}")
    }
    Ok(())
}

pub async fn run_worker(store: Arc<SqliteMailStore>, transport: MailTransport) -> ! {
    loop {
        match store.claim_outbound(20) {
            Ok(messages) if messages.is_empty() => sleep(Duration::from_secs(2)).await,
            Ok(messages) => {
                for message in messages {
                    let result = match &transport {
                        MailTransport::Smtp { address } => submit_smtp(address, &message).await,
                        MailTransport::Postmark {
                            client,
                            server_token,
                        } => {
                            submit_postmark(client, POSTMARK_EMAIL_ENDPOINT, server_token, &message)
                                .await
                        }
                    };
                    match result {
                        Ok(()) => {
                            if let Err(error) = store.mark_outbound_sent(&message.event_id) {
                                tracing::error!(
                                    ?error,
                                    event_id = message.event_id,
                                    "failed to mark email sent"
                                );
                            }
                        }
                        Err(error) => {
                            tracing::error!(
                                ?error,
                                event_id = message.event_id,
                                "mail submission failed"
                            );
                            let _ = store.mark_outbound_failed(&message.event_id);
                        }
                    }
                }
            }
            Err(error) => {
                tracing::error!(?error, "failed to claim email outbox");
                sleep(Duration::from_secs(5)).await;
            }
        }
    }
}
