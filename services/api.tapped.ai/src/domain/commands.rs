//! Domain write endpoints. Collection writes remain compatibility adapters to the same transactions.
use crate::{
    domain::{app_data, firebase_auth::FirebaseUser},
    errors::AppError,
    state::AppStateDyn,
};
use axum::{
    Json,
    extract::{Path, State},
};
use serde::Deserialize;
use serde_json::{Value, json};
type ResultDoc = Result<Json<Value>, AppError>;

#[utoipa::path(post,path="/profiles",tag="app",request_body=Value,responses((status=200,description="Owned profile created")),security(("FirebaseAuth"=[])))]
pub async fn create_profile(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Json(input): Json<Value>,
) -> ResultDoc {
    app_data::save(&state, &user, "users", &user.uid, input, true).await
}
#[utoipa::path(put,path="/profiles/{id}",tag="app",params(("id"=String,Path)),request_body=Value,responses((status=200,description="Owned profile updated")),security(("FirebaseAuth"=[])))]
pub async fn update_profile(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(id): Path<String>,
    Json(input): Json<Value>,
) -> ResultDoc {
    app_data::save(&state, &user, "users", &id, input, false).await
}
#[utoipa::path(post,path="/bookings",tag="app",request_body=Value,responses((status=200,description="Booking requested")),security(("FirebaseAuth"=[])))]
pub async fn request_booking(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Json(input): Json<Value>,
) -> ResultDoc {
    let id = input["id"].as_str().unwrap_or_default().to_owned();
    app_data::save(&state, &user, "bookings", &id, input, true).await
}
#[utoipa::path(put,path="/bookings/{id}",tag="app",params(("id"=String,Path)),request_body=Value,responses((status=200,description="Booking edited")),security(("FirebaseAuth"=[])))]
pub async fn edit_booking(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(id): Path<String>,
    Json(input): Json<Value>,
) -> ResultDoc {
    if input.get("status").is_some() {
        return Err(AppError::bad_request(
            "use accept/cancel commands to change booking status",
        ));
    }
    app_data::save(&state, &user, "bookings", &id, input, false).await
}
#[utoipa::path(post,path="/bookings/{id}/accept",tag="app",request_body=Option<Value>,params(("id"=String,Path)),responses((status=200,description="Booking accepted")),security(("FirebaseAuth"=[])))]
pub async fn accept_booking(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(id): Path<String>,
    input: Option<Json<Value>>,
) -> ResultDoc {
    let mut input = input.map(|Json(v)| v).unwrap_or_else(|| json!({}));
    if !input.is_object() {
        return Err(AppError::bad_request("JSON object required"));
    }
    input["status"] = json!("confirmed");
    app_data::save(&state, &user, "bookings", &id, input, false).await
}
#[utoipa::path(post,path="/bookings/{id}/cancel",tag="app",request_body=Option<Value>,params(("id"=String,Path)),responses((status=200,description="Booking canceled")),security(("FirebaseAuth"=[])))]
pub async fn cancel_booking(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(id): Path<String>,
    input: Option<Json<Value>>,
) -> ResultDoc {
    let mut input = input.map(|Json(v)| v).unwrap_or_else(|| json!({}));
    if !input.is_object() {
        return Err(AppError::bad_request("JSON object required"));
    }
    input["status"] = json!("canceled");
    app_data::save(&state, &user, "bookings", &id, input, false).await
}
#[derive(Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Schedule {
    start_time: chrono::DateTime<chrono::Utc>,
    end_time: chrono::DateTime<chrono::Utc>,
}
#[utoipa::path(post,path="/bookings/{id}/reschedule",tag="app",params(("id"=String,Path)),request_body=Schedule,responses((status=200,description="Booking rescheduled")),security(("FirebaseAuth"=[])))]
pub async fn reschedule_booking(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(id): Path<String>,
    Json(schedule): Json<Schedule>,
) -> ResultDoc {
    app_data::save(
        &state,
        &user,
        "bookings",
        &id,
        json!({"startTime":schedule.start_time,"endTime":schedule.end_time}),
        false,
    )
    .await
}
#[utoipa::path(post,path="/reviews",tag="app",request_body=Value,responses((status=200,description="One review per booking/role")),security(("FirebaseAuth"=[])))]
pub async fn submit_review(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Json(input): Json<Value>,
) -> ResultDoc {
    let id = input["id"].as_str().unwrap_or_default().to_owned();
    app_data::save(&state, &user, "reviews", &id, input, true).await
}
#[utoipa::path(get,path="/public/profiles/{id}/stats",tag="public",params(("id"=String,Path)),responses((status=200,description="Derived profile statistics",body=Value)))]
pub async fn profile_stats(State(state): State<AppStateDyn>, Path(id): Path<String>) -> ResultDoc {
    app_data::safe_id(&id)?;
    let pool = state
        .postgres
        .as_ref()
        .ok_or_else(|| AppError::from_status(axum::http::StatusCode::SERVICE_UNAVAILABLE))?;
    let value:Option<Value>=sqlx::query_scalar("SELECT jsonb_build_object('confirmedBookingCount',s.confirmed_booking_count,'completedBookingCount',s.completed_booking_count,'performerReviewCount',s.performer_review_count,'performerRating',s.performer_rating,'bookerReviewCount',s.booker_review_count,'bookerRating',s.booker_rating,'topPerformerIds',CASE WHEN u.venue_enabled THEN venue_top_performers(u.id) ELSE '{}'::text[] END,'bookingsByDayOfWeek',CASE WHEN u.venue_enabled THEN venue_booking_days(u.id) ELSE ARRAY[0,0,0,0,0,0,0]::bigint[] END) FROM profile_stats s JOIN users u USING(id) WHERE id=$1 AND NOT u.deleted AND NOT u.shadow_banned").bind(id).fetch_optional(pool).await.map_err(|e|AppError::internal("profile statistics",e))?;
    Ok(Json(value.ok_or_else(|| {
        AppError::not_found("profile unavailable")
    })?))
}
