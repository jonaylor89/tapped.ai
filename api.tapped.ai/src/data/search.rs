use crate::domain::models::user::UserModel;
use algoliasearch::{index::AroundRadius, Client, SearchQueryBuilder};
use anyhow::Result;
use axum::async_trait;
use std::collections::HashSet;
use tracing::instrument;

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

#[derive(Debug, Clone, Default)]
pub struct Algolia {}

#[async_trait]
impl Search for Algolia {
    #[instrument]
    async fn search_users(
        &self,
        query: String,
        options: UserSearchOptions,
    ) -> Result<Vec<UserModel>> {
        let index = Client::default().init_index::<UserModel>("prod_users");

        tracing::info!("searching users from Algolia: {}", query);

        let _occupations_intersection = if let (Some(occupations), Some(black_list)) =
            (&options.occupations, &options.occupations_black_list)
        {
            let occ_set: HashSet<_> = occupations.iter().collect();
            let black_set: HashSet<_> = black_list.iter().collect();
            let intersection: Vec<_> = occ_set.intersection(&black_set).cloned().collect();
            if !intersection.is_empty() {
                eprintln!("occupations and occupations_black_list have intersection");
                return Ok(vec![]);
            }
            Some(intersection)
        } else {
            None
        };

        let formatted_is_deleted_filter = "deleted:false".to_string();
        let formatted_label_filter = options.labels.map(|labels| {
            format!(
                "({})",
                labels
                    .into_iter()
                    .map(|e| format!("performerInfo.label:'{}'", e))
                    .collect::<Vec<_>>()
                    .join(" OR ")
            )
        });
        let formatted_genre_filter = options.genres.map(|genres| {
            format!(
                "({})",
                genres
                    .into_iter()
                    .map(|e| format!("performerInfo.genres:'{}'", e))
                    .collect::<Vec<_>>()
                    .join(" OR ")
            )
        });
        let formatted_occupation_filter = options.occupations.map(|occupations| {
            format!(
                "({})",
                occupations
                    .into_iter()
                    .map(|e| format!("occupations:'{}'", e))
                    .collect::<Vec<_>>()
                    .join(" OR ")
            )
        });
        let formatted_occupation_black_list_filter =
            options.occupations_black_list.map(|black_list| {
                format!(
                    "({})",
                    black_list
                        .into_iter()
                        .map(|e| format!("NOT occupations:'{}'", e))
                        .collect::<Vec<_>>()
                        .join(" AND ")
                )
            });
        let formatted_venue_genre_filter = options.venue_genres.map(|venue_genres| {
            format!(
                "({})",
                venue_genres
                    .into_iter()
                    .map(|e| format!("venueInfo.genres:'{}'", e))
                    .collect::<Vec<_>>()
                    .join(" OR ")
            )
        });
        let formatted_unclaimed_filter = options
            .unclaimed
            .map(|unclaimed| format!("unclaimed:{}", unclaimed));

        let filters = vec![
            Some(formatted_is_deleted_filter),
            formatted_label_filter,
            formatted_genre_filter,
            formatted_occupation_filter,
            formatted_occupation_black_list_filter,
            formatted_venue_genre_filter,
            formatted_unclaimed_filter,
        ]
        .into_iter()
        .flatten()
        .collect::<Vec<_>>()
        .join(" AND ");

        let formatted_location_filter = if let (Some(lat), Some(lng)) = (options.lat, options.lng) {
            Some(format!("{}, {}", lat, lng))
        } else {
            None
        };

        let mut numeric_filters = Vec::new();
        if let Some(min_capacity) = options.min_capacity {
            numeric_filters.push(format!("venueInfo.capacity>={}", min_capacity));
        }
        if let Some(max_capacity) = options.max_capacity {
            numeric_filters.push(format!("venueInfo.capacity<={}", max_capacity));
        }

        let numeric_filters = if numeric_filters.is_empty() {
            None
        } else {
            Some(numeric_filters)
        };

        let query = SearchQueryBuilder::default()
            .query(query)
            .filters(filters)
            .hits_per_page(options.hits_per_page.unwrap_or(10))
            .around_radius(AroundRadius::Radius(options.radius.unwrap_or(50_000)))
            .around_lat_lng(formatted_location_filter)
            .numeric_filters(numeric_filters)
            .build()?;

        let response = index
            .search(query)
            .await
            .expect("failed to search users from Algolia");

        Ok(response.hits)
    }
}
