//! Firebase Auth lifecycle capture is identity-only, never a Firestore synchronization worker.
use crate::{
    data::google_identity::{Account, GoogleIdentity},
    domain::{
        external_effects,
        founder_notifications::{self, FounderMessage},
        mail_bridge::{MailStore, QueuedEmail, SqliteMailStore},
    },
};
use anyhow::{Result, anyhow, ensure};
use serde_json::{Value, json};
use sqlx::{PgPool, Row};
use std::time::Duration;

pub async fn capture_account(
    pool: &PgPool,
    account: &Account,
    scan: uuid::Uuid,
    notify_new: bool,
) -> Result<()> {
    ensure!(
        !account.local_id.is_empty() && account.local_id.len() <= 128,
        "invalid identity UID"
    );
    let mut tx = pool.begin().await?;
    let old: Option<(i64, bool)> = sqlx::query_as(
        "SELECT created_at_ms,deleted FROM firebase_identities WHERE uid=$1 FOR UPDATE",
    )
    .bind(&account.local_id)
    .fetch_optional(&mut *tx)
    .await?;
    sqlx::query("INSERT INTO firebase_identities(uid,email,display_name,created_at_ms,scan_id) VALUES($1,$2,$3,$4,$5) ON CONFLICT(uid) DO UPDATE SET email=EXCLUDED.email,display_name=EXCLUDED.display_name,created_at_ms=EXCLUDED.created_at_ms,scan_id=EXCLUDED.scan_id,deleted=false")
        .bind(&account.local_id).bind(&account.email).bind(&account.display_name).bind(account.created_ms()).bind(scan).execute(&mut *tx).await?;
    if notify_new && old.is_none_or(|(created, deleted)| deleted || created != account.created_ms())
    {
        let id = format!("auth-signup:{}:{}", account.local_id, account.created_ms());
        external_effects::enqueue(&mut tx, &id, "auth_signup", serde_json::to_value(account)?)
            .await?;
    }
    sqlx::query(
        "UPDATE users SET email=$2 WHERE id=$1 AND NOT unclaimed AND email IS DISTINCT FROM $2",
    )
    .bind(&account.local_id)
    .bind(&account.email)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(())
}

pub async fn capture_deleted(pool: &PgPool, uid: &str) -> Result<()> {
    let mut tx = pool.begin().await?;
    let old:Option<(String,String,i64)>=sqlx::query_as("UPDATE firebase_identities SET deleted=true WHERE uid=$1 AND NOT deleted RETURNING email,display_name,created_at_ms").bind(uid).fetch_optional(&mut *tx).await?;
    if let Some((email, name, created)) = old {
        sqlx::query("UPDATE users SET deleted=true WHERE id=$1")
            .bind(uid)
            .execute(&mut *tx)
            .await?;
        sqlx::query("UPDATE services SET deleted=true WHERE user_id=$1")
            .bind(uid)
            .execute(&mut *tx)
            .await?;
        external_effects::enqueue(
            &mut tx,
            &format!("auth-delete:{uid}:{created}"),
            "auth_delete",
            json!({"localId":uid,"email":email,"displayName":name,"createdAt":created.to_string()}),
        )
        .await?;
    }
    tx.commit().await?;
    Ok(())
}

