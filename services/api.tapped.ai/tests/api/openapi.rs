use std::path::Path;

use tapped_api_rs::{rate_limit::RateLimits, startup::api_router};

use crate::helpers::mock_state;

/// `src/openapi.json` is generated from the routes in `startup::api_router`. Regenerate with
/// `UPDATE_OPENAPI=1 cargo test --test api openapi`.
#[test]
fn committed_openapi_spec_matches_the_routes() {
    let (_, api) = api_router(mock_state(), &RateLimits::default());
    let generated = serde_json::to_string_pretty(&*api).unwrap() + "\n";
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("src/openapi.json");

    if std::env::var_os("UPDATE_OPENAPI").is_some() {
        std::fs::write(&path, &generated).unwrap();
        return;
    }
    let committed = std::fs::read_to_string(&path).unwrap_or_default();
    if committed != generated {
        let _ = std::fs::write(
            Path::new(env!("CARGO_MANIFEST_DIR")).join("target/openapi.generated.json"),
            &generated,
        );
    }
    assert!(
        committed == generated,
        "src/openapi.json is out of date with the routes. Run `UPDATE_OPENAPI=1 cargo test --test api openapi` and commit the result."
    );
}
