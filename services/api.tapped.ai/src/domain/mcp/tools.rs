//! The MCP tools: read-only views for the signed-in performer. Each tool calls the same handler
//! the iOS app uses, as that user, so ownership and privacy rules are exactly the app's.

use axum::{
    Json,
    extract::{Path, Query, State},
};
use chrono::{DateTime, Utc};
use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::{Value, json};

use crate::{
    data::pg_search::SearchParams,
    domain::{
        app_data::{self, CollectionPath, DocumentPath, ListParams},
        firebase_auth::FirebaseUser,
        places::{self, AutocompleteParams},
    },
    errors::AppError,
    state::AppStateDyn,
};

pub const INSTRUCTIONS: &str = "Tapped helps performers (musicians, DJs, bands) find venues to perform at and get booked. \
These read-only tools see what the signed-in performer can see.
- Use search to find venues, other performers and cities, and get_profile for a venue's or performer's details.
- list_my_bookings shows the performer's gigs. Rates are in cents (USD); times are ISO 8601.
- Opportunities are gigs the performer can apply to in the Tapped app.";

/// "Performers" in search means everyone but venues and promoters ("booker" is the legacy name
/// for promoter), matching how the web app splits results. Matched case-insensitively.
const NON_PERFORMER_OCCUPATIONS: [&str; 3] = ["venue", "promoter", "booker"];

/// A failed call, reported to the model as a tool error rather than a protocol error.
pub struct ToolError(pub String);

impl From<AppError> for ToolError {
    fn from(error: AppError) -> Self {
        let hint = match error.status.as_u16() {
            403 => " The signed-in user is not allowed to see this.",
            404 => " Check the ID.",
            _ => "",
        };
        ToolError(format!("{}{hint}", error.error))
    }
}

fn invalid(message: impl Into<String>) -> ToolError {
    ToolError(message.into())
}

fn args<T: DeserializeOwned>(arguments: Value) -> Result<T, ToolError> {
    let arguments = if arguments.is_null() {
        json!({})
    } else {
        arguments
    };
    serde_json::from_value(arguments)
        .map_err(|error| invalid(format!("Invalid arguments: {error}")))
}

fn id(value: &str, name: &str) -> Result<String, ToolError> {
    let valid = !value.is_empty()
        && value.len() <= 128
        && value
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'));
    valid
        .then(|| value.to_owned())
        .ok_or_else(|| invalid(format!("{name} is not a valid ID")))
}

fn limit(value: Option<i64>, default: i64, max: i64) -> Result<i64, ToolError> {
    let value = value.unwrap_or(default);
    (1..=max)
        .contains(&value)
        .then_some(value)
        .ok_or_else(|| invalid(format!("limit must be 1..{max}")))
}

