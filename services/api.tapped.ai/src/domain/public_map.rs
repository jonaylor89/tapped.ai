//! A viewport and its referenced public profiles in one bounded, indexed Postgres statement.
use axum::{
    Json,
    extract::{Query, State},
    http::{HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;

use crate::{domain::public_docs::public_user, errors::AppError, state::AppStateDyn};
use utoipa::{IntoParams, ToSchema};

pub const MAX_MAP_VENUES: usize = 250;
pub const MAX_MAP_PERFORMERS: usize = 1000;

#[derive(Debug, Deserialize, IntoParams)]
#[into_params(parameter_in = Query)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MapParams {
    pub sw_lat: f64,
    pub sw_lng: f64,
    pub ne_lat: f64,
    pub ne_lng: f64,
}
impl MapParams {
    pub fn validate(&self) -> Result<(), AppError> {
        if ![self.sw_lat, self.ne_lat]
            .iter()
            .all(|v| v.is_finite() && (-90.0..=90.0).contains(v))
            || ![self.sw_lng, self.ne_lng]
                .iter()
                .all(|v| v.is_finite() && (-180.0..=180.0).contains(v))
            || self.sw_lat >= self.ne_lat
            || self.sw_lng == self.ne_lng
        {
            return Err(AppError::bad_request(
                "valid nonempty viewport bounds required",
            ));
        }
        Ok(())
    }
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct MapBundle {
    pub venues: Vec<Value>,
    pub performers: Vec<Value>,
    pub genres: BTreeMap<String, usize>,
    /// A capped result cannot safely answer smaller viewports by client-side filtering.
    pub venues_truncated: bool,
    pub performers_truncated: bool,
}

// MATERIALIZED limits projection/JSON expansion to the selected venues. Bounds use the matching
// expression GiST index, including two envelopes for a viewport crossing the date line.
// The ID join is set-based: no N+1 lookups, and no unbounded profile enumeration.
const MAP_SQL: &str = r#"
WITH candidates AS MATERIALIZED (
    SELECT id, updated_at FROM users
    WHERE NOT deleted AND NOT shadow_banned AND location IS NOT NULL
      AND EXISTS (SELECT 1 FROM unnest(occupations) o WHERE lower(o)='venue')
      AND (($2::float8 <= $4::float8 AND location::geometry && ST_MakeEnvelope($2,$1,$4,$3,4326))
        OR ($2::float8 > $4::float8 AND
          (location::geometry && ST_MakeEnvelope($2,$1,180,$3,4326)
           OR location::geometry && ST_MakeEnvelope(-180,$1,$4,$3,4326))))
    ORDER BY updated_at DESC,id LIMIT 251
), selected AS MATERIALIZED (
    SELECT v.doc FROM candidates c JOIN api_users v USING(id)
    ORDER BY c.updated_at DESC,c.id LIMIT 250
), refs AS MATERIALIZED (
    SELECT DISTINCT r.id FROM selected s
    CROSS JOIN LATERAL jsonb_array_elements_text(
      CASE WHEN jsonb_typeof(s.doc#>'{venueInfo,topPerformerIds}')='array'
        THEN s.doc#>'{venueInfo,topPerformerIds}' ELSE '[]'::jsonb END
    ) WITH ORDINALITY r(id,ordinal)
    WHERE r.ordinal<=20 AND length(r.id) BETWEEN 1 AND 128
    ORDER BY r.id LIMIT 1001
), performer_docs AS (
    SELECT v.doc FROM (SELECT id FROM refs ORDER BY id LIMIT 1000) r
    JOIN users u USING(id) JOIN api_users v USING(id)
    WHERE NOT u.deleted AND NOT u.shadow_banned
    ORDER BY u.id
)
SELECT jsonb_build_object(
  'venues',coalesce((SELECT jsonb_agg(doc) FROM selected),'[]'::jsonb),
  'performers',coalesce((SELECT jsonb_agg(doc) FROM performer_docs),'[]'::jsonb),
  'venuesTruncated',(SELECT count(*)>250 FROM candidates),
  'performersTruncated',(SELECT count(*)>1000 FROM refs) OR EXISTS (
    SELECT 1 FROM selected WHERE jsonb_array_length(
      CASE WHEN jsonb_typeof(doc#>'{venueInfo,topPerformerIds}')='array'
        THEN doc#>'{venueInfo,topPerformerIds}' ELSE '[]'::jsonb END)>20
  )
)
"#;

pub async fn load_map(pool: &sqlx::PgPool, p: &MapParams) -> Result<MapBundle, AppError> {
    p.validate()?;
    let raw: Value = sqlx::query_scalar(MAP_SQL)
        .bind(p.sw_lat)
        .bind(p.sw_lng)
        .bind(p.ne_lat)
        .bind(p.ne_lng)
        .fetch_one(pool)
        .await
        .map_err(|e| AppError::internal("public map query", e))?;
    let project = |key: &str| {
        raw[key]
            .as_array()
            .into_iter()
            .flatten()
            .cloned()
            .filter_map(public_user)
            .collect::<Vec<_>>()
    };
    let venues = project("venues");
    let performers = project("performers");
    let mut genres = BTreeMap::new();
    for venue in &venues {
        for genre in venue["venueInfo"]["genres"]
            .as_array()
            .into_iter()
            .flatten()
            .take(64)
            .filter_map(Value::as_str)
        {
            *genres.entry(genre.to_owned()).or_insert(0) += 1;
        }
    }
    Ok(MapBundle {
        venues,
        performers,
        genres,
        venues_truncated: raw["venuesTruncated"].as_bool().unwrap_or(false),
        performers_truncated: raw["performersTruncated"].as_bool().unwrap_or(false),
    })
}

#[utoipa::path(
    get,
    path = "/public/map",
    tag = "public",
    summary = "Map venues, referenced public performers and genre summary in one query",
    params(MapParams),
    responses((status = 200, description = "Success", body = MapBundle))
)]
pub async fn get_map(State(state): State<AppStateDyn>, Query(p): Query<MapParams>) -> Response {
    let result =
        match p.validate() {
            Err(error) => Err(error),
            Ok(()) => match state.postgres.as_ref() {
                Some(pool) => load_map(pool, &p).await.map(Json),
                None => Err(AppError::new("database unavailable")
                    .with_status(StatusCode::SERVICE_UNAVAILABLE)),
            },
        };
    let mut response = result.into_response();
    // SWR belongs to the bounded client cache. Refreshes must see deletions, not an edge snapshot.
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    response
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn validates_bounds_without_rejecting_wrapped_viewports() {
        assert!(
            MapParams {
                sw_lat: -10.0,
                ne_lat: 10.0,
                sw_lng: 170.0,
                ne_lng: -170.0
            }
            .validate()
            .is_ok()
        );
        assert!(
            MapParams {
                sw_lat: -90.0,
                ne_lat: 90.0,
                sw_lng: -180.0,
                ne_lng: 180.0
            }
            .validate()
            .is_ok()
        );
        for p in [
            MapParams {
                sw_lat: 20.0,
                ne_lat: 10.0,
                sw_lng: 0.0,
                ne_lng: 1.0,
            },
            MapParams {
                sw_lat: 0.0,
                ne_lat: 91.0,
                sw_lng: 0.0,
                ne_lng: 1.0,
            },
            MapParams {
                sw_lat: 0.0,
                ne_lat: 10.0,
                sw_lng: f64::NAN,
                ne_lng: 1.0,
            },
            MapParams {
                sw_lat: 0.0,
                ne_lat: 10.0,
                sw_lng: 1.0,
                ne_lng: 1.0,
            },
        ] {
            assert!(p.validate().is_err());
        }
    }
}
