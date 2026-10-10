use crate::domain::models::user::UserModel;
use anyhow::Result;
use axum::async_trait;

#[derive(Debug, Clone, Default)]
pub struct MockSearch;

#[async_trait]
impl Search for MockSearch {
    async fn search_users(
        &self,
        _query: String,
        _options: UserSearchOptions,
    ) -> Result<Vec<UserModel>> {
        Ok(vec![])
    }
}

#[derive(Debug, Default, Builder)]
pub struct UserSearchOptions {
    #[builder(default)]
    pub(crate) hits_per_page: Option<u64>,
    #[builder(default)]
    pub(crate) labels: Option<Vec<String>>,
    #[builder(default)]
    pub(crate) genres: Option<Vec<String>>,
    #[builder(default)]
    pub(crate) occupations: Option<Vec<String>>,
    #[builder(default)]
    pub(crate) occupations_black_list: Option<Vec<String>>,
    #[builder(default)]
    pub(crate) venue_genres: Option<Vec<String>>,
    #[builder(default)]
    pub(crate) unclaimed: Option<bool>,
    #[builder(default)]
    pub(crate) lat: Option<f64>,
    #[builder(default)]
    pub(crate) lng: Option<f64>,
    #[builder(default)]
    pub(crate) radius: Option<u64>,
    #[builder(default)]
    pub(crate) min_capacity: Option<u32>,
    #[builder(default)]
    pub(crate) max_capacity: Option<u32>,
}

#[async_trait]
pub trait Search: Send + Sync {
    async fn search_users(
        &self,
        query: String,
        options: UserSearchOptions,
    ) -> Result<Vec<UserModel>>;
    async fn ping(&self) -> Result<()> {
        Ok(())
    }
}