/// Tool definitions for `tools/list`.
pub fn definitions() -> Value {
    let read_only = json!({ "readOnlyHint": true, "openWorldHint": false });
    let limit = |max: i64, default: i64| json!({ "type": "integer", "minimum": 1, "maximum": max, "default": default });
    let after = json!({ "type": "string", "description": "Pagination cursor: the ID of the last item from the previous page." });
    let tool = |name: &str, title: &str, description: &str, properties: Value, required: Value| {
        json!({
            "name": name,
            "title": title,
            "description": description,
            "inputSchema": {
                "type": "object",
                "properties": properties,
                "required": required,
                "additionalProperties": false,
            },
            "annotations": read_only,
        })
    };
    json!([
        tool(
            "search",
            "Search Tapped",
            "Search performers, venues and cities, like the Tapped web app's search. Choose which with `types` \
             (default: all three). To find venues or performers around a city, search cities first and pass the \
             city's placeId as `near`, or pass lat/lng.",
            json!({
                "query": { "type": "string", "maxLength": 200, "description": "Name or keywords. Cities need a query; performers and venues can filter by location alone." },
                "types": { "type": "array", "items": { "enum": ["performers", "venues", "cities"] }, "minItems": 1, "default": ["performers", "venues", "cities"] },
                "near": { "type": "string", "description": "A city placeId from a previous `cities` result." },
                "lat": { "type": "number", "minimum": -90, "maximum": 90 },
                "lng": { "type": "number", "minimum": -180, "maximum": 180 },
                "radiusMeters": { "type": "integer", "minimum": 1, "maximum": 500_000, "description": "Around `near` or lat/lng; default 50 km." },
                "genres": { "type": "array", "items": { "type": "string" }, "maxItems": 20, "description": "Performers who play, or venues that book, these genres." },
                "minCapacity": { "type": "integer", "minimum": 0, "description": "Venues only." },
                "maxCapacity": { "type": "integer", "minimum": 0, "description": "Venues only." },
                "limit": limit(50, 10),
            }),
            json!([]),
        ),
        tool(
            "get_profile",
            "Get a profile",
            "A performer's or venue's public profile by user ID or username.",
            json!({ "userId": { "type": "string" }, "username": { "type": "string" } }),
            json!([]),
        ),
        tool(
            "list_my_bookings",
            "List my bookings",
            "The signed-in performer's bookings: requests they received and/or bookings they sent, newest start time first.",
            json!({
                "direction": { "enum": ["received", "sent", "both"], "default": "both" },
                "status": { "enum": ["pending", "confirmed", "canceled"] },
                "limit": limit(100, 20),
                "after": { "type": "string", "description": "Pagination cursor (only with received or sent)." },
            }),
            json!([]),
        ),
        tool(
            "get_booking",
            "Get a booking",
            "One booking. Participants see all fields; others only see confirmed public history.",
            json!({ "bookingId": { "type": "string" } }),
            json!(["bookingId"]),
        ),
        tool(
            "list_opportunities",
            "List opportunities",
            "Gig opportunities for the signed-in performer: 'feed' = upcoming ones they haven't applied to or \
             dismissed, 'applied' = upcoming ones they applied to.",
            json!({ "view": { "enum": ["feed", "applied"], "default": "feed" }, "limit": limit(100, 20), "after": after }),
            json!([]),
        ),
        tool(
            "search_opportunities",
            "Search opportunities",
            "Search gig opportunities for performers by keyword, genre, location and start date.",
            json!({
                "query": { "type": "string", "maxLength": 200 },
                "genres": { "type": "array", "items": { "type": "string" }, "maxItems": 20 },
                "lat": { "type": "number", "minimum": -90, "maximum": 90 },
                "lng": { "type": "number", "minimum": -180, "maximum": 180 },
                "radiusMeters": { "type": "integer", "minimum": 1, "maximum": 500_000 },
                "startingAfter": { "type": "string", "format": "date-time", "description": "Only opportunities starting after this ISO 8601 time." },
                "limit": limit(100, 20),
            }),
            json!([]),
        ),
        tool(
            "get_opportunity",
            "Get an opportunity",
            "One opportunity, plus whether the signed-in performer has applied.",
            json!({ "opportunityId": { "type": "string" } }),
            json!(["opportunityId"]),
        ),
    ])
}

/// Runs a tool; `Ok(None)` for an unknown tool name.
pub async fn call(
    state: &AppStateDyn,
    user: &FirebaseUser,
    name: &str,
    arguments: Value,
) -> Option<Result<Value, ToolError>> {
    Some(match name {
        "search" => search(state, user, arguments).await,
        "get_profile" => get_profile(state, user, arguments).await,
        "list_my_bookings" => list_my_bookings(state, user, arguments).await,
        "get_booking" => get_booking(state, user, arguments).await,
        "list_opportunities" => list_opportunities(state, user, arguments).await,
        "search_opportunities" => search_opportunities(state, user, arguments).await,
        "get_opportunity" => get_opportunity(state, user, arguments).await,
        _ => return None,
    })
}

async fn get_doc(
    state: &AppStateDyn,
    user: &FirebaseUser,
    table: &str,
    id: String,
) -> Result<Value, ToolError> {
    let path = DocumentPath {
        table: table.into(),
        id,
    };
    let Json(doc) = app_data::get_private(
        State(state.clone()),
        user.clone(),
        Path(path),
        Query(ListParams::default()),
    )
    .await?;
    Ok(doc)
}

async fn list(
    state: &AppStateDyn,
    user: &FirebaseUser,
    table: &str,
    params: ListParams,
) -> Result<Value, ToolError> {
    let path = CollectionPath {
        table: table.into(),
    };
    let Json(docs) = app_data::list_private(
        State(state.clone()),
        user.clone(),
        Path(path),
        Query(params),
    )
    .await?;
    Ok(docs)
}

