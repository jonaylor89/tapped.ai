//! Google identity/FCM only. The worker principal has no Firestore permissions.
use anyhow::{Result, anyhow, ensure};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    sync::Arc,
    time::{Duration, Instant},
};
use tokio::sync::Mutex;

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Account {
    pub local_id: String,
    #[serde(default)]
    pub email: String,
    #[serde(default)]
    pub display_name: String,
    #[serde(default)]
    pub created_at: String,
}
impl Account {
    pub fn created_ms(&self) -> i64 {
        // Gen1 Auth events carry whole-second creation times; REST snapshots retain
        // milliseconds. Use their common precision so both sources share one lifecycle key.
        self.created_at.parse::<i64>().unwrap_or_default() / 1000 * 1000
    }
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountPage {
    #[serde(default)]
    pub users: Vec<Account>,
    #[serde(default)]
    pub next_page_token: String,
}
#[derive(Deserialize)]
struct Credentials {
    client_email: String,
    private_key: String,
    project_id: String,
}
#[derive(Deserialize)]
struct AccessToken {
    access_token: String,
    expires_in: u64,
}
struct CachedToken {
    value: String,
    expires: Instant,
}
#[derive(Clone)]
pub struct GoogleIdentity {
    client: reqwest::Client,
    email: String,
    key: Arc<jsonwebtoken::EncodingKey>,
    project: String,
    token: Arc<Mutex<Option<CachedToken>>>,
}
impl GoogleIdentity {
    pub fn new(file: &str, project: &str) -> Result<Self> {
        let c: Credentials = serde_json::from_slice(
            &std::fs::read(file).map_err(|_| anyhow!("identity credential file unavailable"))?,
        )
        .map_err(|_| anyhow!("invalid identity credential file"))?;
        ensure!(
            c.project_id == project && c.client_email.ends_with(".iam.gserviceaccount.com"),
            "identity credential project mismatch"
        );
        let key = jsonwebtoken::EncodingKey::from_rsa_pem(c.private_key.as_bytes())
            .map_err(|_| anyhow!("invalid identity signing key"))?;
        Ok(Self {
            client: reqwest::Client::builder()
                .timeout(Duration::from_secs(30))
                .redirect(reqwest::redirect::Policy::none())
                .build()?,
            email: c.client_email,
            key: Arc::new(key),
            project: project.into(),
            token: Arc::new(Mutex::new(None)),
        })
    }
    async fn access_token(&self) -> Result<String> {
        let mut cached = self.token.lock().await;
        if let Some(t) = cached.as_ref().filter(|t| t.expires > Instant::now()) {
            return Ok(t.value.clone());
        }
        let now = chrono::Utc::now().timestamp();
        let assertion=jsonwebtoken::encode(&jsonwebtoken::Header::new(jsonwebtoken::Algorithm::RS256),&json!({"iss":self.email,"aud":"https://oauth2.googleapis.com/token","iat":now,"exp":now+3600,"scope":"https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/firebase.messaging"}),&self.key)
            .map_err(|_|anyhow!("identity assertion signing failed"))?;
        let response = self
            .client
            .post("https://oauth2.googleapis.com/token")
            .form(&[
                ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
                ("assertion", &assertion),
            ])
            .send()
            .await
            .map_err(|_| anyhow!("identity OAuth network error"))?;
        ensure!(
            response.status().is_success(),
            "identity OAuth HTTP {}",
            response.status().as_u16()
        );
        let token: AccessToken = response
            .json()
            .await
            .map_err(|_| anyhow!("invalid OAuth response"))?;
        *cached = Some(CachedToken {
            value: token.access_token.clone(),
            expires: Instant::now()
                + Duration::from_secs(token.expires_in.saturating_sub(60).min(3540)),
        });
        Ok(token.access_token)
    }
    pub async fn list(&self, cursor: &str) -> Result<AccountPage> {
        let response = self
            .client
            .get(format!(
                "https://identitytoolkit.googleapis.com/v1/projects/{}/accounts:batchGet",
                self.project
            ))
            .query(&[("maxResults", "1000"), ("nextPageToken", cursor)])
            .bearer_auth(self.access_token().await?)
            .send()
            .await
            .map_err(|_| anyhow!("identity list network error"))?;
        ensure!(
            response.status().is_success(),
            "identity list HTTP {}",
            response.status().as_u16()
        );
        response
            .json()
            .await
            .map_err(|_| anyhow!("invalid identity list response"))
    }
    /// A completed list is not a consistent snapshot; confirm every apparent deletion by UID.
    pub async fn exists(&self, uid: &str) -> Result<bool> {
        let response = self
            .client
            .post(format!(
                "https://identitytoolkit.googleapis.com/v1/projects/{}/accounts:lookup",
                self.project
            ))
            .json(&json!({"localId":[uid]}))
            .bearer_auth(self.access_token().await?)
            .send()
            .await
            .map_err(|_| anyhow!("identity lookup network error"))?;
        ensure!(
            response.status().is_success(),
            "identity lookup HTTP {}",
            response.status().as_u16()
        );
        let page: AccountPage = response
            .json()
            .await
            .map_err(|_| anyhow!("invalid identity lookup response"))?;
        Ok(page.users.iter().any(|u| u.local_id == uid))
    }
    /// true means accepted by FCM, false means the device token is definitively unregistered.
    pub async fn push(&self, payload: &Value) -> Result<bool> {
        let response=self.client.post(format!("https://fcm.googleapis.com/v1/projects/{}/messages:send",self.project)).bearer_auth(self.access_token().await?)
            .json(&json!({"message":{"token":payload["token"],"notification":{"title":payload["title"],"body":payload["body"]},"data":{"activityId":payload["activityId"],"bookingId":payload["bookingId"]},"apns":{"payload":{"aps":{"sound":"default"}}}}}))
            .send().await.map_err(|_|anyhow!("FCM network error"))?;
        if response.status().is_success() {
            return Ok(true);
        }
        let status = response.status().as_u16();
        let body: Value = response.json().await.unwrap_or_default();
        if body["error"]["details"]
            .as_array()
            .is_some_and(|items| items.iter().any(|d| d["errorCode"] == "UNREGISTERED"))
        {
            return Ok(false);
        }
        Err(anyhow!("FCM HTTP {status}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn identity_parsing_excludes_password_hashes_and_handles_optional_fields() {
        let a: Account = serde_json::from_value(
            json!({"localId":"user","createdAt":"1234","passwordHash":"not-retained"}),
        )
        .unwrap();
        assert_eq!(a.created_ms(), 1000);
        assert!(a.email.is_empty());
        assert!(
            serde_json::to_value(a)
                .unwrap()
                .get("passwordHash")
                .is_none()
        );
    }
}
