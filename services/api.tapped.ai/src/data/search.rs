use crate::domain::models::user::UserModel;
use anyhow::Result;
use axum::async_trait;
use serde_json::Value;
use std::collections::HashSet;
use tracing::instrument;
use typesense_codegen::apis::configuration::{ApiKey, Configuration};
use typesense_codegen::apis::{Error as TypesenseError, documents_api};
use typesense_codegen::models::{
    ExportDocumentsExportDocumentsParametersParameter,
    ImportDocumentsImportDocumentsParametersParameter, SearchParameters,
};

pub const USERS_COLLECTION: &str = "users";

#[derive(Debug, Clone, Default)]
pub struct MockSearch;

#[async_trait]
impl Search for MockSearch {
    async fn search_users(
        &self,
        _query: String,
        _option: UserSearchOptions,
    ) -> Result<Vec<UserModel>> {
        Ok(vec![])
    }

    async fn upsert_users(&self, _documents: Vec<Value>) -> Result<usize> {
        Ok(0)
    }

    async fn delete_user(&self, _id: &str) -> Result<()> {
        Ok(())
    }

    async fn list_user_ids(&self) -> Result<Vec<String>> {
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

    /// Cheap round trip used by `/health/ready`.
    async fn ping(&self) -> Result<()> {
        Ok(())
    }

    /// Inserts or replaces user documents (built by `domain::search_index`). Returns how many
    /// documents Typesense rejected.
    async fn upsert_users(&self, documents: Vec<Value>) -> Result<usize>;

    /// Removes a user document. Missing documents are not an error.
    async fn delete_user(&self, id: &str) -> Result<()>;

    /// Every indexed user ID.
    async fn list_user_ids(&self) -> Result<Vec<String>>;
}

#[derive(Debug, Clone)]
pub struct Typesense {
    config: Configuration,
    /// Writes use the admin key, which never leaves the server; the app only has a search key.
    admin: Option<Configuration>,
}

fn configuration(base_path: String, api_key: String) -> Configuration {
    Configuration {
        base_path,
        api_key: Some(ApiKey {
            prefix: None,
            key: api_key,
        }),
        client: crate::http::client(),
        ..Default::default()
    }
}

impl Typesense {
    pub fn new(host: String, port: u16, protocol: String, api_key: String) -> Self {
        let base_path = format!("{}://{}:{}", protocol, host, port);
        Self {
            config: configuration(base_path, api_key),
            admin: None,
        }
    }

    pub fn with_admin_key(mut self, admin_api_key: String) -> Self {
        self.admin = Some(configuration(self.config.base_path.clone(), admin_api_key));
        self
    }

    pub fn can_write(&self) -> bool {
        self.admin.is_some()
    }

    fn admin(&self) -> Result<&Configuration> {
        self.admin
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("TYPESENSE_ADMIN_API_KEY is not set"))
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

        let typesense = Self::new(host, port, protocol, api_key);
        match std::env::var("TYPESENSE_ADMIN_API_KEY") {
            Ok(admin_api_key) if !admin_api_key.is_empty() => {
                typesense.with_admin_key(admin_api_key)
            }
            _ => {
                tracing::warn!("TYPESENSE_ADMIN_API_KEY is not set; user search indexing is off");
                typesense
            }
        }
    }
}

#[async_trait]
impl Search for Typesense {
    #[instrument(skip_all, fields(dependency = "typesense", otel.kind = "client", db.system.name = "typesense"))]
    async fn ping(&self) -> Result<()> {
        let status = typesense_codegen::apis::health_api::health(&self.config)
            .await
            .map_err(|error| anyhow::anyhow!("typesense health check failed: {error}"))?;
        anyhow::ensure!(status.ok, "typesense reports it is not ready");
        Ok(())
    }

    async fn upsert_users(&self, documents: Vec<Value>) -> Result<usize> {
        if documents.is_empty() {
            return Ok(0);
        }
        let body = documents
            .iter()
            .map(Value::to_string)
            .collect::<Vec<_>>()
            .join("\n");
        let mut params = ImportDocumentsImportDocumentsParametersParameter::new();
        params.action = Some("upsert".into());
        let response =
            documents_api::import_documents(self.admin()?, USERS_COLLECTION, body, Some(params))
                .await
                .map_err(|error| anyhow::anyhow!("typesense import failed: {error}"))?;

        // One JSON result per line, in document order.
        let mut rejected = 0;
        for (document, line) in documents.iter().zip(response.lines()) {
            let result: Value = serde_json::from_str(line).unwrap_or(Value::Null);
            if result.get("success").and_then(Value::as_bool) != Some(true) {
                rejected += 1;
                let user_id = document.get("id").and_then(Value::as_str);
                let error = result.get("error").and_then(Value::as_str);
                tracing::error!(user_id, error, "typesense rejected user document");
            }
        }
        Ok(rejected)
    }

    async fn delete_user(&self, id: &str) -> Result<()> {
        match documents_api::delete_document(self.admin()?, USERS_COLLECTION, id).await {
            Ok(_) => Ok(()),
            Err(TypesenseError::ResponseError(response)) if response.status.as_u16() == 404 => {
                Ok(())
            }
            Err(error) => Err(anyhow::anyhow!("typesense delete failed: {error}")),
        }
    }

    async fn list_user_ids(&self) -> Result<Vec<String>> {
        let params = ExportDocumentsExportDocumentsParametersParameter {
            filter_by: None,
            include_fields: "id".into(),
            exclude_fields: String::new(),
        };
        let export = documents_api::export_documents(self.admin()?, USERS_COLLECTION, Some(params))
            .await
            .map_err(|error| anyhow::anyhow!("typesense export failed: {error}"))?;
        export
            .lines()
            .filter(|line| !line.is_empty())
            .map(|line| {
                let document: Value = serde_json::from_str(line)?;
                document
                    .get("id")
                    .and_then(Value::as_str)
                    .map(str::to_owned)
                    .ok_or_else(|| anyhow::anyhow!("exported document without an id"))
            })
            .collect()
    }

    #[instrument(skip(self), fields(dependency = "typesense", otel.kind = "client", db.system.name = "typesense"))]
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
            && !labels.is_empty()
        {
            let label_values = labels
                .iter()
                .map(|l| format!("'{}'", l))
                .collect::<Vec<_>>()
                .join(", ");
            filters.push(format!("performerInfo.label:=[{}]", label_values));
        }

        if let Some(genres) = options.genres
            && !genres.is_empty()
        {
            let genre_values = genres
                .iter()
                .map(|g| format!("'{}'", g))
                .collect::<Vec<_>>()
                .join(", ");
            filters.push(format!("performerInfo.genres:=[{}]", genre_values));
        }

        if let Some(occupations) = options.occupations
            && !occupations.is_empty()
        {
            let occupation_values = occupations
                .iter()
                .map(|o| format!("'{}'", o))
                .collect::<Vec<_>>()
                .join(", ");
            filters.push(format!("occupations:=[{}]", occupation_values));
        }

        if let Some(black_list) = options.occupations_black_list
            && !black_list.is_empty()
        {
            let black_list_values = black_list
                .iter()
                .map(|o| format!("'{}'", o))
                .collect::<Vec<_>>()
                .join(", ");
            filters.push(format!("occupations:!=[{}]", black_list_values));
        }

        if let Some(venue_genres) = options.venue_genres
            && !venue_genres.is_empty()
        {
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
