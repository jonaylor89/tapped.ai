use crate::{
    domain::{
        firebase_auth::FirebaseUser,
        founder_notifications::{FounderMessage, enqueue},
    },
    errors::AppError,
    state::AppStateDyn,
};
use axum::{Json, extract::State};
use serde::Deserialize;
use uuid::Uuid;
#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Feedback {
    pub id: Uuid,
    pub text: String,
}
pub async fn submit(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Json(command): Json<Feedback>,
) -> Result<Json<serde_json::Value>, AppError> {
    let text = command.text.trim();
    if text.is_empty() || text.len() > 8_000 {
        return Err(AppError::bad_request("feedback must contain 1–8000 bytes"));
    }
    let pool = state
        .postgres
        .as_ref()
        .ok_or_else(|| AppError::new("database unavailable"))?;
    let escaped = text
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;");
    let mut tx = pool
        .begin()
        .await
        .map_err(|_| AppError::new("feedback queue unavailable"))?;
    let key = format!("feedback:{}:{}", user.uid, command.id);
    enqueue(
        &mut tx,
        &key,
        "feedback",
        &command.id.to_string(),
        &user.uid,
        &FounderMessage {
            text: format!("*New User Feedback 🙃* - {escaped}"),
        },
    )
    .await
    .map_err(|_| AppError::new("feedback queue unavailable"))?;
    tx.commit()
        .await
        .map_err(|_| AppError::new("feedback queue unavailable"))?;
    Ok(Json(serde_json::json!({"id":command.id})))
}
