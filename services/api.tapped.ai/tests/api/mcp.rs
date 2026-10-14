//! The MCP OAuth flow and tools end to end over HTTP, against real Postgres (skipped without
//! `DATABASE_URL`). Firebase sign-in uses Auth Emulator tokens on a `demo-*` project.
use axum::{
    Json,
    extract::{Path, State},
};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::{
    PgPool,
    postgres::{PgConnectOptions, PgPoolOptions},
};
use std::str::FromStr;
use tapped_api_rs::{
    data::{pg_database::PostgresDatabase, postgres::MIGRATOR},
    domain::{app_data, firebase_auth::FirebaseUser},
};

use super::helpers::{TestApp, mock_state, spawn_app_with_state};

const PROJECT: &str = "demo-mcp";
const REDIRECT: &str = "https://claude.ai/api/mcp/auth_callback";
const RESOURCE: &str = "https://api.tapped.ai/mcp";
const VERIFIER: &str = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";

async fn database() -> Option<(PgPool, PgPool, String)> {
    let url = std::env::var("DATABASE_URL").ok()?;
    let options = PgConnectOptions::from_str(&url).unwrap();
    let admin = PgPoolOptions::new()
        .max_connections(1)
        .connect_with(options.clone())
        .await
        .unwrap();
    let name = format!("mcp_{}", uuid::Uuid::new_v4().simple());
    sqlx::query(sqlx::AssertSqlSafe(format!("CREATE DATABASE {name}")))
        .execute(&admin)
        .await
        .unwrap();
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect_with(options.database(&name))
        .await
        .unwrap();
    MIGRATOR.run(&pool).await.unwrap();
    Some((pool, admin, name))
}

fn emulator_token(uid: &str) -> String {
    let claims = json!({
        "sub": uid,
        "aud": PROJECT,
        "iss": format!("https://securetoken.google.com/{PROJECT}"),
        "exp": jsonwebtoken::get_current_timestamp() + 600,
    });
    format!(
        "e30.{}.",
        URL_SAFE_NO_PAD.encode(serde_json::to_vec(&claims).unwrap())
    )
}

fn query(location: &str, key: &str) -> Option<String> {
    reqwest::Url::parse(location)
        .unwrap()
        .query_pairs()
        .find(|(k, _)| k == key)
        .map(|(_, v)| v.into_owned())
}

async fn authorize(app: &TestApp, client_id: &str, redirect_uri: &str) -> String {
    let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(VERIFIER.as_bytes()));
    let response = app
        .api_client
        .get(format!("{}/oauth/authorize", app.address))
        .query(&[
            ("client_id", client_id),
            ("redirect_uri", redirect_uri),
            ("response_type", "code"),
            ("code_challenge", &challenge),
            ("code_challenge_method", "S256"),
            ("state", "xyz"),
            ("resource", RESOURCE),
            ("scope", "tapped"),
        ])
        .send()
        .await
        .unwrap();
    assert!(response.status().is_redirection());
    response.headers()["location"].to_str().unwrap().to_owned()
}

async fn token(app: &TestApp, form: &[(&str, &str)]) -> (u16, Value) {
    let response = app
        .api_client
        .post(format!("{}/oauth/token", app.address))
        .form(form)
        .send()
        .await
        .unwrap();
    (response.status().as_u16(), response.json().await.unwrap())
}

async fn rpc(app: &TestApp, access: &str, body: Value) -> (u16, Value) {
    let response = app
        .api_client
        .post(format!("{}/mcp", app.address))
        .bearer_auth(access)
        .header("accept", "application/json, text/event-stream")
        .json(&body)
        .send()
        .await
        .unwrap();
    let status = response.status().as_u16();
    (status, response.json().await.unwrap_or(Value::Null))
}

