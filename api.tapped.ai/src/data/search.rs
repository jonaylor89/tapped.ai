use crate::domain::models::user::UserModel;
use anyhow::Result;
use axum::async_trait;
use std::collections::HashSet;
use tracing::instrument;
use typesense_codegen::apis::configuration::{ApiKey, Configuration};
use typesense_codegen::apis::documents_api;
use typesense_codegen::models::SearchParameters;

#[derive(Debug, Clone, Default)]
pub struct MockSearch;

#[async_trait]
impl Search for MockSearch {
    async fn search_users(&self, _query: String, _option: UserSearchOptions) -> Result<Vec<UserModel>> {
        Ok(vec![])
    }
}

#[derive(Debug, Default, Builder)]
pub struct UserSearchOptions {
    #[builder(default)]
    hits_per_page: Option<u64>,
    #[builder(default)]
    labels: Option<Vec<String>>,
    #[builder(default)]
    genres: Option<Vec<String>>,
    #[builder(default)]
    occupations: Option<Vec<String>>,
    #[builder(default)]
    occupations_black_list: Option<Vec<String>>,
    #[builder(default)]
    venue_genres: Option<Vec<String>>,
    #[builder(default)]
    unclaimed: Option<bool>,
    #[builder(default)]
    lat: Option<f64>,
    #[builder(default)]
    lng: Option<f64>,
    #[builder(default)]
    radius: Option<u64>,
    #[builder(default)]
    min_capacity: Option<u32>,
    #[builder(default)]
    max_capacity: Option<u32>,
}

#[async_trait]
pub trait Search: Send + Sync {
    async fn search_users(
        &self,
        query: String,
        option: UserSearchOptions,
    ) -> Result<Vec<UserModel>>;
}

#[derive(Debug, Clone)]
pub struct Typesense {
    config: Configuration,
}

impl Typesense {
    pub fn new(host: String, port: u16, protocol: String, api_key: String) -> Self {
        let base_path = format!("{}://{}:{}", protocol, host, port);
        let config = Configuration {
            base_path,
            api_key: Some(ApiKey {
                prefix: None,
                key: api_key,
            }),
            ..Default::default()
        };

        Self { config }
    }

    pub fn from_env() -> Self {
        let host = std::env::var("TYPESENSE_HOST").unwrap_or_else(|_| "localhost".to_string());
        let port = std::env::var("TYPESENSE_PORT")
            .unwrap_or_else(|_| "8108".to_string())
            .parse()
            .unwrap_or(8108);
        let protocol = std::env::var("TYPESENSE_PROTOCOL").unwrap_or_else(|_| "http".to_string());
        let api_key = std::env::var("TYPESENSE_SEARCH_API_KEY")
            .expect("TYPESENSE_SEARCH_API_KEY must be set");

        Self::new(host, port, protocol, api_key)
    }
}

#[async_trait]
impl Search for Typesense {
    #[instrument(skip(self))]
    async fn search_users(
        &self,
        query: String,
        options: UserSearchOptions,
    ) -> Result<Vec<UserModel>> {
        tracing::info!("searching users from Typesense: {}", query);

        if let (Some(occupations), Some(black_list)) =
            (&options.occupations, &options.occupations_black_list)
        {
            let occ_set: HashSet<_> = occupations.iter().collect();
            let black_set: HashSet<_> = black_list.iter().collect();
            let intersection: Vec<_> = occ_set.intersection(&black_set).cloned().collect();
            if !intersection.is_empty() {
                eprintln!("occupations and occupations_black_list have intersection");
                return Ok(vec![]);
            }
        }

        let mut filters: Vec<String> = Vec::new();

        filters.push("deleted:=false".to_string());

        if let Some(labels) = options.labels
            && !labels.is_empty() {
                let label_values = labels
                    .iter()
                    .map(|l| format!("'{}'", l))
                    .collect::<Vec<_>>()
                    .join(", ");
                filters.push(format!("performerInfo.label:=[{}]", label_values));
            }

        if let Some(genres) = options.genres
            && !genres.is_empty() {
                let genre_values = genres
                    .iter()
                    .map(|g| format!("'{}'", g))
                    .collect::<Vec<_>>()
                    .join(", ");
                filters.push(format!("performerInfo.genres:=[{}]", genre_values));
            }

        if let Some(occupations) = options.occupations
            && !occupations.is_empty() {
                let occupation_values = occupations
                    .iter()
                    .map(|o| format!("'{}'", o))
                    .collect::<Vec<_>>()
                    .join(", ");
                filters.push(format!("occupations:=[{}]", occupation_values));
            }

        if let Some(black_list) = options.occupations_black_list
            && !black_list.is_empty() {
                let black_list_values = black_list
                    .iter()
                    .map(|o| format!("'{}'", o))
                    .collect::<Vec<_>>()
                    .join(", ");
                filters.push(format!("occupations:!=[{}]", black_list_values));
            }

        if let Some(venue_genres) = options.venue_genres
            && !venue_genres.is_empty() {
                let venue_genre_values = venue_genres
                    .iter()
                    .map(|g| format!("'{}'", g))
                    .collect::<Vec<_>>()
                    .join(", ");
                filters.push(format!("venueInfo.genres:=[{}]", venue_genre_values));
            }

        if let Some(unclaimed) = options.unclaimed {
            filters.push(format!("unclaimed:={}", unclaimed));
        }

        if let Some(min_capacity) = options.min_capacity {
            filters.push(format!("venueInfo.capacity:>={}", min_capacity));
        }

        if let Some(max_capacity) = options.max_capacity {
            filters.push(format!("venueInfo.capacity:<={}", max_capacity));
        }

        if let (Some(lat), Some(lng)) = (options.lat, options.lng) {
            let radius_km = options.radius.unwrap_or(50_000) as f64 / 1000.0;
            filters.push(format!("location:({}, {}, {} km)", lat, lng, radius_km));
        }

        let filter_by = if filters.is_empty() {
            None
        } else {
            Some(filters.join(" && "))
        };

        let query_str = if query.is_empty() {
            "*".to_string()
        } else {
            query
        };

        let sort_by = if let (Some(lat), Some(lng)) = (options.lat, options.lng) {
            Some(format!("location({}, {}):asc", lat, lng))
        } else {
            Some("_text_match:desc".to_string())
        };

        let mut search_params = SearchParameters::new(
            query_str,
            "artistName,username,bio,performerInfo.label,venueInfo.type".to_string(),
        );
        search_params.filter_by = filter_by;
        search_params.sort_by = sort_by;
        search_params.per_page = Some(options.hits_per_page.unwrap_or(10) as i32);

        let response =
            documents_api::search_collection::<UserModel>(&self.config, "users", search_params)
                .await?;

        let users: Vec<UserModel> = response
            .hits
            .unwrap_or_default()
            .into_iter()
            .filter_map(|hit| hit.document)
            .collect();

        Ok(users)
    }
}
