//! Search reads the authoritative Postgres rows, including newly created/updated records.
//! No client search key, Firestore trigger, or secondary-index freshness is required.
use anyhow::{Result, ensure};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::{PgPool, Postgres, QueryBuilder};

use super::search::{Search, UserSearchOptions};
use crate::domain::models::user::UserModel;

#[derive(Debug, Default, Deserialize, Serialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", default, deny_unknown_fields)]
pub struct SearchParams {
    pub q: String,
    pub hits_per_page: Option<u32>,
    pub labels: Vec<String>,
    pub genres: Vec<String>,
    pub occupations: Vec<String>,
    pub occupations_blacklist: Vec<String>,
    pub venue_genres: Vec<String>,
    pub unclaimed: Option<bool>,
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub radius: Option<u64>,
    pub sw_lat: Option<f64>,
    pub sw_lng: Option<f64>,
    pub ne_lat: Option<f64>,
    pub ne_lng: Option<f64>,
    pub min_capacity: Option<u32>,
    pub max_capacity: Option<u32>,
    #[schemars(with = "Option<String>")]
    pub start_time: Option<DateTime<Utc>>,
}
impl SearchParams {
    pub fn validate(&self) -> Result<()> {
        ensure!(self.q.len() <= 200, "query too long");
        ensure!(
            self.hits_per_page.unwrap_or(20) <= 1000,
            "limit exceeds 1000"
        );
        ensure!(
            self.radius.unwrap_or(50_000) <= 20_000_000,
            "radius too large"
        );
        for values in [
            &self.labels,
            &self.genres,
            &self.occupations,
            &self.occupations_blacklist,
            &self.venue_genres,
        ] {
            ensure!(
                values.len() <= 64 && values.iter().all(|s| s.len() <= 120),
                "invalid search filter"
            );
        }
        for lat in [self.lat, self.sw_lat, self.ne_lat].into_iter().flatten() {
            ensure!(
                lat.is_finite() && (-90.0..=90.0).contains(&lat),
                "invalid latitude"
            );
        }
        for lng in [self.lng, self.sw_lng, self.ne_lng].into_iter().flatten() {
            ensure!(
                lng.is_finite() && (-180.0..=180.0).contains(&lng),
                "invalid longitude"
            );
        }
        ensure!(
            self.lat.is_some() == self.lng.is_some(),
            "coordinates must be paired"
        );
        let bounds = [self.sw_lat, self.sw_lng, self.ne_lat, self.ne_lng];
        ensure!(
            bounds.iter().all(Option::is_none) || bounds.iter().all(Option::is_some),
            "bounds must be complete"
        );
        if let (Some(sw), Some(ne)) = (self.sw_lat, self.ne_lat) {
            ensure!(sw <= ne, "invalid bounds");
        }
        if let (Some(min), Some(max)) = (self.min_capacity, self.max_capacity) {
            ensure!(min <= max, "invalid capacity range");
        }
        Ok(())
    }
}

