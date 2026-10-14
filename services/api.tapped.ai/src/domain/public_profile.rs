//! One public-only details request, used for hover/focus warming and fresh profile-sheet reads.
use crate::{
    domain::{app_data::visible, public_docs::public_user},
    errors::AppError,
    state::AppStateDyn,
};
use axum::{
    Json,
    extract::{Path, State},
    http::{HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
};
use serde::Serialize;
use serde_json::Value;
use utoipa::ToSchema;

#[derive(Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ProfileDetails {
    pub user: Value,
    pub booking_count: i64,
    pub bookings: Vec<Value>,
    pub latest_review: Option<Value>,
    pub related_users: Vec<Value>,
}

fn public_review(mut doc: Value) -> Option<Value> {
    // The profile card needs only the public review summary, never imported extension fields.
    let fields = [
        "id",
        "bookerId",
        "performerId",
        "bookingId",
        "timestamp",
        "overallRating",
        "overallReview",
        "type",
    ];
    doc.as_object_mut()?
        .retain(|key, _| fields.contains(&key.as_str()));
    Some(doc)
}

#[utoipa::path(
    get,
    path = "/public/users/{id}/details",
    tag = "public",
    summary = "Fresh public profile, confirmed history, count and latest review",
    params(("id" = String, Path, description = "The user ID.")),
    responses((status = 200, description = "Success", body = ProfileDetails))
)]
pub async fn get_details(State(state): State<AppStateDyn>, Path(id): Path<String>) -> Response {
    let result = load(&state, &id).await;
    let mut response = result.map(Json).into_response();
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    response
}
async fn load(state: &AppStateDyn, id: &str) -> Result<ProfileDetails, AppError> {
    if id.is_empty()
        || id.len() > 128
        || !id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
        || id.contains("..")
    {
        return Err(AppError::bad_request("invalid ID"));
    }
    let pool = state.postgres.as_ref().ok_or_else(|| {
        AppError::new("database unavailable").with_status(StatusCode::SERVICE_UNAVAILABLE)
    })?;
    let raw: Option<Value> = sqlx::query_scalar(
        r#"
WITH subject AS MATERIALIZED (
  SELECT v.doc FROM users u JOIN api_users v USING(id)
  WHERE u.id=$1 AND NOT u.deleted AND NOT u.shadow_banned
), received AS (
  SELECT id FROM bookings WHERE requestee_id=$1 AND status='confirmed'
  ORDER BY occurred_at DESC NULLS LAST,id DESC LIMIT 40
), requested AS (
  SELECT id FROM bookings WHERE requester_id=$1 AND status='confirmed'
  ORDER BY occurred_at DESC NULLS LAST,id DESC LIMIT 40
), history AS MATERIALIZED (
  SELECT v.doc FROM (SELECT id FROM received UNION SELECT id FROM requested) b
  JOIN api_bookings v USING(id)
  ORDER BY v.doc->>'startTime' DESC NULLS LAST,v.id
), latest AS MATERIALIZED (
  SELECT doc FROM api_reviews WHERE reviewee_id=$1 AND review_type='performer'
  ORDER BY doc->>'timestamp' DESC NULLS LAST,id DESC LIMIT 1
), refs AS MATERIALIZED (
  SELECT id FROM (
    SELECT doc->>'requesterId' AS id FROM history UNION SELECT doc->>'requesteeId' FROM history
    UNION SELECT doc->>'bookerId' FROM latest UNION SELECT doc->>'performerId' FROM latest
    UNION SELECT r.id FROM subject s CROSS JOIN LATERAL jsonb_array_elements_text(
      CASE WHEN jsonb_typeof(s.doc#>'{venueInfo,topPerformerIds}')='array'
        THEN s.doc#>'{venueInfo,topPerformerIds}' ELSE '[]'::jsonb END
    ) WITH ORDINALITY r(id,ordinal) WHERE r.ordinal<=20
  ) ids WHERE id<>$1 AND length(id) BETWEEN 1 AND 128 ORDER BY id LIMIT 200
), related AS (
  SELECT v.doc FROM refs r JOIN users u USING(id) JOIN api_users v USING(id)
  WHERE NOT u.deleted AND NOT u.shadow_banned ORDER BY u.id
)
SELECT jsonb_build_object(
  'user',s.doc,
  'bookingCount',(SELECT count(*) FROM bookings WHERE requestee_id=$1 AND status='confirmed'),
  'bookings',coalesce((SELECT jsonb_agg(doc) FROM history),'[]'::jsonb),
  'latestReview',(SELECT doc FROM latest),
  'relatedUsers',coalesce((SELECT jsonb_agg(doc) FROM related),'[]'::jsonb)
) FROM subject s
"#,
    )
    .bind(id)
    .fetch_optional(pool)
    .await
    .map_err(|e| AppError::internal("public profile details", e))?;
    let raw = raw.ok_or_else(|| AppError::not_found("profile unavailable"))?;
    let user = public_user(raw["user"].clone())
        .ok_or_else(|| AppError::not_found("profile unavailable"))?;
    Ok(ProfileDetails {
        user,
        booking_count: raw["bookingCount"].as_i64().unwrap_or(0),
        bookings: raw["bookings"]
            .as_array()
            .into_iter()
            .flatten()
            .cloned()
            .filter_map(|doc| visible("bookings", doc, None))
            .collect(),
        latest_review: raw.get("latestReview").cloned().and_then(public_review),
        related_users: raw["relatedUsers"]
            .as_array()
            .into_iter()
            .flatten()
            .cloned()
            .filter_map(public_user)
            .collect(),
    })
}
