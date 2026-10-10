//! API-only collection access. SQL identifiers come exclusively from this module's allowlist.
//! Public responses are separately projected; authentication never grants access to another user's
//! private profile, pending bookings, activities, credentials or interest comments.
use crate::{
    domain::{firebase_auth::FirebaseUser, public_docs::public_user},
    errors::AppError,
    state::AppStateDyn,
};
use axum::{
    Json,
    extract::{Path, Query, State},
    http::StatusCode,
};
use serde::Deserialize;
use serde_json::{Value, json};
use sqlx::{PgPool, Postgres, Transaction};

type ApiResult = Result<Json<Value>, AppError>;
fn db_error(e: sqlx::Error) -> AppError {
    if e.as_database_error()
        .is_some_and(|e| e.is_unique_violation())
    {
        AppError::new("already exists").with_status(StatusCode::CONFLICT)
    } else {
        AppError::internal("Postgres request", e)
    }
}
fn forbidden() -> AppError {
    AppError::new("forbidden").with_status(StatusCode::FORBIDDEN)
}
fn pool(state: &AppStateDyn) -> Result<&PgPool, AppError> {
    state.postgres.as_ref().ok_or_else(|| {
        AppError::new("database unavailable").with_status(StatusCode::SERVICE_UNAVAILABLE)
    })
}
#[derive(Deserialize, schemars::JsonSchema)]
pub struct CollectionPath {
    pub table: String,
}
impl From<&str> for CollectionPath {
    fn from(table: &str) -> Self {
        Self {
            table: table.to_owned(),
        }
    }
}
impl From<String> for CollectionPath {
    fn from(table: String) -> Self {
        Self { table }
    }
}
#[derive(Deserialize, schemars::JsonSchema)]
pub struct DocumentPath {
    pub table: String,
    pub id: String,
}
impl From<(String, String)> for DocumentPath {
    fn from((table, id): (String, String)) -> Self {
        Self { table, id }
    }
}