async fn call(app: &TestApp, access: &str, name: &str, arguments: Value) -> (bool, Value) {
    let (status, body) = rpc(
        app,
        access,
        json!({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":name,"arguments":arguments}}),
    )
    .await;
    assert_eq!(status, 200, "{body}");
    let result = &body["result"];
    let text = result["content"][0]["text"].as_str().unwrap();
    let is_error = result["isError"] == true;
    (
        is_error,
        serde_json::from_str(text).unwrap_or_else(|_| json!(text)),
    )
}

#[tokio::test]
async fn performers_connect_with_firebase_and_read_their_account_through_mcp() {
    let Some((pool, admin, name)) = database().await else {
        eprintln!("DATABASE_URL unset; skipping MCP flow");
        return;
    };
    let mut state = mock_state();
    state.postgres = Some(pool.clone());
    state.database = std::sync::Arc::new(PostgresDatabase::new(pool.clone()));
    state.firebase_project_id = PROJECT.into();
    state.firebase_auth_emulator = true;

    let performer = FirebaseUser {
        uid: "performer-1".into(),
        email: None,
    };
    let promoter = FirebaseUser {
        uid: "promoter-1".into(),
        email: None,
    };
    for (user, occupations) in [
        (&performer, json!(["Musician"])),
        (&promoter, json!(["Booker"])),
    ] {
        let _ = app_data::create(
            State(state.clone()),
            user.clone(),
            Path("users".into()),
            Json(json!({"id":user.uid,"username":user.uid,"artistName":user.uid,"occupations":occupations})),
        )
        .await
        .unwrap();
    }
    let _ = app_data::create(State(state.clone()),promoter.clone(),Path("bookings".into()),Json(json!({
        "id":"booking-1","requesterId":promoter.uid,"requesteeId":performer.uid,"status":"pending",
        "startTime":"2030-01-01T20:00:00Z","endTime":"2030-01-01T23:00:00Z","timestamp":"2026-10-14T00:00:00Z",
        "rate":25000,"name":"Friday show","note":"private note"
    }))).await.unwrap();

    let app = spawn_app_with_state(state).await;
    let client = &app.api_client;

    // Discovery and the unauthenticated challenge.
    let metadata: Value = client
        .get(format!(
            "{}/.well-known/oauth-protected-resource/mcp",
            app.address
        ))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(metadata["resource"], RESOURCE);
    let server: Value = client
        .get(format!(
            "{}/.well-known/oauth-authorization-server",
            app.address
        ))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(server["code_challenge_methods_supported"], json!(["S256"]));
    let challenge = client
        .post(format!("{}/mcp", app.address))
        .json(&json!({}))
        .send()
        .await
        .unwrap();
    assert_eq!(challenge.status(), 401);
    assert!(
        challenge.headers()["www-authenticate"]
            .to_str()
            .unwrap()
            .contains("resource_metadata=\"https://api.tapped.ai/.well-known/oauth-protected-resource/mcp\"")
    );

    // Registration.
    let bad = client
        .post(format!("{}/oauth/register", app.address))
        .json(&json!({"redirect_uris":["http://evil.example/cb"]}))
        .send()
        .await
        .unwrap();
    assert_eq!(bad.status(), 400);
    let registered: Value = client
        .post(format!("{}/oauth/register", app.address))
        .json(&json!({"redirect_uris":[REDIRECT],"client_name":"Claude"}))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let client_id = registered["client_id"].as_str().unwrap();

    // Untrusted redirect URIs are never redirected to.
    let untrusted = authorize(&app, client_id, "https://evil.example/cb").await;
    assert!(untrusted.starts_with("https://app.tapped.ai/oauth/authorize?error="));

    // Consent: the page shows the client, the signed-in user approves with a Firebase token.
    let consent = authorize(&app, client_id, REDIRECT).await;
    assert!(consent.starts_with("https://app.tapped.ai/oauth/authorize?request="));
    let request = query(&consent, "request").unwrap();
    let shown: Value = client
        .get(format!(
            "{}/oauth/authorization-requests/{request}",
            app.address
        ))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(
        shown,
        json!({"clientName":"Claude","redirectHost":"claude.ai"})
    );
    let approve = |token: Option<String>| {
        let mut builder = client.post(format!(
            "{}/oauth/authorization-requests/{request}/approve",
            app.address
        ));
        if let Some(token) = token {
            builder = builder.bearer_auth(token);
        }
        builder.send()
    };
    assert_eq!(approve(None).await.unwrap().status(), 401);
    let approved: Value = approve(Some(emulator_token(&performer.uid)))
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let redirect_to = approved["redirectTo"].as_str().unwrap();
    assert!(redirect_to.starts_with(REDIRECT));
    assert_eq!(query(redirect_to, "state").as_deref(), Some("xyz"));
    assert_eq!(
        query(redirect_to, "iss").as_deref(),
        Some("https://api.tapped.ai")
    );
    let code = query(redirect_to, "code").unwrap();
    // A request is approved once.
    assert_eq!(
        approve(Some(emulator_token(&performer.uid)))
            .await
            .unwrap()
            .status(),
        404
    );

    // Code exchange: PKCE and redirect URI are checked; the code is single-use.
    let exchange = |verifier: &'static str, redirect: &'static str| {
        let code = code.clone();
        let client_id = client_id.to_owned();
        let app = &app;
        async move {
            token(
                app,
                &[
                    ("grant_type", "authorization_code"),
                    ("client_id", &client_id),
                    ("code", &code),
                    ("redirect_uri", redirect),
                    ("code_verifier", verifier),
                    ("resource", RESOURCE),
                ],
            )
            .await
        }
    };
    let (status, body) = exchange("x".repeat(43).leak(), REDIRECT).await;
    assert_eq!(
        (status, body["error"].as_str()),
        (400, Some("invalid_grant"))
    );
    let (status, _) = exchange(VERIFIER, "https://claude.ai/other").await;
    assert_eq!(status, 400);
    let (status, tokens) = exchange(VERIFIER, REDIRECT).await;
    assert_eq!(status, 200, "{tokens}");
    assert_eq!(tokens["token_type"], "Bearer");
    let (status, _) = exchange(VERIFIER, REDIRECT).await;
    assert_eq!(status, 400, "codes are single-use");
    let access = tokens["access_token"].as_str().unwrap().to_owned();

    // The protocol.
    let (_, init) = rpc(
        &app,
        &access,
        json!({"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}),
    )
    .await;
    assert_eq!(init["result"]["protocolVersion"], "2025-06-18");
    assert_eq!(init["result"]["serverInfo"]["name"], "tapped");
    let (status, _) = rpc(
        &app,
        &access,
        json!({"jsonrpc":"2.0","method":"notifications/initialized"}),
    )
    .await;
    assert_eq!(status, 202);
    let (_, list) = rpc(
        &app,
        &access,
        json!({"jsonrpc":"2.0","id":2,"method":"tools/list"}),
    )
    .await;
    let names: Vec<&str> = list["result"]["tools"]
        .as_array()
        .unwrap()
        .iter()
        .map(|tool| tool["name"].as_str().unwrap())
        .collect();
    assert_eq!(
        names,
        [
            "search",
            "get_profile",
            "list_my_bookings",
            "get_booking",
            "list_opportunities",
            "search_opportunities",
            "get_opportunity"
        ]
    );
    assert!(
        list["result"]["tools"]
            .as_array()
            .unwrap()
            .iter()
            .all(|t| t["annotations"]["readOnlyHint"] == true)
    );

    // Tools act as the signed-in performer.
    let (error, bookings) = call(
        &app,
        &access,
        "list_my_bookings",
        json!({"direction":"received"}),
    )
    .await;
    assert!(!error);
    assert_eq!(bookings[0]["id"], "booking-1");
    let (_, booking) = call(
        &app,
        &access,
        "get_booking",
        json!({"bookingId":"booking-1"}),
    )
    .await;
    assert_eq!(
        booking["note"], "private note",
        "participants see private fields"
    );
    let (_, profile) = call(
        &app,
        &access,
        "get_profile",
        json!({"username":"@promoter-1"}),
    )
    .await;
    assert_eq!(profile["id"], "promoter-1");
    let (_, found) = call(
        &app,
        &access,
        "search",
        json!({"types":["performers","venues"]}),
    )
    .await;
    let performers: Vec<&str> = found["performers"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["id"].as_str().unwrap())
        .collect();
    assert!(performers.contains(&"performer-1"));
    assert!(
        !performers.contains(&"promoter-1"),
        "promoters are not performers"
    );
    assert_eq!(found["venues"], json!([]));
    assert!(found.get("cities").is_none());
    let (_, feed) = call(&app, &access, "list_opportunities", json!({})).await;
    assert_eq!(feed, json!([]));
    let (error, message) = call(&app, &access, "get_booking", json!({"bookingId":"../x"})).await;
    assert!(error, "{message}");
    let (error, _) = call(
        &app,
        &access,
        "list_my_bookings",
        json!({"unexpected":true}),
    )
    .await;
    assert!(error);
    let (_, unknown) = rpc(
        &app,
        &access,
        json!({"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"delete_everything"}}),
    )
    .await;
    assert_eq!(unknown["error"]["code"], -32602);

    // Refresh rotates; replaying a used refresh token revokes the whole connection.
    let refresh = |refresh_token: String| {
        let client_id = client_id.to_owned();
        let app = &app;
        async move {
            token(
                app,
                &[
                    ("grant_type", "refresh_token"),
                    ("client_id", &client_id),
                    ("refresh_token", &refresh_token),
                ],
            )
            .await
        }
    };
    let first_refresh = tokens["refresh_token"].as_str().unwrap().to_owned();
    let (status, rotated) = refresh(first_refresh.clone()).await;
    assert_eq!(status, 200, "{rotated}");
    let rotated_access = rotated["access_token"].as_str().unwrap().to_owned();
    let (status, _) = rpc(
        &app,
        &rotated_access,
        json!({"jsonrpc":"2.0","id":4,"method":"ping"}),
    )
    .await;
    assert_eq!(status, 200);
    let (status, _) = refresh(first_refresh).await;
    assert_eq!(status, 400);
    let (status, _) = rpc(
        &app,
        &rotated_access,
        json!({"jsonrpc":"2.0","id":5,"method":"ping"}),
    )
    .await;
    assert_eq!(status, 401, "reuse revokes the grant");

    // Explicit revocation (RFC 7009) and denial.
    let consent = authorize(&app, client_id, REDIRECT).await;
    let request = query(&consent, "request").unwrap();
    let denied: Value = client
        .post(format!(
            "{}/oauth/authorization-requests/{request}/deny",
            app.address
        ))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let denied = denied["redirectTo"].as_str().unwrap();
    assert_eq!(query(denied, "error").as_deref(), Some("access_denied"));
    assert_eq!(query(denied, "state").as_deref(), Some("xyz"));

    let consent = authorize(&app, client_id, REDIRECT).await;
    let request = query(&consent, "request").unwrap();
    let approved: Value = client
        .post(format!(
            "{}/oauth/authorization-requests/{request}/approve",
            app.address
        ))
        .bearer_auth(emulator_token(&performer.uid))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let code = query(approved["redirectTo"].as_str().unwrap(), "code").unwrap();
    let (_, tokens) = token(
        &app,
        &[
            ("grant_type", "authorization_code"),
            ("client_id", client_id),
            ("code", &code),
            ("redirect_uri", REDIRECT),
            ("code_verifier", VERIFIER),
        ],
    )
    .await;
    let access = tokens["access_token"].as_str().unwrap();
    let revoked = client
        .post(format!("{}/oauth/revoke", app.address))
        .form(&[("token", access)])
        .send()
        .await
        .unwrap();
    assert_eq!(revoked.status(), 200);
    let (status, _) = rpc(
        &app,
        access,
        json!({"jsonrpc":"2.0","id":6,"method":"ping"}),
    )
    .await;
    assert_eq!(status, 401);

    pool.close().await;
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "DROP DATABASE {name} WITH (FORCE)"
    )))
    .execute(&admin)
    .await
    .unwrap();
}
