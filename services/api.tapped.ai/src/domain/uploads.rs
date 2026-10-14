//! Presigned R2 uploads for user media (`POST /app/v1/uploads`).
//!
//! Clients hash the file, ask for an upload URL, `PUT` the bytes straight to R2, then save the
//! returned `url` on their profile or opportunity. Keys are content-addressed and owned by the
//! caller, so an upload can never replace another user's file. The presigned URL signs the body's
//! SHA-256 and length, so R2 rejects any other bytes.

use crate::{domain::firebase_auth::FirebaseUser, errors::AppError, state::AppStateDyn};
use axum::{Json, extract::State, http::StatusCode};
use chrono::{DateTime, Utc};
use hmac::{Hmac, KeyInit, Mac};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;

const UPLOAD_TTL_SECONDS: u32 = 600;
const MAX_UPLOAD_BYTES: u64 = 15 * 1024 * 1024;

/// R2 credentials and the public base URL of the media bucket (`https://media.tapped.ai`).
#[derive(Clone)]
pub struct MediaUploads {
    pub account_id: String,
    pub access_key_id: String,
    pub secret_access_key: String,
    pub bucket: String,
    pub public_base_url: String,
}

impl MediaUploads {
    /// `None` unless every `R2_*` variable is set; uploads then answer 503.
    pub fn from_env() -> Option<Self> {
        let var = |name| std::env::var(name).ok().filter(|v| !v.trim().is_empty());
        Some(Self {
            account_id: var("R2_ACCOUNT_ID")?,
            access_key_id: var("R2_ACCESS_KEY_ID")?,
            secret_access_key: var("R2_SECRET_ACCESS_KEY")?,
            bucket: var("R2_MEDIA_BUCKET").unwrap_or_else(|| "tapped-media".into()),
            public_base_url: var("MEDIA_PUBLIC_BASE_URL")
                .unwrap_or_else(|| "https://media.tapped.ai".into()),
        })
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum UploadKind {
    Avatar,
    OpportunityFlier,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct UploadRequest {
    pub kind: UploadKind,
    pub content_type: String,
    /// Lowercase hex SHA-256 of the exact bytes the client will `PUT`.
    pub sha256: String,
    pub size: u64,
    /// Required for `opportunityFlier`.
    pub opportunity_id: Option<String>,
}

#[derive(Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct UploadTicket {
    pub upload_url: String,
    pub method: &'static str,
    /// Send exactly these headers with the `PUT`.
    pub headers: BTreeMap<&'static str, String>,
    /// Public URL to save once the `PUT` succeeds.
    pub url: String,
    pub expires_at: DateTime<Utc>,
}

pub async fn create(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Json(request): Json<UploadRequest>,
) -> Result<Json<UploadTicket>, AppError> {
    let media = state.media.as_ref().ok_or_else(|| {
        AppError::new("uploads unavailable").with_status(StatusCode::SERVICE_UNAVAILABLE)
    })?;
    let ext = extension(&request.content_type).ok_or_else(|| {
        AppError::bad_request("contentType must be a JPEG, PNG, WebP or HEIC image")
    })?;
    if request.sha256.len() != 64
        || !request
            .sha256
            .bytes()
            .all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
    {
        return Err(AppError::bad_request(
            "sha256 must be 64 lowercase hex digits",
        ));
    }
    if request.size == 0 || request.size > MAX_UPLOAD_BYTES {
        return Err(AppError::bad_request("size must be 1 byte to 15 MB"));
    }
    let name = format!("{}.{ext}", &request.sha256[..32]);
    let key = match request.kind {
        UploadKind::Avatar => format!("users/{}/avatar/{name}", user.uid),
        UploadKind::OpportunityFlier => {
            let id = request
                .opportunity_id
                .as_deref()
                .filter(|id| is_safe_id(id))
                .ok_or_else(|| AppError::bad_request("opportunityId is required"))?;
            // A new opportunity has no row yet; an existing one must belong to the caller.
            let existing = state
                .database
                .get_opportunity_doc(id)
                .await
                .map_err(|e| AppError::internal("opportunity lookup failed", e))?;
            if let Some(doc) = existing
                && doc.get("userId").and_then(|v| v.as_str()) != Some(user.uid.as_str())
            {
                return Err(
                    AppError::new("not your opportunity").with_status(StatusCode::FORBIDDEN)
                );
            }
            format!("opportunities/{id}/flier/{name}")
        }
    };
    Ok(Json(presign_put(
        media,
        &key,
        &request.content_type,
        &request.sha256,
        request.size,
        Utc::now(),
    )))
}

fn extension(content_type: &str) -> Option<&'static str> {
    match content_type {
        "image/jpeg" => Some("jpg"),
        "image/png" => Some("png"),
        "image/webp" => Some("webp"),
        "image/heic" => Some("heic"),
        _ => None,
    }
}

fn is_safe_id(id: &str) -> bool {
    (1..=128).contains(&id.len())
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

fn presign_put(
    media: &MediaUploads,
    key: &str,
    content_type: &str,
    sha256: &str,
    size: u64,
    now: DateTime<Utc>,
) -> UploadTicket {
    let host = format!("{}.r2.cloudflarestorage.com", media.account_id);
    let path = format!("/{}/{}", media.bucket, encode_path(key));
    let headers = BTreeMap::from([
        ("content-length", size.to_string()),
        ("content-type", content_type.to_string()),
        ("x-amz-content-sha256", sha256.to_string()),
    ]);
    let query = presigned_query(
        &media.access_key_id,
        &media.secret_access_key,
        "auto",
        "s3",
        "PUT",
        &host,
        &path,
        &headers,
        // R2 always canonicalizes presigned requests as UNSIGNED-PAYLOAD; the signed
        // `x-amz-content-sha256` header is what pins the body.
        "UNSIGNED-PAYLOAD",
        now,
        UPLOAD_TTL_SECONDS,
    );
    UploadTicket {
        upload_url: format!("https://{host}{path}?{query}"),
        method: "PUT",
        headers,
        url: format!(
            "{}/{}",
            media.public_base_url.trim_end_matches('/'),
            encode_path(key)
        ),
        expires_at: now + chrono::Duration::seconds(UPLOAD_TTL_SECONDS.into()),
    }
}

/// AWS Signature V4 query string (`X-Amz-*` parameters) for a presigned request. `headers` are
/// signed alongside `host`, and `payload_hash` is the signed body hash (`UNSIGNED-PAYLOAD` allowed).
#[allow(clippy::too_many_arguments)]
fn presigned_query(
    access_key_id: &str,
    secret_access_key: &str,
    region: &str,
    service: &str,
    method: &str,
    host: &str,
    path: &str,
    headers: &BTreeMap<&str, String>,
    payload_hash: &str,
    now: DateTime<Utc>,
    expires: u32,
) -> String {
    let amz_date = now.format("%Y%m%dT%H%M%SZ").to_string();
    let date = now.format("%Y%m%d").to_string();
    let scope = format!("{date}/{region}/{service}/aws4_request");
    let mut all_headers: BTreeMap<&str, String> = headers.clone();
    all_headers.insert("host", host.to_string());
    let signed_headers = all_headers.keys().copied().collect::<Vec<_>>().join(";");
    let canonical_headers: String = all_headers
        .iter()
        .map(|(k, v)| format!("{k}:{}\n", v.trim()))
        .collect();
    let params = BTreeMap::from([
        ("X-Amz-Algorithm", "AWS4-HMAC-SHA256".to_string()),
        ("X-Amz-Credential", format!("{access_key_id}/{scope}")),
        ("X-Amz-Date", amz_date.clone()),
        ("X-Amz-Expires", expires.to_string()),
        ("X-Amz-SignedHeaders", signed_headers.clone()),
    ]);
    let canonical_query = |params: &BTreeMap<&str, String>| {
        params
            .iter()
            .map(|(k, v)| format!("{}={}", encode(k), encode(v)))
            .collect::<Vec<_>>()
            .join("&")
    };
    let canonical_request = format!(
        "{method}\n{path}\n{}\n{canonical_headers}\n{signed_headers}\n{payload_hash}",
        canonical_query(&params)
    );
    let string_to_sign = format!(
        "AWS4-HMAC-SHA256\n{amz_date}\n{scope}\n{}",
        hex::encode(Sha256::digest(canonical_request.as_bytes()))
    );
    let mut key = hmac(
        format!("AWS4{secret_access_key}").as_bytes(),
        date.as_bytes(),
    );
    for part in [region, service, "aws4_request"] {
        key = hmac(&key, part.as_bytes());
    }
    let signature = hex::encode(hmac(&key, string_to_sign.as_bytes()));
    format!("{}&X-Amz-Signature={signature}", canonical_query(&params))
}

fn hmac(key: &[u8], data: &[u8]) -> Vec<u8> {
    let mut mac = Hmac::<Sha256>::new_from_slice(key).expect("HMAC accepts any key length");
    mac.update(data);
    mac.finalize().into_bytes().to_vec()
}

/// RFC 3986 percent-encoding as SigV4 requires (unreserved characters pass through).
fn encode(value: &str) -> String {
    value
        .bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                (b as char).to_string()
            }
            _ => format!("%{b:02X}"),
        })
        .collect()
}