pub async fn scan_identities(pool: &PgPool, google: &GoogleIdentity) -> Result<usize> {
    // One dedicated session lock prevents overlapping scanners, including during rollout.
    let mut connection = pool.acquire().await?;
    let locked: bool = sqlx::query_scalar("SELECT pg_try_advisory_lock(920041755)")
        .fetch_one(&mut *connection)
        .await?;
    if !locked {
        return Ok(0);
    }
    let result = scan_locked(pool, google).await;
    sqlx::query("SELECT pg_advisory_unlock(920041755)")
        .execute(&mut *connection)
        .await?;
    result
}
async fn scan_locked(pool: &PgPool, google: &GoogleIdentity) -> Result<usize> {
    sqlx::query(
        "INSERT INTO firebase_identity_sync(singleton) VALUES(true) ON CONFLICT DO NOTHING",
    )
    .execute(pool)
    .await?;
    let state:(bool,i64)=sqlx::query_as("SELECT baseline_completed_at IS NOT NULL,(extract(epoch FROM baseline_started_at)*1000)::bigint FROM firebase_identity_sync").fetch_one(pool).await?;
    let scan = uuid::Uuid::new_v4();
    let mut cursor = String::new();
    let mut count = 0;
    loop {
        let page = google.list(&cursor).await?;
        for account in page.users {
            let notify = state.0 || account.created_ms() >= state.1;
            capture_account(pool, &account, scan, notify).await?;
            count += 1;
        }
        if page.next_page_token.is_empty() {
            break;
        }
        ensure!(
            page.next_page_token != cursor,
            "identity pagination did not advance"
        );
        cursor = page.next_page_token;
    }
    // Do not infer deletion from a partial scan or changing pagination. Confirm unseen UIDs.
    let missing: Vec<String> =
        sqlx::query_scalar("SELECT uid FROM firebase_identities WHERE scan_id<>$1 AND NOT deleted")
            .bind(scan)
            .fetch_all(pool)
            .await?;
    for uid in missing {
        if !google.exists(&uid).await? {
            capture_deleted(pool, &uid).await?;
        }
    }
    sqlx::query("UPDATE firebase_identity_sync SET baseline_completed_at=COALESCE(baseline_completed_at,now()),completed_scan_at=now()").execute(pool).await?;
    Ok(count)
}