async fn search_table(
    state: &AppStateDyn,
    user: &FirebaseUser,
    table: &str,
    params: SearchParams,
) -> Result<Value, ToolError> {
    let path = CollectionPath {
        table: table.into(),
    };
    let Json(docs) =
        app_data::search_private(State(state.clone()), user.clone(), Path(path), Json(params))
            .await?;
    Ok(docs)
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SearchArgs {
    #[serde(default)]
    query: String,
    types: Option<Vec<String>>,
    near: Option<String>,
    lat: Option<f64>,
    lng: Option<f64>,
    radius_meters: Option<u64>,
    #[serde(default)]
    genres: Vec<String>,
    min_capacity: Option<u32>,
    max_capacity: Option<u32>,
    limit: Option<i64>,
}

async fn search(
    state: &AppStateDyn,
    user: &FirebaseUser,
    arguments: Value,
) -> Result<Value, ToolError> {
    let a: SearchArgs = args(arguments)?;
    let hits = limit(a.limit, 10, 50)? as u32;
    let types = a
        .types
        .unwrap_or_else(|| vec!["performers".into(), "venues".into(), "cities".into()]);
    if types.is_empty()
        || types
            .iter()
            .any(|t| !matches!(t.as_str(), "performers" | "venues" | "cities"))
    {
        return Err(invalid(
            "types must be a non-empty list of performers, venues and cities",
        ));
    }
    let want = |t: &str| types.iter().any(|v| v == t);

    let (mut lat, mut lng) = (a.lat, a.lng);
    if let Some(place_id) = &a.near {
        // Cached by the API; a cache miss is a billed Google lookup.
        let place = places::place_details(state, place_id, None).await?;
        (lat, lng) = (Some(place.lat), Some(place.lng));
    }
    if lat.is_some() != lng.is_some() {
        return Err(invalid("Provide both lat and lng, or neither."));
    }
    let base = SearchParams {
        q: a.query.clone(),
        hits_per_page: Some(hits),
        lat,
        lng,
        radius: lat.and(a.radius_meters),
        ..Default::default()
    };

    let mut result = serde_json::Map::new();
    if want("performers") {
        let params = SearchParams {
            occupations_blacklist: NON_PERFORMER_OCCUPATIONS.map(str::to_owned).to_vec(),
            genres: a.genres.clone(),
            ..base.clone()
        };
        result.insert(
            "performers".into(),
            search_table(state, user, "users", params).await?,
        );
    }
    if want("venues") {
        let params = SearchParams {
            occupations: vec!["venue".into()],
            venue_genres: a.genres.clone(),
            min_capacity: a.min_capacity,
            max_capacity: a.max_capacity,
            ..base.clone()
        };
        result.insert(
            "venues".into(),
            search_table(state, user, "users", params).await?,
        );
    }
    if want("cities") {
        let cities = if a.query.trim().is_empty() {
            json!([])
        } else {
            let params = AutocompleteParams {
                query: a.query.clone(),
                types: Some("locality".into()),
                session_token: None,
            };
            let Json(predictions) =
                places::autocomplete_places(State(state.clone()), Query(params)).await?;
            json!(
                predictions
                    .into_iter()
                    .take(hits as usize)
                    .collect::<Vec<_>>()
            )
        };
        result.insert("cities".into(), cities);
    }
    Ok(Value::Object(result))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ProfileArgs {
    user_id: Option<String>,
    username: Option<String>,
}

async fn get_profile(
    state: &AppStateDyn,
    user: &FirebaseUser,
    arguments: Value,
) -> Result<Value, ToolError> {
    let a: ProfileArgs = args(arguments)?;
    if let Some(user_id) = a.user_id {
        return get_doc(state, user, "users", id(&user_id, "userId")?).await;
    }
    let username = id(
        a.username.as_deref().unwrap_or("").trim_start_matches('@'),
        "username",
    )
    .map_err(|_| invalid("Provide userId or a valid username."))?;
    let doc = state
        .database
        .get_user_doc_by_username(&username)
        .await
        .map_err(|error| AppError::internal("profile lookup failed", error))?;
    doc.and_then(|doc| app_data::visible("users", doc, Some(&user.uid)))
        .ok_or_else(|| invalid(format!("No profile with username {username}.")))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct BookingsArgs {
    direction: Option<String>,
    status: Option<String>,
    limit: Option<i64>,
    after: Option<String>,
}

async fn list_my_bookings(
    state: &AppStateDyn,
    user: &FirebaseUser,
    arguments: Value,
) -> Result<Value, ToolError> {
    let a: BookingsArgs = args(arguments)?;
    let limit = limit(a.limit, 20, 100)?;
    if a.status
        .as_deref()
        .is_some_and(|s| !matches!(s, "pending" | "confirmed" | "canceled"))
    {
        return Err(invalid("status must be pending, confirmed or canceled"));
    }
    let page = |received: bool| ListParams {
        requester_id: (!received).then(|| user.uid.clone()),
        requestee_id: received.then(|| user.uid.clone()),
        status: a.status.clone(),
        limit: Some(limit),
        after: a.after.clone(),
        ..Default::default()
    };
    match a.direction.as_deref().unwrap_or("both") {
        "received" => list(state, user, "bookings", page(true)).await,
        "sent" => list(state, user, "bookings", page(false)).await,
        "both" => {
            if a.after.is_some() {
                return Err(invalid("after requires direction received or sent."));
            }
            let mut all = Vec::new();
            for received in [true, false] {
                if let Value::Array(docs) = list(state, user, "bookings", page(received)).await? {
                    for doc in docs {
                        if !all.iter().any(|d: &Value| d["id"] == doc["id"]) {
                            all.push(doc);
                        }
                    }
                }
            }
            let start = |d: &Value| d["startTime"].as_str().unwrap_or("").to_owned();
            all.sort_by_key(|d| std::cmp::Reverse(start(d)));
            all.truncate(limit as usize);
            Ok(Value::Array(all))
        }
        _ => Err(invalid("direction must be received, sent or both")),
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct BookingArgs {
    booking_id: String,
}

async fn get_booking(
    state: &AppStateDyn,
    user: &FirebaseUser,
    arguments: Value,
) -> Result<Value, ToolError> {
    let a: BookingArgs = args(arguments)?;
    get_doc(state, user, "bookings", id(&a.booking_id, "bookingId")?).await
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct OpportunitiesArgs {
    view: Option<String>,
    limit: Option<i64>,
    after: Option<String>,
}

async fn list_opportunities(
    state: &AppStateDyn,
    user: &FirebaseUser,
    arguments: Value,
) -> Result<Value, ToolError> {
    let a: OpportunitiesArgs = args(arguments)?;
    let view = a.view.unwrap_or_else(|| "feed".into());
    if !matches!(view.as_str(), "feed" | "applied") {
        return Err(invalid("view must be feed or applied"));
    }
    let params = ListParams {
        user_id: Some(user.uid.clone()),
        mode: Some(view),
        limit: Some(limit(a.limit, 20, 100)?),
        after: a.after.map(|after| id(&after, "after")).transpose()?,
        ..Default::default()
    };
    list(state, user, "opportunities", params).await
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SearchOpportunitiesArgs {
    #[serde(default)]
    query: String,
    #[serde(default)]
    genres: Vec<String>,
    lat: Option<f64>,
    lng: Option<f64>,
    radius_meters: Option<u64>,
    starting_after: Option<DateTime<Utc>>,
    limit: Option<i64>,
}

async fn search_opportunities(
    state: &AppStateDyn,
    user: &FirebaseUser,
    arguments: Value,
) -> Result<Value, ToolError> {
    let a: SearchOpportunitiesArgs = args(arguments)?;
    if a.lat.is_some() != a.lng.is_some() {
        return Err(invalid("Provide both lat and lng, or neither."));
    }
    let params = SearchParams {
        q: a.query,
        genres: a.genres,
        lat: a.lat,
        lng: a.lng,
        radius: a.lat.and(a.radius_meters),
        start_time: a.starting_after,
        hits_per_page: Some(limit(a.limit, 20, 100)? as u32),
        ..Default::default()
    };
    search_table(state, user, "opportunities", params).await
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct OpportunityArgs {
    opportunity_id: String,
}

async fn get_opportunity(
    state: &AppStateDyn,
    user: &FirebaseUser,
    arguments: Value,
) -> Result<Value, ToolError> {
    let a: OpportunityArgs = args(arguments)?;
    let opportunity_id = id(&a.opportunity_id, "opportunityId")?;
    let mut doc = get_doc(state, user, "opportunities", opportunity_id.clone()).await?;
    let Json(applied) =
        app_data::interest_status(State(state.clone()), user.clone(), Path(opportunity_id)).await?;
    doc["appliedBySignedInUser"] = applied;
    Ok(doc)
}
