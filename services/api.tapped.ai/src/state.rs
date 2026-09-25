use crate::{
    data::{database::Database, search::Search},
    domain::mail_bridge::MailBridge,
};
use std::sync::Arc;

#[derive(Clone)]
pub struct AppStateDyn {
    pub database: Arc<dyn Database>,
    pub search: Arc<dyn Search>,
    pub firebase_project_id: String,
    pub mail: MailBridge,
}