pub async fn documents(
    pool: &PgPool,
    table: &str,
    p: &SearchParams,
    uid: Option<&str>,
) -> Result<Vec<Value>> {
    p.validate()?;
    let expression = match table {
        "users" => {
            "lower(t.artist_name || ' ' || t.username || ' ' || t.bio || ' ' || coalesce(t.profile#>>'{performerInfo,label}','') || ' ' || coalesce(t.profile#>>'{venueInfo,type}',''))"
        }
        // Private booking notes must never influence public search results.
        "bookings" => "lower(t.name)",
        "opportunities" => "lower(t.title || ' ' || t.description)",
        _ => anyhow::bail!("unsupported search collection"),
    };
    let mut q: QueryBuilder<Postgres> = QueryBuilder::new(format!(
        "SELECT v.doc FROM {table} t JOIN api_{table} v USING(id) WHERE "
    ));
    match table {
        "users" => {
            q.push("NOT t.deleted AND NOT t.shadow_banned");
        }
        "opportunities" => {
            q.push("NOT t.deleted");
        }
        _ => {
            q.push("(t.status='confirmed'");
            if let Some(uid) = uid {
                q.push(" OR t.requester_id=")
                    .push_bind(uid)
                    .push(" OR t.requestee_id=")
                    .push_bind(uid);
            }
            q.push(")");
        }
    }
    let text = p.q.trim().to_lowercase();
    let has_text = !text.is_empty() && text != "*";
    if has_text {
        let pattern = format!(
            "%{}%",
            text.replace('\\', "\\\\")
                .replace('%', "\\%")
                .replace('_', "\\_")
        );
        q.push(" AND (")
            .push(expression)
            .push(" LIKE ")
            .push_bind(pattern);
        if text.chars().count() >= 3 {
            q.push(" OR ")
                .push_bind(text.clone())
                .push(" <% ")
                .push(expression);
        }
        q.push(")");
    }
    if let (Some(lat), Some(lng)) = (p.lat, p.lng) {
        q.push(" AND ST_DWithin(t.location,ST_SetSRID(ST_MakePoint(")
            .push_bind(lng)
            .push(",")
            .push_bind(lat)
            .push("),4326)::geography,")
            .push_bind(p.radius.unwrap_or(50_000) as f64)
            .push(")");
    }
    if let (Some(slat), Some(slng), Some(nlat), Some(nlng)) =
        (p.sw_lat, p.sw_lng, p.ne_lat, p.ne_lng)
    {
        q.push(" AND ST_Y(t.location::geometry) BETWEEN ")
            .push_bind(slat)
            .push(" AND ")
            .push_bind(nlat);
        if slng <= nlng {
            q.push(" AND ST_X(t.location::geometry) BETWEEN ")
                .push_bind(slng)
                .push(" AND ")
                .push_bind(nlng);
        } else {
            q.push(" AND (ST_X(t.location::geometry)>=")
                .push_bind(slng)
                .push(" OR ST_X(t.location::geometry)<=")
                .push_bind(nlng)
                .push(")");
        }
    }
    if table == "users" {
        if !p.occupations.is_empty() {
            q.push(" AND ARRAY(SELECT lower(o) FROM unnest(t.occupations) o) && ")
                .push_bind(
                    p.occupations
                        .iter()
                        .map(|s| s.to_lowercase())
                        .collect::<Vec<_>>(),
                );
        }
        if !p.occupations_blacklist.is_empty() {
            q.push(" AND NOT (ARRAY(SELECT lower(o) FROM unnest(t.occupations) o) && ")
                .push_bind(
                    p.occupations_blacklist
                        .iter()
                        .map(|s| s.to_lowercase())
                        .collect::<Vec<_>>(),
                )
                .push(")");
        }
        if !p.labels.is_empty() {
            q.push(" AND t.profile#>>'{performerInfo,label}'=ANY(")
                .push_bind(&p.labels)
                .push(")");
        }
        for (path, values) in [
            ("{performerInfo,genres}", &p.genres),
            ("{venueInfo,genres}", &p.venue_genres),
        ] {
            if !values.is_empty() {
                q.push(format!(" AND ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(t.profile#>'{path}')='array' THEN t.profile#>'{path}' ELSE '[]'::jsonb END)) && ")).push_bind(values);
            }
        }
        if let Some(unclaimed) = p.unclaimed {
            q.push(" AND t.unclaimed=").push_bind(unclaimed);
        }
        let capacity = "(CASE WHEN t.profile#>>'{venueInfo,capacity}' ~ '^[0-9]+(\\.[0-9]+)?$' THEN (t.profile#>>'{venueInfo,capacity}')::numeric END)";
        if let Some(min) = p.min_capacity {
            q.push(" AND ")
                .push(capacity)
                .push(">=")
                .push_bind(i64::from(min));
        }
        if let Some(max) = p.max_capacity {
            q.push(" AND ")
                .push(capacity)
                .push("<=")
                .push_bind(i64::from(max));
        }
    }
    if table == "opportunities"
        && let Some(time) = p.start_time
    {
        q.push(" AND t.start_time>").push_bind(time);
    }
    if let (Some(lat), Some(lng)) = (p.lat, p.lng) {
        q.push(" ORDER BY t.location <-> ST_SetSRID(ST_MakePoint(")
            .push_bind(lng)
            .push(",")
            .push_bind(lat)
            .push("),4326)::geography,t.id");
    } else if has_text {
        q.push(" ORDER BY word_similarity(")
            .push_bind(text)
            .push(",")
            .push(expression)
            .push(") DESC,t.id");
    } else {
        q.push(" ORDER BY t.updated_at DESC,t.id");
    }
    q.push(" LIMIT ")
        .push_bind(i64::from(p.hits_per_page.unwrap_or(20)));
    Ok(q.build_query_scalar().fetch_all(pool).await?)
}

#[derive(Clone)]
pub struct PostgresSearch {
    pool: PgPool,
}
impl PostgresSearch {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}
#[axum::async_trait]
impl Search for PostgresSearch {
    async fn ping(&self) -> Result<()> {
        sqlx::query("SELECT id FROM api_users LIMIT 1")
            .execute(&self.pool)
            .await?;
        Ok(())
    }
    async fn search_users(&self, query: String, o: UserSearchOptions) -> Result<Vec<UserModel>> {
        let p = SearchParams {
            q: query,
            hits_per_page: o
                .hits_per_page
                .map(|v| u32::try_from(v).unwrap_or(u32::MAX)),
            labels: o.labels.unwrap_or_default(),
            genres: o.genres.unwrap_or_default(),
            occupations: o.occupations.unwrap_or_default(),
            occupations_blacklist: o.occupations_black_list.unwrap_or_default(),
            venue_genres: o.venue_genres.unwrap_or_default(),
            unclaimed: o.unclaimed,
            lat: o.lat,
            lng: o.lng,
            radius: o.radius,
            min_capacity: o.min_capacity,
            max_capacity: o.max_capacity,
            ..Default::default()
        };
        documents(&self.pool, "users", &p, None)
            .await?
            .into_iter()
            .map(|doc| {
                serde_json::from_value(doc.clone())
                    .map_err(|e| anyhow::anyhow!("user projection {}: {e}", doc["id"]))
            })
            .collect()
    }
}
