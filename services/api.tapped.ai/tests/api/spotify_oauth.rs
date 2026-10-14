use super::{
    external_effects::{cleanup, database},
    helpers::{mock_state, spawn_app_with_state},
};
use async_trait::async_trait;
use axum::{Json, extract::State};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::sync::{
    Arc,
    atomic::{AtomicBool, AtomicUsize, Ordering},
};
use tapped_api_rs::{
    data::spotify::{OAuthToken, Spotify},
    domain::{
        firebase_auth::FirebaseUser,
        spotify_oauth::{self, Exchange},
    },
};

#[derive(Default)]
struct OAuthProvider {
    calls: AtomicUsize,
    fail: AtomicBool,
}
#[async_trait]
impl Spotify for OAuthProvider {
    async fn artist(&self, _: &str) -> anyhow::Result<Option<Value>> {
        Ok(None)
    }
    async fn top_tracks(&self, _: &str, _: Option<&str>) -> anyhow::Result<Option<Value>> {
        Ok(None)
    }
    fn authorize_url(&self, state: &str, challenge: &str) -> anyhow::Result<String> {
        assert_eq!(challenge.len(), 43);
        Ok(format!(
            "https://accounts.spotify.com/authorize?state={state}&code_challenge={challenge}"
        ))
    }
    async fn exchange(
        &self,
        code: &str,
        verifier: &str,
        redirect: &str,
    ) -> anyhow::Result<OAuthToken> {
        assert_eq!(code, "test-code");
        assert_eq!(verifier.len(), 64);
        assert_eq!(redirect, self.oauth_redirect_uri());
        self.calls.fetch_add(1, Ordering::SeqCst);
        if self.fail.load(Ordering::SeqCst) {
            anyhow::bail!("private upstream details");
        }
        Ok(OAuthToken {
            access_token: "private-access".into(),
            refresh_token: Some("private-refresh".into()),
            expires_in: 3600,
            token_type: "Bearer".into(),
            scope: "user-read-email".into(),
        })
    }
    async fn refresh(&self, refresh: &str) -> anyhow::Result<OAuthToken> {
        assert_eq!(refresh, "private-refresh");
        Ok(OAuthToken {
            access_token: "private-refreshed".into(),
            refresh_token: None,
            expires_in: 3600,
            token_type: "Bearer".into(),
            scope: "user-read-email".into(),
        })
    }
}
fn user(uid: &str) -> FirebaseUser {
    FirebaseUser {
        uid: uid.into(),
        email: None,
    }
}

#[tokio::test]
async fn oauth_uses_pkce_uid_bound_single_use_state_and_owned_refresh_tokens() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    let provider = Arc::new(OAuthProvider::default());
    let mut state = mock_state();
    state.postgres = Some(pool.clone());
    state.spotify = provider.clone();
    let Json(start) = spotify_oauth::authorize(State(state.clone()), user("alice"))
        .await
        .unwrap();
    let nonce = start["state"].as_str().unwrap().to_string();
    let key = hex::encode(Sha256::digest(nonce.as_bytes()));
    let verifier: String =
        sqlx::query_scalar("SELECT verifier FROM spotify_oauth_states WHERE state_hash=$1")
            .bind(&key)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(verifier.len(), 64);
    assert_eq!(
        spotify_oauth::exchange(
            State(state.clone()),
            user("bob"),
            Json(Exchange {
                state: nonce.clone(),
                code: "test-code".into()
            })
        )
        .await
        .unwrap_err()
        .status,
        400
    );
    assert_eq!(provider.calls.load(Ordering::SeqCst), 0);
    let (a, b) = tokio::join!(
        spotify_oauth::exchange(
            State(state.clone()),
            user("alice"),
            Json(Exchange {
                state: nonce.clone(),
                code: "test-code".into()
            })
        ),
        spotify_oauth::exchange(
            State(state.clone()),
            user("alice"),
            Json(Exchange {
                state: nonce,
                code: "test-code".into()
            })
        )
    );
    assert_eq!(usize::from(a.is_ok()) + usize::from(b.is_ok()), 1);
    assert_eq!(provider.calls.load(Ordering::SeqCst), 1);
    assert_eq!(
        spotify_oauth::refresh(State(state.clone()), user("bob"))
            .await
            .unwrap_err()
            .status,
        404
    );
    let Json(refreshed) = spotify_oauth::refresh(State(state.clone()), user("alice"))
        .await
        .unwrap();
    assert_eq!(refreshed["refreshToken"], "private-refresh");
    let stored: String =
        sqlx::query_scalar("SELECT access_token FROM spotify_oauth_tokens WHERE user_id='alice'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(stored, "private-refreshed");
    // These private tables cannot be served by the generic collection API.
    assert!(
        tapped_api_rs::domain::app_data::get_private(
            State(state),
            user("alice"),
            axum::extract::Path(tapped_api_rs::domain::app_data::DocumentPath {
                table: "spotify_oauth_tokens".into(),
                id: "alice".into()
            }),
            axum::extract::Query(Default::default()),
        )
        .await
        .is_err()
    );
    cleanup(pool, admin, name).await;
}

#[tokio::test]
async fn oauth_callback_never_exposes_tokens_and_failure_does_not_consume_state() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    let provider = Arc::new(OAuthProvider::default());
    let mut state = mock_state();
    state.postgres = Some(pool.clone());
    state.spotify = provider.clone();
    let app = spawn_app_with_state(state.clone()).await;
    let Json(start) = spotify_oauth::authorize(State(state.clone()), user("alice"))
        .await
        .unwrap();
    let nonce = start["state"].as_str().unwrap();
    let url = format!(
        "{}/webhooks/spotify/callback?state={nonce}&code=test-code",
        app.address
    );
    provider.fail.store(true, Ordering::SeqCst);
    let response = app.api_client.get(&url).send().await.unwrap();
    assert_eq!(response.status(), 502);
    assert!(!response.text().await.unwrap().contains("private"));
    provider.fail.store(false, Ordering::SeqCst);
    let response = app.api_client.get(&url).send().await.unwrap();
    assert_eq!(response.status(), 200);
    let body = response.text().await.unwrap();
    assert!(body.contains("Spotify connected"));
    assert!(!body.contains("private"));
    assert_eq!(app.api_client.get(&url).send().await.unwrap().status(), 400);
    let Json(start) = spotify_oauth::authorize(State(state.clone()), user("expired"))
        .await
        .unwrap();
    sqlx::query("UPDATE spotify_oauth_states SET expires_at=now()-interval '1 second' WHERE user_id='expired'").execute(&pool).await.unwrap();
    assert_eq!(
        spotify_oauth::exchange(
            State(state),
            user("expired"),
            Json(Exchange {
                state: start["state"].as_str().unwrap().into(),
                code: "test-code".into()
            })
        )
        .await
        .unwrap_err()
        .status,
        400
    );
    cleanup(pool, admin, name).await;
}
