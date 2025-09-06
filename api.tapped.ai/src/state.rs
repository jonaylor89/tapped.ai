use crate::data::{database::Database, search::Search};
use std::sync::Arc;

#[derive(Clone)]
pub struct AppStateDyn {
    pub database: Arc<dyn Database>,
    pub search: Arc<dyn Search>,
}