pub fn fields(table: &str) -> Result<&'static [(&'static str, &'static str)], AppError> {
    Ok(match table {
        "users" => &[
            ("username", "username"),
            ("email", "email"),
            ("artistName", "artist_name"),
            ("bio", "bio"),
            ("occupations", "occupations"),
            ("profilePicture", "profile_picture"),
            ("placeId", "place_id"),
            ("deleted", "deleted"),
            ("shadowBanned", "shadow_banned"),
            ("unclaimed", "unclaimed"),
        ],
        "services" => &[
            ("userId", "user_id"),
            ("title", "title"),
            ("description", "description"),
            ("rate", "rate"),
            ("rateType", "rate_type"),
            ("count", "count"),
            ("deleted", "deleted"),
        ],
        "bookings" => &[
            ("serviceId", "service_id"),
            ("addedByUser", "added_by_user"),
            ("name", "name"),
            ("note", "note"),
            ("requesterId", "requester_id"),
            ("requesteeId", "requestee_id"),
            ("status", "status"),
            ("genres", "genres"),
            ("rate", "rate"),
            ("startTime", "start_time"),
            ("endTime", "end_time"),
            ("timestamp", "occurred_at"),
            ("placeId", "place_id"),
            ("ticketsSold", "tickets_sold"),
            ("totalEventRevenue", "total_event_revenue"),
            ("flierUrl", "flier_url"),
            ("eventUrl", "event_url"),
            ("referenceEventId", "reference_event_id"),
        ],
        "activities" => &[
            ("type", "activity_type"),
            ("fromUserId", "from_user_id"),
            ("toUserId", "to_user_id"),
            ("bookingId", "booking_id"),
            ("loopId", "loop_id"),
            ("commentId", "comment_id"),
            ("rootId", "root_id"),
            ("count", "count"),
            ("markedRead", "marked_read"),
            ("timestamp", "occurred_at"),
        ],
        "opportunities" => &[
            ("userId", "user_id"),
            ("title", "title"),
            ("description", "description"),
            ("flierUrl", "flier_url"),
            ("placeId", "place_id"),
            ("timestamp", "occurred_at"),
            ("startTime", "start_time"),
            ("endTime", "end_time"),
            ("deadline", "deadline"),
            ("genres", "genres"),
            ("isPaid", "is_paid"),
            ("venueId", "venue_id"),
            ("referenceEventId", "reference_event_id"),
            ("deleted", "deleted"),
        ],
        "reviews" => &[
            ("revieweeId", "reviewee_id"),
            ("bookerId", "booker_id"),
            ("performerId", "performer_id"),
            ("bookingId", "booking_id"),
            ("timestamp", "occurred_at"),
            ("overallRating", "overall_rating"),
            ("overallReview", "overall_review"),
            ("type", "review_type"),
        ],
        _ => return Err(AppError::not_found("unknown collection")),
    })
}
fn safe_id(id: &str) -> Result<(), AppError> {
    if id.is_empty()
        || id.len() > 128
        || !id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
        || id.contains("..")
    {
        Err(AppError::bad_request("invalid ID"))
    } else {
        Ok(())
    }
}
pub async fn document(pool: &PgPool, table: &str, id: &str) -> Result<Option<Value>, AppError> {
    fields(table)?;
    safe_id(id)?;
    sqlx::query_scalar(&format!("SELECT doc FROM api_{table} WHERE id=$1"))
        .bind(id)
        .fetch_optional(pool)
        .await
        .map_err(db_error)
}
async fn document_with_kind(
    pool: &PgPool,
    table: &str,
    id: &str,
    kind: Option<&str>,
    reviewee: Option<&str>,
) -> Result<Option<Value>, AppError> {
    if table != "reviews" {
        return document(pool, table, id).await;
    }
    safe_id(id)?;
    if !matches!(kind, Some("performer" | "booker")) {
        return Err(AppError::bad_request("reviewType required"));
    }
    let reviewee = reviewee.ok_or_else(|| AppError::bad_request("userId required"))?;
    safe_id(reviewee)?;
    sqlx::query_scalar(
        "SELECT doc FROM api_reviews WHERE id=$1 AND review_type=$2 AND reviewee_id=$3",
    )
    .bind(id)
    .bind(kind)
    .bind(reviewee)
    .fetch_optional(pool)
    .await
    .map_err(db_error)
}
fn text<'a>(doc: &'a Value, key: &str) -> &'a str {
    doc[key].as_str().unwrap_or("")
}
fn participant(doc: &Value, uid: &str) -> bool {
    text(doc, "requesterId") == uid || text(doc, "requesteeId") == uid
}
fn visible(table: &str, mut doc: Value, uid: Option<&str>) -> Option<Value> {
    match table {
        "users" => {
            if doc["deleted"] == true {
                return None;
            }
            if uid != doc["id"].as_str() {
                return public_user(doc);
            }
        }
        "bookings" if !uid.is_some_and(|u| participant(&doc, u)) => {
            if doc["status"] != "confirmed" {
                return None;
            }
            // Public performance history contains no private notes, financial terms or service details.
            let keys = [
                "id",
                "name",
                "requesterId",
                "requesteeId",
                "status",
                "location",
                "startTime",
                "endTime",
                "timestamp",
                "flierUrl",
                "eventUrl",
                "venueId",
                "referenceEventId",
            ];
            doc.as_object_mut()?
                .retain(|k, _| keys.contains(&k.as_str()));
        }
        "activities" if uid != doc["toUserId"].as_str() || uid.is_none() => return None,
        "opportunities" | "services" if doc["deleted"] == true => return None,
        _ => {}
    }
    Some(doc)
}
pub async fn get_public(
    State(state): State<AppStateDyn>,
    Path(DocumentPath { table, id }): Path<DocumentPath>,
    Query(p): Query<ListParams>,
) -> ApiResult {
    if table == "activities" {
        return Err(forbidden());
    }
    let doc = document_with_kind(
        pool(&state)?,
        &table,
        &id,
        p.review_type.as_deref(),
        p.user_id.as_deref(),
    )
    .await?
    .and_then(|v| visible(&table, v, None))
    .ok_or_else(|| AppError::not_found("not found"))?;
    Ok(Json(doc))
}
pub async fn get_private(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(DocumentPath { table, id }): Path<DocumentPath>,
    Query(p): Query<ListParams>,
) -> ApiResult {
    let doc = document_with_kind(
        pool(&state)?,
        &table,
        &id,
        p.review_type.as_deref(),
        p.user_id.as_deref(),
    )
    .await?
    .and_then(|v| visible(&table, v, Some(&user.uid)))
    .ok_or_else(|| AppError::not_found("not found"))?;
    Ok(Json(doc))
}

