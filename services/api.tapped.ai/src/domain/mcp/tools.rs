//! The MCP tools: read-only views for the signed-in performer. Each tool calls the same handler
//! the iOS app uses, as that user, so ownership and privacy rules are exactly the app's.

use axum::{
    Json,
    extract::{Path, Query, State},
    http::request::Parts,
};
use chrono::{DateTime, Utc};
use rmcp::{
    ErrorData as McpError, ServerHandler,
    handler::server::{router::tool::ToolRouter, tool::Extension, wrapper::Parameters},
    model::{CallToolResult, ContentBlock, Implementation, ServerCapabilities, ServerConfig},
    schemars::{self, JsonSchema},
    tool, tool_handler, tool_router,
};
use serde::Deserialize;
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
struct ToolError(String);

impl From<AppError> for ToolError {
    fn from(error: AppError) -> Self {
        let hint = match error.status.as_u16() {
            403 => " The signed-in user is not allowed to see this.",
            404 => " Check the ID.",
            _ => "",
        };
        ToolError(format!("{}.{hint}", error.error.trim_end_matches('.')))
    }
}

fn invalid(message: impl Into<String>) -> ToolError {
    ToolError(message.into())
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

/// One MCP server per request (stateless). The signed-in user comes from the access token,
/// checked by `mcp::require_access_token` before the request reaches rmcp.
#[derive(Clone)]
pub struct TappedMcp {
    state: AppStateDyn,
    tool_router: ToolRouter<Self>,
}

impl TappedMcp {
    pub fn new(state: AppStateDyn) -> Self {
        Self {
            state,
            tool_router: Self::tool_router(),
        }
    }

    async fn run<F>(&self, parts: &Parts, tool: F) -> Result<CallToolResult, McpError>
    where
        F: AsyncFnOnce(&AppStateDyn, &FirebaseUser) -> Result<Value, ToolError>,
    {
        let user = parts
            .extensions
            .get::<FirebaseUser>()
            .cloned()
            .ok_or_else(|| McpError::internal_error("missing authenticated user", None))?;
        Ok(match tool(&self.state, &user).await {
            Ok(value) => CallToolResult::success(vec![ContentBlock::text(
                serde_json::to_string_pretty(&value).unwrap_or_default(),
            )]),
            Err(ToolError(message)) => CallToolResult::error(vec![ContentBlock::text(message)]),
        })
    }
}

#[tool_router]
impl TappedMcp {
    /// Search performers, venues and cities, like the Tapped web app's search. Choose which with
    /// `types` (default: all three). To find venues or performers around a city, search cities
    /// first and pass the city's placeId as `near`, or pass lat/lng.
    #[tool(annotations(
        title = "Search Tapped",
        read_only_hint = true,
        open_world_hint = false
    ))]
    async fn search(
        &self,
        Extension(parts): Extension<Parts>,
        Parameters(a): Parameters<SearchArgs>,
    ) -> Result<CallToolResult, McpError> {
        self.run(&parts, async |state, user| search(state, user, a).await)
            .await
    }

    /// A performer's or venue's public profile by user ID or username.
    #[tool(annotations(
        title = "Get a profile",
        read_only_hint = true,
        open_world_hint = false
    ))]
    async fn get_profile(
        &self,
        Extension(parts): Extension<Parts>,
        Parameters(a): Parameters<ProfileArgs>,
    ) -> Result<CallToolResult, McpError> {
        self.run(&parts, async |state, user| {
            get_profile(state, user, a).await
        })
        .await
    }

    /// The signed-in performer's bookings: requests they received and/or bookings they sent,
    /// newest start time first.
    #[tool(annotations(
        title = "List my bookings",
        read_only_hint = true,
        open_world_hint = false
    ))]
    async fn list_my_bookings(
        &self,
        Extension(parts): Extension<Parts>,
        Parameters(a): Parameters<BookingsArgs>,
    ) -> Result<CallToolResult, McpError> {
        self.run(&parts, async |state, user| {
            list_my_bookings(state, user, a).await
        })
        .await
    }

    /// One booking. Participants see all fields; others only see confirmed public history.
    #[tool(annotations(
        title = "Get a booking",
        read_only_hint = true,
        open_world_hint = false
    ))]
    async fn get_booking(
        &self,
        Extension(parts): Extension<Parts>,
        Parameters(a): Parameters<BookingArgs>,
    ) -> Result<CallToolResult, McpError> {
        self.run(&parts, async |state, user| {
            get_doc(state, user, "bookings", id(&a.booking_id, "bookingId")?).await
        })
        .await
    }

    /// Gig opportunities for the signed-in performer: `feed` = upcoming ones they haven't applied
    /// to or dismissed, `applied` = upcoming ones they applied to.
    #[tool(annotations(
        title = "List opportunities",
        read_only_hint = true,
        open_world_hint = false
    ))]
    async fn list_opportunities(
        &self,
        Extension(parts): Extension<Parts>,
        Parameters(a): Parameters<OpportunitiesArgs>,
    ) -> Result<CallToolResult, McpError> {
        self.run(&parts, async |state, user| {
            list_opportunities(state, user, a).await
        })
        .await
    }

    /// Search gig opportunities for performers by keyword, genre, location and start date.
    #[tool(annotations(
        title = "Search opportunities",
        read_only_hint = true,
        open_world_hint = false
    ))]
    async fn search_opportunities(
        &self,
        Extension(parts): Extension<Parts>,
        Parameters(a): Parameters<SearchOpportunitiesArgs>,
    ) -> Result<CallToolResult, McpError> {
        self.run(&parts, async |state, user| {
            search_opportunities(state, user, a).await
        })
        .await
    }

    /// One opportunity, plus whether the signed-in performer has applied.
    #[tool(annotations(
        title = "Get an opportunity",
        read_only_hint = true,
        open_world_hint = false
    ))]
    async fn get_opportunity(
        &self,
        Extension(parts): Extension<Parts>,
        Parameters(a): Parameters<OpportunityArgs>,
    ) -> Result<CallToolResult, McpError> {
        self.run(&parts, async |state, user| {
            get_opportunity(state, user, a).await
        })
        .await
    }
}