pub struct ProviderWorker {
    pub pool: PgPool,
    pub google: GoogleIdentity,
    pub mail: SqliteMailStore,
    pub client: reqwest::Client,
    pub stream_key: String,
    pub stream_secret: String,
    pub mailchimp_key: String,
    pub mailchimp_region: String,
    pub auth_effects: bool,
}
impl ProviderWorker {
    fn stream_request(
        &self,
        method: reqwest::Method,
        path: &str,
    ) -> Result<reqwest::RequestBuilder> {
        let now = chrono::Utc::now().timestamp();
        let token = jsonwebtoken::encode(
            &jsonwebtoken::Header::new(jsonwebtoken::Algorithm::HS256),
            &json!({"server":true,"iat":now,"exp":now+120}),
            &jsonwebtoken::EncodingKey::from_secret(self.stream_secret.as_bytes()),
        )
        .map_err(|_| anyhow!("Stream signing failed"))?;
        Ok(self
            .client
            .request(method, format!("https://chat.stream-io-api.com{path}"))
            .query(&[("api_key", &self.stream_key)])
            .header("Stream-Auth-Type", "jwt")
            .bearer_auth(token))
    }
    async fn stream_upsert(&self, uid: &str, profile: Value) -> Result<()> {
        let mut user = profile;
        user["id"] = json!(uid);
        let r = self
            .stream_request(reqwest::Method::POST, "/users")?
            .json(&json!({"users":{uid:user}}))
            .send()
            .await
            .map_err(|_| anyhow!("Stream network error"))?;
        ensure!(
            r.status().is_success(),
            "Stream upsert HTTP {}",
            r.status().as_u16()
        );
        Ok(())
    }
    async fn introductions(&self, uid: &str) -> Result<()> {
        // Preserve the existing automatic founder welcome DMs. Stable IDs deduplicate retries.
        for (sender, messages) in [
            (
                "8yYVxpQ7cURSzNfBsaBGF7A7kkv2",
                vec![
                    "welcome to tapped!",
                    "I work with the engineering team so if you have any ideas on how to make the app better lemme know and I can send it to them",
                ],
            ),
            (
                "n4zIL6bOuPTqRC3dtsl6gyEBPQl1",
                vec!["welcome to the app! how did you find out about us?"],
            ),
        ] {
            if sender == uid {
                continue;
            }
            let r = self
                .stream_request(reqwest::Method::POST, "/channels/messaging/query")?
                .json(&json!({"data":{"members":[sender,uid],"created_by_id":sender},"state":true}))
                .send()
                .await
                .map_err(|_| anyhow!("Stream welcome channel network error"))?;
            ensure!(
                r.status().is_success(),
                "Stream welcome channel HTTP {}",
                r.status().as_u16()
            );
            let channel: Value = r
                .json()
                .await
                .map_err(|_| anyhow!("invalid Stream channel response"))?;
            let channel_id = channel["channel"]["id"]
                .as_str()
                .ok_or_else(|| anyhow!("missing Stream channel id"))?;
            for (index, text) in messages.into_iter().enumerate() {
                use sha2::{Digest, Sha256};
                let id = hex::encode(Sha256::digest(
                    format!("welcome:{sender}:{uid}:{index}").as_bytes(),
                ));
                let r = self
                    .stream_request(
                        reqwest::Method::POST,
                        &format!("/channels/messaging/{channel_id}/message"),
                    )?
                    .json(&json!({"message":{"id":id,"text":text,"user_id":sender}}))
                    .send()
                    .await
                    .map_err(|_| anyhow!("Stream welcome message network error"))?;
                ensure!(
                    r.status().is_success() || r.status().as_u16() == 409,
                    "Stream welcome message HTTP {}",
                    r.status().as_u16()
                );
            }
        }
        Ok(())
    }
    async fn stream_delete(&self, uid: &str) -> Result<()> {
        // UID encoding prevents custom Auth IDs from changing the path/query.
        let mut url = reqwest::Url::parse("https://chat.stream-io-api.com/users/")?;
        url.path_segments_mut()
            .map_err(|_| anyhow!("invalid Stream path"))?
            .push(uid);
        let r = self
            .stream_request(reqwest::Method::DELETE, url.path())?
            .send()
            .await
            .map_err(|_| anyhow!("Stream network error"))?;
        ensure!(
            r.status().is_success() || r.status().as_u16() == 404,
            "Stream delete HTTP {}",
            r.status().as_u16()
        );
        Ok(())
    }
    async fn slack_auth(&self, id: &str, kind: &str, a: &Account) -> Result<()> {
        if a.email.ends_with("@tapped.ai") {
            return Ok(());
        }
        let title = if kind == "auth_signup" {
            "You have a new user 🙃"
        } else {
            "user deleted their account 😞"
        };
        let action = if kind == "auth_signup" {
            "just signed up"
        } else {
            "just left"
        };
        let safe = |s: &str| {
            s.replace('&', "&amp;")
                .replace('<', "&lt;")
                .replace('>', "&gt;")
        };
        let mut tx = self.pool.begin().await?;
        founder_notifications::enqueue(
            &mut tx,
            id,
            kind,
            &a.local_id,
            &a.local_id,
            &FounderMessage {
                text: format!(
                    "*{title}* - {}, {} {action}",
                    safe(&a.display_name),
                    safe(&a.email)
                ),
            },
        )
        .await?;
        tx.commit().await?;
        Ok(())
    }
    async fn mailchimp(&self, email: &str) -> Result<()> {
        if email.is_empty() || email.contains("tapped.ai") {
            return Ok(());
        }
        ensure!(
            !self.mailchimp_key.is_empty()
                && self.mailchimp_region.len() < 20
                && self.mailchimp_region.starts_with("us")
                && self
                    .mailchimp_region
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric()),
            "Mailchimp configuration unavailable"
        );
        // POST preserves legacy behavior: existing/unsubscribed members are never re-subscribed.
        let r = self
            .client
            .post(format!(
                "https://{}.api.mailchimp.com/3.0/lists/adc6feff36/members",
                self.mailchimp_region
            ))
            .basic_auth("apikey", Some(&self.mailchimp_key))
            .json(&json!({"email_address":email,"status":"subscribed"}))
            .send()
            .await
            .map_err(|_| anyhow!("Mailchimp network error"))?;
        if r.status().is_success() {
            return Ok(());
        }
        let status = r.status().as_u16();
        let v: Value = r.json().await.unwrap_or_default();
        ensure!(v["title"] == "Member Exists", "Mailchimp HTTP {status}");
        Ok(())
    }
    async fn send_mail(&self, id: &str, to: &str, template: &str) -> Result<()> {
        let row: Option<(String, String, Option<String>)> =
            sqlx::query_as("SELECT subject,text_body,html_body FROM email_templates WHERE name=$1")
                .bind(template)
                .fetch_optional(&self.pool)
                .await?;
        let (subject, text_body, html_body) =
            row.ok_or_else(|| anyhow!("mail template not provisioned"))?;
        // Enqueue is idempotent across the Postgres/SQLite boundary. The mail worker retries transport.
        self.mail
            .enqueue_outbound(QueuedEmail {
                event_id: id.into(),
                thread_id: format!("notification:{id}"),
                from: "no-reply@tapped.ai".into(),
                to: vec![to.into()],
                cc: vec![],
                subject,
                text_body,
                html_body,
                message_id: format!("<{}@tapped.ai>", uuid::Uuid::new_v4()),
                in_reply_to: String::new(),
                references: String::new(),
                attachments: vec![],
                encoded_attachments: vec![],
            })
            .await?;
        Ok(())
    }
    pub async fn deliver(&self, id: &str, kind: &str, payload: Value) -> Result<()> {
        match kind {
            "auth_signup" => {
                let a: Account = serde_json::from_value(payload)?;
                let current:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM firebase_identities WHERE uid=$1 AND created_at_ms=$2 AND NOT deleted)")
                    .bind(&a.local_id).bind(a.created_ms()).fetch_one(&self.pool).await?;
                if !current {
                    return Ok(());
                }
                self.slack_auth(id, kind, &a).await?;
                let doc: Option<Value> =
                    sqlx::query_scalar("SELECT doc FROM api_users WHERE id=$1")
                        .bind(&a.local_id)
                        .fetch_optional(&self.pool)
                        .await?;
                let user=doc.map(|doc|json!({"email":doc["email"],"name":doc["artistName"],"username":doc["username"],"image":doc["profilePicture"]}))
                    .unwrap_or_else(||json!({"email":a.email,"name":if a.display_name.is_empty(){&a.local_id}else{&a.display_name},"username":a.local_id}));
                self.stream_upsert(&a.local_id, user).await?;
                if !a.email.is_empty() && !a.email.ends_with("@tapped.ai") {
                    self.send_mail(&format!("welcome:{id}"), &a.email, "welcome")
                        .await?;
                }
                self.mailchimp(&a.email).await?;
            }
            "auth_delete" => {
                let a: Account = serde_json::from_value(payload)?;
                let replaced: bool = sqlx::query_scalar(
                    "SELECT EXISTS(SELECT 1 FROM firebase_identities WHERE uid=$1 AND NOT deleted)",
                )
                .bind(&a.local_id)
                .fetch_one(&self.pool)
                .await?;
                if replaced {
                    return Ok(());
                }
                self.slack_auth(id, kind, &a).await?;
                self.stream_delete(&a.local_id).await?;
            }
            "stream_profile" => {
                let uid = payload["uid"]
                    .as_str()
                    .ok_or_else(|| anyhow!("invalid profile effect"))?;
                let doc: Option<Value> =
                    sqlx::query_scalar("SELECT doc FROM api_users WHERE id=$1")
                        .bind(uid)
                        .fetch_optional(&self.pool)
                        .await?;
                match doc {
                    Some(doc) if doc["deleted"] != true && doc["unclaimed"] != true => {
                        self.stream_upsert(uid,json!({"name":doc["artistName"],"username":doc["username"],"email":doc["email"],"image":doc["profilePicture"]})).await?;
                        if payload["created"] == true {
                            self.introductions(uid).await?;
                        }
                    }
                    Some(doc) if doc["deleted"] == true => self.stream_delete(uid).await?,
                    None => self.stream_delete(uid).await?,
                    _ => {}
                }
            }
            "mail" => {
                self.send_mail(
                    id,
                    payload["to"]
                        .as_str()
                        .ok_or_else(|| anyhow!("invalid mail recipient"))?,
                    payload["template"]
                        .as_str()
                        .ok_or_else(|| anyhow!("invalid mail template"))?,
                )
                .await?
            }
            "push" => {
                let active:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM device_tokens t JOIN users u ON u.id=t.user_id WHERE t.token=$1 AND t.user_id=$2 AND NOT u.deleted)").bind(payload["token"].as_str()).bind(payload["uid"].as_str()).fetch_one(&self.pool).await?;
                if active && !self.google.push(&payload).await? {
                    sqlx::query("DELETE FROM device_tokens WHERE token=$1 AND user_id=$2")
                        .bind(payload["token"].as_str())
                        .bind(payload["uid"].as_str())
                        .execute(&self.pool)
                        .await?;
                }
            }
            _ => return Err(anyhow!("invalid effect kind")),
        }
        Ok(())
    }
    pub async fn deliver_one(&self) -> Result<bool> {
        let lease = uuid::Uuid::new_v4();
        let row=sqlx::query("UPDATE external_effect_outbox SET lock_token=$1,locked_until=now()+interval '5 minutes',attempts=attempts+1 WHERE id=(SELECT id FROM external_effect_outbox WHERE delivered_at IS NULL AND available_at<=now() AND (locked_until IS NULL OR locked_until<now()) AND ($2 OR kind NOT IN ('auth_signup','auth_delete')) ORDER BY available_at,created_at FOR UPDATE SKIP LOCKED LIMIT 1) RETURNING id,kind,payload,attempts")
            .bind(lease).bind(self.auth_effects).fetch_optional(&self.pool).await?;
        let Some(row) = row else { return Ok(false) };
        let id: String = row.get("id");
        let kind: String = row.get("kind");
        match self.deliver(&id, &kind, row.get("payload")).await {
            Ok(()) => {
                sqlx::query("UPDATE external_effect_outbox SET delivered_at=now(),lock_token=NULL,locked_until=NULL,last_error=NULL WHERE id=$1 AND lock_token=$2 AND locked_until>now() AND delivered_at IS NULL").bind(id).bind(lease).execute(&self.pool).await?;
            }
            Err(_) => {
                let attempts: i32 = row.get("attempts");
                let delay = (5_i64 * 2_i64.pow(attempts.clamp(0, 10) as u32)).min(3600);
                // Never log SDK errors/payloads: URLs and bodies may contain credentials/PII.
                tracing::warn!(effect_type = kind, "provider effect retained for retry");
                sqlx::query("UPDATE external_effect_outbox SET available_at=now()+make_interval(secs=>$3),lock_token=NULL,locked_until=NULL,last_error='provider_error' WHERE id=$1 AND lock_token=$2 AND locked_until>now() AND delivered_at IS NULL").bind(id).bind(lease).bind(delay as f64).execute(&self.pool).await?;
            }
        }
        Ok(true)
    }
    pub async fn run(&self) {
        loop {
            match self.deliver_one().await {
                Ok(true) => {}
                Ok(false) => tokio::time::sleep(Duration::from_secs(2)).await,
                Err(_) => {
                    tracing::warn!("provider queue unavailable; retrying");
                    tokio::time::sleep(Duration::from_secs(10)).await;
                }
            }
        }
    }
}
