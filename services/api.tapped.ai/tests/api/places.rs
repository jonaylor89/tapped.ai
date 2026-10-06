use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

use async_trait::async_trait;
use axum::{
    extract::{Path, Query, State},
    response::IntoResponse,
};
use tapped_api_rs::{
    data::places::{AutocompletePrediction, MockPlaces, PlaceDetails, Places},
    domain::{
        firebase_auth::FirebaseUser,
        places::{ReverseGeocodeParams, get_locality_place, get_place},
    },
    state::AppStateDyn,
};

use crate::helpers::{mock_state, spawn_app};

#[tokio::test]
async fn place_details_are_public() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(format!("{}/app/v1/places/ChIJmockPlace", app.address))
        .header("Origin", "https://tapped.ai")
        .send()
        .await
        .expect("Failed to execute request");

    assert!(response.status().is_success());
    assert_eq!(
        response
            .headers()
            .get("access-control-allow-origin")
            .and_then(|v| v.to_str().ok()),
        Some("*")
    );
    let body: serde_json::Value = response.json().await.unwrap();
    assert_eq!(body["placeId"], "ChIJmockPlace");
    assert_eq!(body["name"], "Mock Place");
}

#[tokio::test]
async fn place_details_reject_unsafe_ids() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(format!("{}/app/v1/places/bad%3Fkey%3Dx", app.address))
        .send()
        .await
        .expect("Failed to execute request");

    assert_eq!(response.status(), reqwest::StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn autocomplete_is_public() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(format!(
            "{}/app/v1/places/autocomplete?query=Richmond&types=locality",
            app.address
        ))
        .header("Origin", "https://tapped.ai")
        .send()
        .await
        .expect("Failed to execute request");

    assert!(response.status().is_success());
    assert!(
        response
            .headers()
            .contains_key("access-control-allow-origin")
    );
    let body: serde_json::Value = response.json().await.unwrap();
    assert_eq!(body[0]["placeId"], "mock-place");
    assert_eq!(body[0]["fullText"], "richmond");
}

#[tokio::test]
async fn autocomplete_rejects_invalid_types() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(format!(
            "{}/app/v1/places/autocomplete?query=richmond&types=locality%26key%3Dx",
            app.address
        ))
        .send()
        .await
        .expect("Failed to execute request");

    assert_eq!(response.status(), reqwest::StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn other_places_endpoints_require_firebase_auth() {
    let app = spawn_app().await;

    for path in [
        "places/photo?name=places/x/photos/y",
        "places/reverse-geocode?lat=37.5&lng=-77.4",
    ] {
        let response = app
            .api_client
            .get(format!("{}/app/v1/{path}", app.address))
            .send()
            .await
            .expect("Failed to execute request");

        assert_eq!(
            response.status(),
            reqwest::StatusCode::UNAUTHORIZED,
            "{path}"
        );
    }
}

#[tokio::test]
async fn locality_place_requires_firebase_auth() {
    let app = spawn_app().await;

    let response = app
        .api_client
        .get(format!(
            "{}/app/v1/places/locality?lat=37.5&lng=-77.4",
            app.address
        ))
        .send()
        .await
        .expect("Failed to execute request");

    assert_eq!(response.status(), reqwest::StatusCode::UNAUTHORIZED);
}

/// Counts Google calls; reverse geocoding resolves to `locality`.
struct CountingPlaces {
    locality: Option<&'static str>,
    reverse_geocodes: AtomicUsize,
    details: AtomicUsize,
}

impl CountingPlaces {
    fn new(locality: Option<&'static str>) -> Arc<Self> {
        Arc::new(Self {
            locality,
            reverse_geocodes: AtomicUsize::new(0),
            details: AtomicUsize::new(0),
        })
    }
}

#[async_trait]
impl Places for CountingPlaces {
    async fn autocomplete(
        &self,
        query: &str,
        types: &[String],
        session_token: Option<&str>,
    ) -> anyhow::Result<Vec<AutocompletePrediction>> {
        MockPlaces.autocomplete(query, types, session_token).await
    }

    async fn place_details(
        &self,
        place_id: &str,
        session_token: Option<&str>,
    ) -> anyhow::Result<Option<PlaceDetails>> {
        self.details.fetch_add(1, Ordering::SeqCst);
        MockPlaces.place_details(place_id, session_token).await
    }

    async fn photo_uri(
        &self,
        photo_name: &str,
        max_height_px: u32,
    ) -> anyhow::Result<Option<String>> {
        MockPlaces.photo_uri(photo_name, max_height_px).await
    }

    async fn place_id_by_lat_lng(&self, _lat: f64, _lng: f64) -> anyhow::Result<Option<String>> {
        self.reverse_geocodes.fetch_add(1, Ordering::SeqCst);
        Ok(self.locality.map(str::to_owned))
    }
}

fn state_with(places: Arc<CountingPlaces>) -> AppStateDyn {
    AppStateDyn {
        places,
        ..mock_state()
    }
}

fn user() -> FirebaseUser {
    FirebaseUser {
        uid: "artist-1".into(),
        email: None,
    }
}

async fn locality_place(state: &AppStateDyn, lat: f64, lng: f64) -> axum::response::Response {
    get_locality_place(
        State(state.clone()),
        user(),
        Query(ReverseGeocodeParams { lat, lng }),
    )
    .await
    .into_response()
}

#[tokio::test]
async fn locality_place_returns_details_for_a_coordinate_and_caches_both_lookups() {
    let places = CountingPlaces::new(Some("ChIJrichmond"));
    let state = state_with(places.clone());

    let response = locality_place(&state, 37.54071, -77.43601).await;
    assert_eq!(response.status(), reqwest::StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(body["placeId"], "ChIJrichmond");
    assert_eq!(body["name"], "Mock Place");
    assert_eq!(body["locality"], "Richmond");

    // Same ~100m cell: served from the process cache without calling Google again.
    let again = locality_place(&state, 37.54069, -77.43599).await;
    assert_eq!(again.status(), reqwest::StatusCode::OK);
    assert_eq!(places.reverse_geocodes.load(Ordering::SeqCst), 1);
    assert_eq!(places.details.load(Ordering::SeqCst), 1);

    // The old two-step endpoints share those cache entries.
    let details = get_place(
        State(state.clone()),
        Path(serde_json::from_value(serde_json::json!({ "place_id": "ChIJrichmond" })).unwrap()),
        Query(serde_json::from_value(serde_json::json!({})).unwrap()),
    )
    .await
    .into_response();
    assert_eq!(details.status(), reqwest::StatusCode::OK);
    assert_eq!(places.details.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn locality_place_is_not_found_without_a_locality() {
    let places = CountingPlaces::new(None);
    let state = state_with(places.clone());

    let response = locality_place(&state, 0.0, 0.0).await;
    assert_eq!(response.status(), reqwest::StatusCode::NOT_FOUND);
    assert_eq!(places.details.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn locality_place_rejects_out_of_range_coordinates() {
    let places = CountingPlaces::new(Some("ChIJrichmond"));
    let state = state_with(places.clone());

    let response = locality_place(&state, 91.0, 0.0).await;
    assert_eq!(response.status(), reqwest::StatusCode::BAD_REQUEST);
    assert_eq!(places.reverse_geocodes.load(Ordering::SeqCst), 0);
}