#[derive(Default, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ListParams {
    pub user_id: Option<String>,
    pub requester_id: Option<String>,
    pub requestee_id: Option<String>,
    pub reference_event_id: Option<String>,
    pub review_type: Option<String>,
    pub status: Option<String>,
    pub after: Option<String>,
    pub limit: Option<i64>,
    pub order: Option<String>,
    pub mode: Option<String>,
}
async fn list(state: &AppStateDyn, table: &str, p: ListParams, uid: Option<&str>) -> ApiResult {
    fields(table)?;
    let limit = p.limit.unwrap_or(100);
    if !(1..=500).contains(&limit) {
        return Err(AppError::bad_request("limit must be 1..500"));
    }
    if let Some(id) = &p.after {
        safe_id(id)?;
    }
    if table == "users" {
        return Err(forbidden());
    } // no bulk profile enumeration
    if table == "activities" && (uid.is_none() || p.user_id.as_deref() != uid) {
        return Err(forbidden());
    }
    let (owner, role1, role2, event, status, kind, time) = match table {
        "services" => (
            "user_id",
            "NULL::text",
            "NULL::text",
            "NULL::text",
            "NULL::text",
            "NULL::text",
            "created_at",
        ),
        "activities" => (
            "to_user_id",
            "NULL::text",
            "NULL::text",
            "NULL::text",
            "NULL::text",
            "NULL::text",
            "occurred_at",
        ),
        "opportunities" => (
            "user_id",
            "NULL::text",
            "NULL::text",
            "reference_event_id",
            "NULL::text",
            "NULL::text",
            if p.mode.is_some() {
                "start_time"
            } else {
                "occurred_at"
            },
        ),
        "reviews" => (
            if p.review_type.as_deref() == Some("booker") {
                "booker_id"
            } else {
                "performer_id"
            },
            "NULL::text",
            "NULL::text",
            "NULL::text",
            "NULL::text",
            "review_type",
            "occurred_at",
        ),
        "bookings" => (
            "NULL::text",
            "requester_id",
            "requestee_id",
            "reference_event_id",
            "status",
            "NULL::text",
            if p.order.as_deref() == Some("timestamp") {
                "occurred_at"
            } else {
                "start_time"
            },
        ),
        _ => return Err(forbidden()),
    };
    if table == "bookings"
        && p.requester_id.is_none()
        && p.requestee_id.is_none()
        && p.reference_event_id.is_none()
    {
        return Err(AppError::bad_request(
            "booking participant or event required",
        ));
    }
    if table == "reviews"
        && (p.user_id.is_none()
            || !matches!(p.review_type.as_deref(), Some("performer" | "booker")))
    {
        return Err(AppError::bad_request("review type and user required"));
    }
    if matches!(table, "services" | "activities") && p.user_id.is_none() {
        return Err(AppError::bad_request("userId required"));
    }
    if p.mode.is_some()
        && (table != "opportunities"
            || uid.is_none()
            || p.user_id.as_deref() != uid
            || !matches!(p.mode.as_deref(), Some("feed" | "applied")))
    {
        return Err(forbidden());
    }
    let public_booking = if table == "bookings" {
        "AND (t.status='confirmed' OR t.requester_id=$10 OR t.requestee_id=$10)"
    } else {
        ""
    };
    let deleted = if matches!(table, "opportunities" | "services") {
        "AND NOT t.deleted"
    } else {
        ""
    };
    let mode = match p.mode.as_deref() {
        Some("feed") => {
            "AND t.start_time>=now() AND t.user_id<>$10 AND NOT EXISTS(SELECT 1 FROM opportunity_interested_users i WHERE i.opportunity_id=t.id AND i.user_id=$10) AND NOT EXISTS(SELECT 1 FROM opportunity_dismissals d WHERE d.opportunity_id=t.id AND d.user_id=$10)"
        }
        Some("applied") => {
            "AND t.start_time>=now() AND EXISTS(SELECT 1 FROM opportunity_interested_users i WHERE i.opportunity_id=t.id AND i.user_id=$10)"
        }
        _ => "",
    };
    let owner_filter = if p.mode.is_some() {
        "TRUE".to_owned()
    } else {
        format!(
            "($1::text IS NULL OR {owner_expr}=$1)",
            owner_expr = if owner.starts_with("NULL") {
                owner.to_owned()
            } else {
                format!("t.{owner}")
            }
        )
    };
    // COALESCE gives legacy undated records a stable ordering. The id breaks timestamp ties.
    let join = if table == "reviews" {
        "id,review_type,reviewee_id"
    } else {
        "id"
    };
    let cursor_kind = if table == "reviews" {
        "AND c.review_type=$6 AND c.reviewee_id=$1"
    } else {
        ""
    };
    let sql=format!("SELECT v.doc FROM {table} t JOIN api_{table} v USING({join})
        WHERE {owner_filter} AND ($2::text IS NULL OR {role1}=$2) AND ($3::text IS NULL OR {role2}=$3)
        AND ($4::text IS NULL OR {event}=$4) AND ($5::text IS NULL OR {status}=$5) AND ($6::text IS NULL OR {kind}=$6)
        AND ($7::text IS NULL OR (coalesce(t.{time},'-infinity'::timestamptz),t.id) <
            (SELECT coalesce(c.{time},'-infinity'::timestamptz),c.id FROM {table} c WHERE c.id=$7 {cursor_kind}))
        AND $9::text IS NOT NULL AND ($10::text IS NULL OR TRUE)
        {public_booking} {deleted} {mode}
        ORDER BY t.{time} DESC NULLS LAST,t.id DESC LIMIT $8");
    let rows: Vec<Value> = sqlx::query_scalar(&sql)
        .bind(&p.user_id)
        .bind(&p.requester_id)
        .bind(&p.requestee_id)
        .bind(&p.reference_event_id)
        .bind(&p.status)
        .bind(&p.review_type)
        .bind(&p.after)
        .bind(limit)
        .bind(table)
        .bind(uid)
        .fetch_all(pool(state)?)
        .await
        .map_err(db_error)?;
    Ok(Json(Value::Array(
        rows.into_iter()
            .filter_map(|v| visible(table, v, uid))
            .collect(),
    )))
}
pub async fn list_public(
    State(state): State<AppStateDyn>,
    Path(CollectionPath { table }): Path<CollectionPath>,
    Query(p): Query<ListParams>,
) -> ApiResult {
    list(&state, &table, p, None).await
}
pub async fn list_private(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(CollectionPath { table }): Path<CollectionPath>,
    Query(p): Query<ListParams>,
) -> ApiResult {
    list(&state, &table, p, Some(&user.uid)).await
}

fn writable(
    table: &str,
    doc: &Value,
    old: Option<&Value>,
    user: &FirebaseUser,
) -> Result<(), AppError> {
    let uid = user.uid.as_str();
    match table {
        "users" => {
            if text(doc, "id") != uid {
                return Err(forbidden());
            }
            // Privileges, subscription/credit balances and billing IDs are never client writable.
            let allowed = [
                "id",
                "username",
                "artistName",
                "bio",
                "occupations",
                "profilePicture",
                "location",
                "performerInfo",
                "venueInfo",
                "bookerInfo",
                "socialFollowing",
                "emailNotifications",
                "pushNotifications",
                "latestAppVersion",
                "website",
                "phoneNumber",
                "timestamp",
                "deleted",
            ];
            if doc
                .as_object()
                .is_none_or(|o| o.keys().any(|k| !allowed.contains(&k.as_str())))
            {
                return Err(AppError::bad_request("unsupported profile field"));
            }
        }
        "services" | "opportunities" => {
            if text(doc, "userId") != uid || old.is_some_and(|v| text(v, "userId") != uid) {
                return Err(forbidden());
            }
        }
        "bookings" => {
            if let Some(old) = old {
                if !participant(old, uid)
                    || ["requesterId", "requesteeId", "serviceId", "addedByUser"]
                        .iter()
                        .any(|k| old[*k] != doc[*k])
                {
                    return Err(forbidden());
                }
                if doc["status"] != old["status"] {
                    let transition = (text(old, "status"), text(doc, "status"));
                    if !matches!(
                        transition,
                        ("pending", "confirmed")
                            | ("pending", "canceled")
                            | ("confirmed", "canceled")
                    ) || transition == ("pending", "confirmed")
                        && uid != text(old, "requesteeId")
                    {
                        return Err(forbidden());
                    }
                }
                if uid != text(old, "requesterId")
                    && ["rate", "startTime", "endTime", "note", "name", "location"]
                        .iter()
                        .any(|k| old[*k] != doc[*k])
                    && old["addedByUser"] != true
                {
                    return Err(forbidden());
                }
            } else if !(text(doc, "requesterId") == uid && doc["status"] == "pending"
                || text(doc, "requesteeId") == uid
                    && doc["addedByUser"] == true
                    && doc["status"] == "confirmed")
            {
                return Err(forbidden());
            }
            if !matches!(text(doc, "status"), "pending" | "confirmed" | "canceled") {
                return Err(AppError::bad_request("invalid booking status"));
            }
        }
        "reviews" => {
            let author = match text(doc, "type") {
                "performer" => text(doc, "bookerId"),
                "booker" => text(doc, "performerId"),
                _ => return Err(AppError::bad_request("invalid review type")),
            };
            if author != uid || old.is_some() {
                return Err(forbidden());
            }
            if !doc["overallRating"]
                .as_f64()
                .is_some_and(|r| (1.0..=5.0).contains(&r))
            {
                return Err(AppError::bad_request("rating must be 1..5"));
            }
        }
        "activities" => {
            if let Some(old) = old {
                if text(old, "toUserId") != uid
                    || doc.as_object().is_none_or(|o| {
                        o.keys().any(|k| !matches!(k.as_str(), "id" | "markedRead"))
                    })
                {
                    return Err(forbidden());
                }
            } else if text(doc, "fromUserId") != uid || doc["type"] != "follow" {
                return Err(forbidden());
            }
        }
        _ => return Err(forbidden()),
    }
    Ok(())
}

/// Atomic replacement/patch through relational columns, with imported extension fields in profile.
/// The advisory lock prevents concurrent first writes racing ownership checks.
async fn save(
    state: &AppStateDyn,
    user: &FirebaseUser,
    table: &str,
    id: &str,
    mut input: Value,
    create: bool,
) -> ApiResult {
    let mapping = fields(table)?;
    safe_id(id)?;
    if !input.is_object() {
        return Err(AppError::bad_request("JSON object required"));
    }
    input["id"] = json!(id);
    if table == "reviews" {
        input["revieweeId"] = input[if input["type"] == "performer" {
            "performerId"
        } else {
            "bookerId"
        }]
        .clone();
    }
    let mut tx = pool(state)?.begin().await.map_err(db_error)?;
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))")
        .bind(format!("{table}:{id}"))
        .execute(&mut *tx)
        .await
        .map_err(db_error)?;
    let old: Option<Value> = if table == "reviews" {
        sqlx::query_scalar(
            "SELECT doc FROM api_reviews WHERE id=$1 AND review_type=$2 AND reviewee_id=$3",
        )
        .bind(id)
        .bind(text(&input, "type"))
        .bind(text(&input, "revieweeId"))
        .fetch_optional(&mut *tx)
        .await
        .map_err(db_error)?
    } else {
        sqlx::query_scalar(&format!("SELECT doc FROM api_{table} WHERE id=$1"))
            .bind(id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(db_error)?
    };
    if create && old.is_some() {
        return Err(AppError::new("already exists").with_status(StatusCode::CONFLICT));
    }
    if !create && old.is_none() {
        return Err(AppError::not_found("not found"));
    }
    let mut doc=old.clone().unwrap_or_else(|| json!({
        "id":id,"deleted":false,"count":0,"rate":0,"genres":[],"occupations":[],
        "username":"","artistName":"","bio":"","title":"","description":"","note":"","name":"",
        "addedByUser":false,"isPaid":false,"markedRead":false,"timestamp":chrono::Utc::now().to_rfc3339()
    }));
    // Check the submitted fields, then validate the merged record with immutable ownership.
    if table == "users" || table == "activities" {
        writable(table, &input, old.as_ref(), user)?;
    }
    for (k, v) in input.as_object().unwrap() {
        doc[k] = v.clone();
    }
    if table != "users" && table != "activities" {
        writable(table, &doc, old.as_ref(), user)?;
    }
    if table == "users" {
        // Ratings and classification are server-owned even inside editable profile objects.
        for (section, keys) in [
            ("performerInfo", &["rating", "reviewCount", "category"][..]),
            ("bookerInfo", &["rating", "reviewCount"][..]),
            ("venueInfo", &["topPerformerIds", "bookingsByDayOfWeek"][..]),
        ] {
            if let Some(object) = doc[section].as_object_mut() {
                for key in keys {
                    match old.as_ref().and_then(|v| v[section].get(*key)) {
                        Some(value) => {
                            object.insert((*key).to_owned(), value.clone());
                        }
                        None => {
                            object.remove(*key);
                        }
                    }
                }
            }
        }
        if old.is_none() {
            doc["email"] = json!(user.email.clone().unwrap_or_default());
            doc["unclaimed"] = json!(false);
            doc["shadowBanned"] = json!(false);
        }
        let username = text(&doc, "username");
        if username.is_empty()
            || username.len() > 64
            || ["anonymous", "*deleted*"].contains(&username)
            || !username
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
        {
            return Err(AppError::bad_request("invalid username"));
        }
    }
    if table == "reviews" {
        let booking_id = text(&doc, "bookingId");
        let booking: Option<Value> = sqlx::query_scalar("SELECT doc FROM api_bookings WHERE id=$1")
            .bind(booking_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(db_error)?;
        if booking.is_none_or(|b| {
            b["status"] != "confirmed"
                || b["requesteeId"] != doc["performerId"]
                || b["requesterId"] != doc["bookerId"]
        }) {
            return Err(forbidden());
        }
    }
    if let Some(point) = doc.get("location").filter(|v| !v.is_null()) {
        let lat = point["lat"].as_f64().or_else(|| point["latitude"].as_f64());
        let lng = point["lng"]
            .as_f64()
            .or_else(|| point["longitude"].as_f64());
        if !lat.is_some_and(|v| (-90.0..=90.0).contains(&v))
            || !lng.is_some_and(|v| (-180.0..=180.0).contains(&v))
        {
            return Err(AppError::bad_request("invalid location"));
        }
        doc["location"] = json!({"lat":lat,"lng":lng,"placeId":point["placeId"]});
        doc["placeId"] = doc["location"]["placeId"].clone();
    }
    for key in ["timestamp", "startTime", "endTime", "deadline"] {
        if let Some(v) = doc.get(key).filter(|v| !v.is_null())
            && !v
                .as_str()
                .is_some_and(|s| chrono::DateTime::parse_from_rfc3339(s).is_ok())
        {
            return Err(AppError::bad_request(format!("{key} must be RFC3339")));
        }
    }
    if matches!(table, "bookings" | "opportunities")
        && !doc["startTime"].is_null()
        && !doc["endTime"].is_null()
    {
        let start = chrono::DateTime::parse_from_rfc3339(text(&doc, "startTime"))
            .map_err(|_| AppError::bad_request("invalid time"))?;
        let end = chrono::DateTime::parse_from_rfc3339(text(&doc, "endTime"))
            .map_err(|_| AppError::bad_request("invalid time"))?;
        if start > end {
            return Err(AppError::bad_request("endTime precedes startTime"));
        }
    }
    if matches!(table, "bookings" | "opportunities")
        && (doc["startTime"].is_null() || doc["endTime"].is_null())
    {
        return Err(AppError::bad_request("startTime and endTime required"));
    }
    if table == "reviews" {
        let mut participants = [text(&doc, "bookerId"), text(&doc, "performerId")];
        participants.sort();
        for uid in participants {
            sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))")
                .bind(format!("users:{uid}"))
                .execute(&mut *tx)
                .await
                .map_err(db_error)?;
        }
    }
    persist(&mut tx, table, mapping, &doc).await?;
    if table == "users" && create {
        for title in ["30 min set", "45 min set", "60 min set"] {
            sqlx::query("INSERT INTO services(id,user_id,title,description,rate_type) VALUES($1,$2,$3,$3,'hourly')")
                .bind(uuid::Uuid::new_v4().to_string()).bind(id).bind(title).execute(&mut *tx).await.map_err(db_error)?;
        }
    }
    if table == "bookings" && (create || old.as_ref().is_some_and(|v| v["status"] != doc["status"]))
    {
        let recipient = if text(&doc, "requesterId") == user.uid {
            text(&doc, "requesteeId")
        } else {
            text(&doc, "requesterId")
        };
        if !recipient.is_empty() && recipient != user.uid {
            sqlx::query("INSERT INTO activities(id,activity_type,from_user_id,to_user_id,booking_id,occurred_at,profile) VALUES($1,$2,$3,$4,$5,now(),$6)")
                .bind(uuid::Uuid::new_v4().to_string()).bind(if create {"bookingRequest"} else {"bookingUpdate"})
                .bind(&user.uid).bind(recipient).bind(id).bind(json!({"status":doc["status"]})).execute(&mut *tx).await.map_err(db_error)?;
        }
    }
    if table == "reviews" {
        let (uid, section) = if doc["type"] == "performer" {
            (text(&doc, "performerId"), "performerInfo")
        } else {
            (text(&doc, "bookerId"), "bookerInfo")
        };
        sqlx::query("UPDATE users SET profile=jsonb_set(profile,ARRAY[$2],(CASE WHEN jsonb_typeof(profile->$2)='object' THEN profile->$2 ELSE '{}'::jsonb END) || jsonb_build_object('reviewCount',(SELECT count(*) FROM reviews WHERE (CASE WHEN $3='performer' THEN performer_id ELSE booker_id END)=$1 AND review_type=$3),'rating',(SELECT avg(overall_rating) FROM reviews WHERE (CASE WHEN $3='performer' THEN performer_id ELSE booker_id END)=$1 AND review_type=$3))) WHERE id=$1")
            .bind(uid).bind(section).bind(text(&doc,"type")).execute(&mut *tx).await.map_err(db_error)?;
    }
    tx.commit().await.map_err(db_error)?;
    Ok(Json(json!({"id":id})))
}
async fn persist(
    tx: &mut Transaction<'_, Postgres>,
    table: &str,
    mapping: &[(&str, &str)],
    doc: &Value,
) -> Result<(), AppError> {
    let mut row = json!({"id":doc["id"],"profile":doc});
    for (key, col) in mapping {
        row[*col] = doc[*key].clone();
    }
    let columns = std::iter::once("id")
        .chain(mapping.iter().map(|(_, c)| *c))
        .chain(std::iter::once("profile"))
        .collect::<Vec<_>>();
    let geo = matches!(table, "users" | "bookings" | "opportunities");
    let location = if geo { ",location" } else { "" };
    let geo_select = if geo {
        ",CASE WHEN $2::double precision IS NULL THEN NULL ELSE ST_SetSRID(ST_MakePoint($3::double precision,$2::double precision),4326)::geography END"
    } else {
        ""
    };
    let updates = columns
        .iter()
        .filter(|c| **c != "id")
        .map(|c| format!("{c}=EXCLUDED.{c}"))
        .collect::<Vec<_>>()
        .join(",");
    let sql = format!(
        "INSERT INTO {table} ({cols}{location}) SELECT {cols}{geo_select} FROM jsonb_populate_record(NULL::{table},$1::jsonb) ON CONFLICT({conflict}) DO UPDATE SET {updates}{geo_update}",
        conflict = if table == "reviews" {
            "id,review_type,reviewee_id"
        } else {
            "id"
        },
        cols = columns.join(","),
        geo_update = if geo {
            ",location=EXCLUDED.location"
        } else {
            ""
        }
    );
    let mut q = sqlx::query(&sql).bind(row);
    if geo {
        q = q
            .bind(doc["location"]["lat"].as_f64())
            .bind(doc["location"]["lng"].as_f64());
    }
    q.execute(&mut **tx).await.map_err(db_error)?;
    Ok(())
}
pub async fn create(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(CollectionPath { table }): Path<CollectionPath>,
    Json(input): Json<Value>,
) -> ApiResult {
    let id = text(&input, "id").to_owned();
    save(&state, &user, &table, &id, input, true).await
}
pub async fn update(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(DocumentPath { table, id }): Path<DocumentPath>,
    Json(input): Json<Value>,
) -> ApiResult {
    save(&state, &user, &table, &id, input, false).await
}
pub async fn remove(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(DocumentPath { table, id }): Path<DocumentPath>,
) -> ApiResult {
    if !matches!(table.as_str(), "users" | "services" | "opportunities") {
        return Err(forbidden());
    }
    let old = document(pool(&state)?, &table, &id)
        .await?
        .ok_or_else(|| AppError::not_found("not found"))?;
    let input = if table == "users" {
        json!({"deleted":true})
    } else {
        json!({"deleted":true,"userId":old["userId"]})
    };
    save(&state, &user, &table, &id, input, false).await
}
pub async fn booking_count(State(state): State<AppStateDyn>, Path(id): Path<String>) -> ApiResult {
    safe_id(&id)?;
    let count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM bookings WHERE requestee_id=$1 AND status='confirmed'",
    )
    .bind(id)
    .fetch_one(pool(&state)?)
    .await
    .map_err(db_error)?;
    Ok(Json(json!(count)))
}
pub async fn username_available(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(username): Path<String>,
) -> ApiResult {
    safe_id(&username)?;
    let exists: bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM users WHERE lower(username)=lower($1) AND id<>$2 AND NOT deleted)").bind(&username).bind(user.uid).fetch_one(pool(&state)?).await.map_err(db_error)?;
    Ok(Json(json!(
        !exists && !["anonymous", "*deleted*"].contains(&username.as_str())
    )))
}
pub async fn interests(State(state): State<AppStateDyn>, Path(id): Path<String>) -> ApiResult {
    safe_id(&id)?;
    let docs: Vec<Value>=sqlx::query_scalar("SELECT u.doc FROM opportunity_interested_users i JOIN api_users u ON u.id=i.user_id JOIN opportunities o ON o.id=i.opportunity_id WHERE i.opportunity_id=$1 AND NOT o.deleted ORDER BY i.created_at DESC,i.user_id DESC").bind(id).fetch_all(pool(&state)?).await.map_err(db_error)?;
    Ok(Json(json!(
        docs.into_iter().filter_map(public_user).collect::<Vec<_>>()
    )))
}
pub async fn interest_status(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(id): Path<String>,
) -> ApiResult {
    safe_id(&id)?;
    let exists: bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM opportunity_interested_users WHERE opportunity_id=$1 AND user_id=$2)").bind(id).bind(user.uid).fetch_one(pool(&state)?).await.map_err(db_error)?;
    Ok(Json(json!(exists)))
}
pub async fn set_interest(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(id): Path<String>,
    Json(input): Json<Value>,
) -> ApiResult {
    safe_id(&id)?;
    let mut tx = pool(&state)?.begin().await.map_err(db_error)?;
    let allowed: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM opportunities WHERE id=$1 AND NOT deleted AND user_id<>$2)",
    )
    .bind(&id)
    .bind(&user.uid)
    .fetch_one(&mut *tx)
    .await
    .map_err(db_error)?;
    if !allowed {
        return Err(AppError::not_found("opportunity not found"));
    }
    match text(&input, "action") {
        "apply" => {
            let comment = text(&input, "userComment");
            if comment.len() > 4000 {
                return Err(AppError::bad_request("comment too long"));
            }
            sqlx::query("INSERT INTO opportunity_interested_users(opportunity_id,user_id,profile) VALUES($1,$2,$3) ON CONFLICT(opportunity_id,user_id) DO UPDATE SET profile=EXCLUDED.profile")
             .bind(&id).bind(&user.uid).bind(json!({"userComment":comment,"timestamp":chrono::Utc::now().to_rfc3339()})).execute(&mut *tx).await.map_err(db_error)?;
        }
        "dislike" => {
            sqlx::query("INSERT INTO opportunity_dismissals(opportunity_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING").bind(&id).bind(&user.uid).execute(&mut *tx).await.map_err(db_error)?;
        }
        _ => return Err(AppError::bad_request("invalid action")),
    }
    tx.commit().await.map_err(db_error)?;
    Ok(Json(json!({"id":id})))
}
async fn search_docs(
    state: &AppStateDyn,
    table: &str,
    p: crate::data::pg_search::SearchParams,
    uid: Option<&str>,
) -> ApiResult {
    if !matches!(table, "users" | "bookings" | "opportunities") {
        return Err(forbidden());
    }
    p.validate()
        .map_err(|e| AppError::bad_request(e.to_string()))?;
    let docs = crate::data::pg_search::documents(pool(state)?, table, &p, uid)
        .await
        .map_err(|e| AppError::internal("database search failed", e))?;
    Ok(Json(Value::Array(
        docs.into_iter()
            .filter_map(|v| visible(table, v, uid))
            .collect(),
    )))
}
pub async fn search_public(
    State(state): State<AppStateDyn>,
    Path(CollectionPath { table }): Path<CollectionPath>,
    Json(p): Json<crate::data::pg_search::SearchParams>,
) -> ApiResult {
    search_docs(&state, &table, p, None).await
}
pub async fn search_private(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Path(CollectionPath { table }): Path<CollectionPath>,
    Json(p): Json<crate::data::pg_search::SearchParams>,
) -> ApiResult {
    search_docs(&state, &table, p, Some(&user.uid)).await
}
pub async fn register_token(
    State(state): State<AppStateDyn>,
    user: FirebaseUser,
    Json(input): Json<Value>,
) -> ApiResult {
    let token = text(&input, "token");
    if token.is_empty() || token.len() > 4096 {
        return Err(AppError::bad_request("invalid token"));
    }
    sqlx::query("INSERT INTO device_tokens(token,user_id,platform) VALUES($1,$2,$3) ON CONFLICT(token) DO UPDATE SET user_id=EXCLUDED.user_id,platform=EXCLUDED.platform")
      .bind(token).bind(user.uid).bind(text(&input,"platform")).execute(pool(&state)?).await.map_err(db_error)?;
    Ok(Json(json!({"ok":true})))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn public_profile_and_private_bookings_are_guarded() {
        assert!(visible("activities", json!({"toUserId":"someone"}), Some("other")).is_none());
        assert!(
            visible(
                "bookings",
                json!({"status":"pending","requesterId":"a","requesteeId":"b"}),
                Some("c")
            )
            .is_none()
        );
        let b = visible(
            "bookings",
            json!({"status":"confirmed","note":"secret","rate":500,"name":"show"}),
            None,
        )
        .unwrap();
        assert!(b.get("note").is_none());
        assert!(b.get("rate").is_none());
    }
    #[test]
    fn prevents_ownership_and_privilege_changes() {
        let user = FirebaseUser {
            uid: "a".into(),
            email: None,
        };
        assert!(
            writable(
                "users",
                &json!({"id":"a","stripeCustomerId":"fake"}),
                None,
                &user
            )
            .is_err()
        );
        assert!(
            writable(
                "services",
                &json!({"userId":"a"}),
                Some(&json!({"userId":"b"})),
                &user
            )
            .is_err()
        );
        assert!(
            writable(
                "bookings",
                &json!({"requesterId":"a","requesteeId":"b","status":"confirmed"}),
                None,
                &user
            )
            .is_err()
        );
        assert!(
            writable(
                "reviews",
                &json!({"type":"performer","bookerId":"b","overallRating":5}),
                None,
                &user
            )
            .is_err()
        );
    }
}
