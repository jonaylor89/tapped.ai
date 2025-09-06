use once_cell::sync::Lazy;
use tapped_api_rs::{
    environment::Environment,
    startup::Application,
    tracing::{get_subscriber, init_subscriber},
};

static TRACING: Lazy<()> = Lazy::new(|| {
    let default_filter_level = "info".to_string();
    let subscriber_name = "test".to_string();

    if std::env::var("TEST_LOG").is_ok() {
        let subscriber = get_subscriber(subscriber_name, default_filter_level, std::io::stdout);
        init_subscriber(subscriber);
    } else {
        let subscriber = get_subscriber(subscriber_name, default_filter_level, std::io::sink);
        init_subscriber(subscriber);
    }
});

pub struct TestApp {
    pub address: String,
    pub port: u16,
    pub api_client: reqwest::Client,
}

impl TestApp {}

pub async fn spawn_app() -> TestApp {
    Lazy::force(&TRACING);

    let application = Application::build(3000, "in-the-loop-306520".into(), Environment::Stage)
        .await
        .expect("Failed to build application");

    let application_port = application.port();
    let address = format!("http://localhost:{}", application_port);

    let _ = tokio::spawn(application.run_until_stopped());

    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .unwrap();

    let test_app = TestApp {
        address,
        port: application_port,
        api_client: client,
    };

    test_app
}