#[tool_handler(router = self.tool_router)]
impl ServerHandler for TappedMcp {
    fn get_info(&self) -> ServerConfig {
        ServerConfig::new(ServerCapabilities::builder().enable_tools().build())
            .with_server_info(
                Implementation::new("tapped", env!("CARGO_PKG_VERSION")).with_title("Tapped"),
            )
            .with_instructions(INSTRUCTIONS)
    }
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

#[derive(Deserialize, JsonSchema, PartialEq, Clone, Copy)]
#[serde(rename_all = "lowercase")]
enum SearchType {
    Performers,
    Venues,
    Cities,
}

#[derive(Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SearchArgs {
    /// Name or keywords. Cities need a query; performers and venues can filter by location alone.
    #[serde(default)]
    #[schemars(length(max = 200))]
    query: String,
    /// Which results to return; default all three.
    types: Option<Vec<SearchType>>,
    /// A city placeId from a previous `cities` result.
    near: Option<String>,
    #[schemars(range(min = -90.0, max = 90.0))]
    lat: Option<f64>,
    #[schemars(range(min = -180.0, max = 180.0))]
    lng: Option<f64>,
    /// Around `near` or lat/lng; default 50 km.
    #[schemars(range(min = 1, max = 500_000))]
    radius_meters: Option<u64>,
    /// Performers who play, or venues that book, these genres.
    #[serde(default)]
    #[schemars(length(max = 20))]
    genres: Vec<String>,
    /// Venues only.
    min_capacity: Option<u32>,
    /// Venues only.
    max_capacity: Option<u32>,
    /// Maximum results per type (1-50, default 10).
    #[schemars(range(min = 1, max = 50))]
    limit: Option<i64>,
}

async fn search(
    state: &AppStateDyn,
    user: &FirebaseUser,
    a: SearchArgs,
) -> Result<Value, ToolError> {
    let hits = limit(a.limit, 10, 50)? as u32;
    let types = a.types.unwrap_or_else(|| {
        vec![
            SearchType::Performers,
            SearchType::Venues,
            SearchType::Cities,
        ]
    });
    if types.is_empty() {
        return Err(invalid(
            "types must be a non-empty list of performers, venues and cities",
        ));
    }

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
    if types.contains(&SearchType::Performers) {
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
    if types.contains(&SearchType::Venues) {
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
    if types.contains(&SearchType::Cities) {
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

#[derive(Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ProfileArgs {
    user_id: Option<String>,
    /// With or without a leading `@`.
    username: Option<String>,
}

async fn get_profile(
    state: &AppStateDyn,
    user: &FirebaseUser,
    a: ProfileArgs,
) -> Result<Value, ToolError> {
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

#[derive(Deserialize, JsonSchema, Default)]
#[serde(rename_all = "lowercase")]
enum Direction {
    Received,
    Sent,
    #[default]
    Both,
}

#[derive(Deserialize, JsonSchema, Clone, Copy)]
#[serde(rename_all = "lowercase")]
enum BookingStatus {
    Pending,
    Confirmed,
    Canceled,
}

impl BookingStatus {
    fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Confirmed => "confirmed",
            Self::Canceled => "canceled",
        }
    }
}

#[derive(Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct BookingsArgs {
    /// Default `both`.
    #[serde(default)]
    direction: Direction,
    status: Option<BookingStatus>,
    /// 1-100, default 20.
    #[schemars(range(min = 1, max = 100))]
    limit: Option<i64>,
    /// Pagination cursor: the ID of the last booking on the previous page (only with
    /// `received` or `sent`).
    after: Option<String>,
}

async fn list_my_bookings(
    state: &AppStateDyn,
    user: &FirebaseUser,
    a: BookingsArgs,
) -> Result<Value, ToolError> {
    let limit = limit(a.limit, 20, 100)?;
    let page = |received: bool| ListParams {
        requester_id: (!received).then(|| user.uid.clone()),
        requestee_id: received.then(|| user.uid.clone()),
        status: a.status.map(|s| s.as_str().to_owned()),
        limit: Some(limit),
        after: a.after.clone(),
        ..Default::default()
    };
    match a.direction {
        Direction::Received => list(state, user, "bookings", page(true)).await,
        Direction::Sent => list(state, user, "bookings", page(false)).await,
        Direction::Both => {
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
    }
}

#[derive(Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct BookingArgs {
    booking_id: String,
}

#[derive(Deserialize, JsonSchema, Default)]
#[serde(rename_all = "lowercase")]
enum OpportunityView {
    #[default]
    Feed,
    Applied,
}

#[derive(Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct OpportunitiesArgs {
    /// Default `feed`.
    #[serde(default)]
    view: OpportunityView,
    /// 1-100, default 20.
    #[schemars(range(min = 1, max = 100))]
    limit: Option<i64>,
    /// Pagination cursor: the ID of the last opportunity on the previous page.
    after: Option<String>,
}