fn encode_path(key: &str) -> String {
    key.split('/').map(encode).collect::<Vec<_>>().join("/")
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    /// The presigned GET example from the AWS SigV4 documentation.
    #[test]
    fn matches_aws_presigned_url_example() {
        let query = presigned_query(
            "AKIAIOSFODNN7EXAMPLE",
            "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            "us-east-1",
            "s3",
            "GET",
            "examplebucket.s3.amazonaws.com",
            "/test.txt",
            &BTreeMap::new(),
            "UNSIGNED-PAYLOAD",
            Utc.with_ymd_and_hms(2013, 5, 24, 0, 0, 0).unwrap(),
            86_400,
        );
        assert!(query.ends_with(
            "X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404"
        ));
        assert!(query.contains(
            "X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request"
        ));
    }

    fn media() -> MediaUploads {
        MediaUploads {
            account_id: "acct".into(),
            access_key_id: "key".into(),
            secret_access_key: "secret".into(),
            bucket: "tapped-media".into(),
            public_base_url: "https://media.tapped.ai/".into(),
        }
    }

    #[test]
    fn ticket_signs_body_hash_length_and_type() {
        let sha = "a".repeat(64);
        let ticket = presign_put(
            &media(),
            "users/u1/avatar/x.jpg",
            "image/jpeg",
            &sha,
            42,
            Utc::now(),
        );
        assert!(ticket.upload_url.starts_with(
            "https://acct.r2.cloudflarestorage.com/tapped-media/users/u1/avatar/x.jpg?"
        ));
        assert!(ticket.upload_url.contains(
            "X-Amz-SignedHeaders=content-length%3Bcontent-type%3Bhost%3Bx-amz-content-sha256"
        ));
        assert_eq!(ticket.url, "https://media.tapped.ai/users/u1/avatar/x.jpg");
        assert_eq!(ticket.headers["content-length"], "42");
        assert_eq!(ticket.headers["x-amz-content-sha256"], sha);
    }

    #[test]
    fn rejects_unsafe_ids_and_types() {
        assert!(is_safe_id("6c7ef95c-4ad9-44e5-af5a-a832d6c8790d"));
        assert!(!is_safe_id("../users"));
        assert!(!is_safe_id(""));
        assert_eq!(extension("image/jpeg"), Some("jpg"));
        assert_eq!(extension("text/html"), None);
    }
}