async fn list_opportunities(
    state: &AppStateDyn,
    user: &FirebaseUser,
    a: OpportunitiesArgs,
) -> Result<Value, ToolError> {
    let view = match a.view {
        OpportunityView::Feed => "feed",
        OpportunityView::Applied => "applied",
    };
    let params = ListParams {
        user_id: Some(user.uid.clone()),
        mode: Some(view.into()),
        limit: Some(limit(a.limit, 20, 100)?),
        after: a.after.map(|after| id(&after, "after")).transpose()?,
        ..Default::default()
    };
    list(state, user, "opportunities", params).await
}

#[derive(Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SearchOpportunitiesArgs {
    #[serde(default)]
    #[schemars(length(max = 200))]
    query: String,
    #[serde(default)]
    #[schemars(length(max = 20))]
    genres: Vec<String>,
    #[schemars(range(min = -90.0, max = 90.0))]
    lat: Option<f64>,
    #[schemars(range(min = -180.0, max = 180.0))]
    lng: Option<f64>,
    #[schemars(range(min = 1, max = 500_000))]
    radius_meters: Option<u64>,
    /// Only opportunities starting after this ISO 8601 time.
    #[schemars(with = "Option<String>")]
    starting_after: Option<DateTime<Utc>>,
    /// 1-100, default 20.
    #[schemars(range(min = 1, max = 100))]
    limit: Option<i64>,
}

async fn search_opportunities(
    state: &AppStateDyn,
    user: &FirebaseUser,
    a: SearchOpportunitiesArgs,
) -> Result<Value, ToolError> {
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

#[derive(Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct OpportunityArgs {
    opportunity_id: String,
}

async fn get_opportunity(
    state: &AppStateDyn,
    user: &FirebaseUser,
    a: OpportunityArgs,
) -> Result<Value, ToolError> {
    let opportunity_id = id(&a.opportunity_id, "opportunityId")?;
    let mut doc = get_doc(state, user, "opportunities", opportunity_id.clone()).await?;
    let Json(applied) =
        app_data::interest_status(State(state.clone()), user.clone(), Path(opportunity_id)).await?;
    doc["appliedBySignedInUser"] = applied;
    Ok(doc)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn schema(tool: rmcp::model::Tool) -> Value {
        Value::Object((*tool.input_schema).clone())
    }

    #[test]
    fn tools_are_read_only_with_strict_documented_inputs() {
        let tools = [
            TappedMcp::search_tool_attr(),
            TappedMcp::get_profile_tool_attr(),
            TappedMcp::list_my_bookings_tool_attr(),
            TappedMcp::get_booking_tool_attr(),
            TappedMcp::list_opportunities_tool_attr(),
            TappedMcp::search_opportunities_tool_attr(),
            TappedMcp::get_opportunity_tool_attr(),
        ];
        for tool in &tools {
            let annotations = tool.annotations.as_ref().unwrap();
            assert_eq!(annotations.read_only_hint, Some(true), "{}", tool.name);
            assert!(tool.description.as_ref().is_some_and(|d| !d.is_empty()));
            assert_eq!(
                schema(tool.clone())["additionalProperties"],
                false,
                "{}",
                tool.name
            );
        }

        let search = schema(TappedMcp::search_tool_attr()).to_string();
        for value in [
            "performers",
            "venues",
            "cities",
            "radiusMeters",
            "minCapacity",
        ] {
            assert!(
                search.contains(value),
                "search schema lacks {value}: {search}"
            );
        }
        let bookings = schema(TappedMcp::list_my_bookings_tool_attr()).to_string();
        for value in [
            "received",
            "sent",
            "both",
            "pending",
            "confirmed",
            "canceled",
        ] {
            assert!(bookings.contains(value), "bookings schema lacks {value}");
        }
        let required = &schema(TappedMcp::get_booking_tool_attr())["required"];
        assert_eq!(required, &json!(["bookingId"]));
    }
}
