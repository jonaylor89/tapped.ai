use anyhow::{Result, bail};
use axum::async_trait;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use tracing::instrument;

const PLACES_BASE_URL: &str = "https://places.googleapis.com/v1";
const GEOCODE_URL: &str = "https://maps.googleapis.com/maps/api/geocode/json";
const PLACE_DETAILS_FIELD_MASK: &str =
    "id,displayName,shortFormattedAddress,location,addressComponents,photos";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct AutocompletePrediction {
    pub place_id: String,
    pub full_text: String,
    pub primary_text: String,
    pub secondary_text: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct AddressComponent {
    pub long_text: Option<String>,
    pub short_text: Option<String>,
    #[serde(default)]
    pub types: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct PhotoMetadata {
    pub name: String,
    pub width_px: Option<i64>,
    pub height_px: Option<i64>,
}

/// A place as stored in the Firestore `googlePlacesCache` collection.
///
/// Documents written by the legacy Cloud Functions have no `name`, `locality` or `photoNames`;
/// those are refreshed from Google once and rewritten in this shape. `addressComponents`,
/// `photoMetadata` and `geohash` are kept for the legacy readers of the collection.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct PlaceDetails {
    pub place_id: String,
    #[serde(default)]
    pub name: Option<String>,
    pub short_formatted_address: Option<String>,
    pub lat: f64,
    pub lng: f64,
    #[serde(default)]
    pub locality: Option<String>,
    #[serde(default)]
    pub photo_names: Vec<String>,
    #[serde(default)]
    pub address_components: Vec<AddressComponent>,
    #[serde(default)]
    pub photo_metadata: Option<PhotoMetadata>,
    #[serde(default)]
    pub geohash: Option<String>,
}

impl PlaceDetails {
    /// Whether this was written by the legacy Cloud Functions and is missing fields clients need.
    pub fn is_legacy(&self) -> bool {
        self.name.is_none()
    }
}

/// Google Places (New) and Geocoding. Every call is billed; callers are expected to cache.
#[async_trait]
pub trait Places: Send + Sync {
    /// `types` restricts results to these primary types (e.g. `locality`, `(cities)`).
    async fn autocomplete(
        &self,
        query: &str,
        types: &[String],
        session_token: Option<&str>,
    ) -> Result<Vec<AutocompletePrediction>>;
    async fn place_details(
        &self,
        place_id: &str,
        session_token: Option<&str>,
    ) -> Result<Option<PlaceDetails>>;
    async fn photo_uri(&self, photo_name: &str, max_height_px: u32) -> Result<Option<String>>;
    async fn place_id_by_lat_lng(&self, lat: f64, lng: f64) -> Result<Option<String>>;
}

#[derive(Debug, Clone, Default)]
pub struct MockPlaces;

#[async_trait]
impl Places for MockPlaces {
    async fn autocomplete(
        &self,
        query: &str,
        _types: &[String],
        _session_token: Option<&str>,
    ) -> Result<Vec<AutocompletePrediction>> {
        Ok(vec![AutocompletePrediction {
            place_id: "mock-place".into(),
            full_text: query.into(),
            primary_text: query.into(),
            secondary_text: String::new(),
        }])
    }

    async fn place_details(
        &self,
        place_id: &str,
        _session_token: Option<&str>,
    ) -> Result<Option<PlaceDetails>> {
        Ok(Some(PlaceDetails {
            place_id: place_id.into(),
            name: Some("Mock Place".into()),
            short_formatted_address: Some("Richmond, VA".into()),
            lat: 37.5407,
            lng: -77.436,
            locality: Some("Richmond".into()),
            photo_names: vec![],
            address_components: vec![],
            photo_metadata: None,
            geohash: None,
        }))
    }

    async fn photo_uri(&self, _photo_name: &str, _max_height_px: u32) -> Result<Option<String>> {
        Ok(None)
    }

    async fn place_id_by_lat_lng(&self, _lat: f64, _lng: f64) -> Result<Option<String>> {
        Ok(Some("mock-place".into()))
    }
}

#[derive(Clone)]
pub struct GooglePlaces {
    client: reqwest::Client,
    api_key: String,
}

impl std::fmt::Debug for GooglePlaces {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("GooglePlaces").finish_non_exhaustive()
    }
}

impl GooglePlaces {
    pub fn new(api_key: String) -> Self {
        Self {
            client: reqwest::Client::new(),
            api_key,
        }
    }

    fn ensure_configured(&self) -> Result<()> {
        if self.api_key.is_empty() {
            bail!("GOOGLE_PLACES_API_KEY is not configured");
        }
        Ok(())
    }
}

#[async_trait]
impl Places for GooglePlaces {
    #[instrument]
    async fn autocomplete(
        &self,
        query: &str,
        types: &[String],
        session_token: Option<&str>,
    ) -> Result<Vec<AutocompletePrediction>> {
        self.ensure_configured()?;
        let mut body = serde_json::json!({ "input": query });
        if !types.is_empty() {
            body["includedPrimaryTypes"] = types.into();
        }
        if let Some(session_token) = session_token {
            body["sessionToken"] = session_token.into();
        }
        let response: AutocompleteResponse = self
            .client
            .post(format!("{PLACES_BASE_URL}/places:autocomplete"))
            .header("X-Goog-Api-Key", &self.api_key)
            .json(&body)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;

        Ok(response
            .suggestions
            .unwrap_or_default()
            .into_iter()
            .filter_map(|suggestion| suggestion.place_prediction)
            .map(|prediction| {
                let structured = prediction.structured_format.unwrap_or_default();
                AutocompletePrediction {
                    place_id: prediction.place_id,
                    full_text: text(prediction.text),
                    primary_text: text(structured.main_text),
                    secondary_text: text(structured.secondary_text),
                }
            })
            .collect())
    }

    #[instrument]
    async fn place_details(
        &self,
        place_id: &str,
        session_token: Option<&str>,
    ) -> Result<Option<PlaceDetails>> {
        self.ensure_configured()?;
        let mut request = self
            .client
            .get(format!("{PLACES_BASE_URL}/places/{place_id}"))
            .query(&[("languageCode", "en")])
            .header("X-Goog-Api-Key", &self.api_key)
            .header("X-Goog-FieldMask", PLACE_DETAILS_FIELD_MASK);
        if let Some(session_token) = session_token {
            request = request.query(&[("sessionToken", session_token)]);
        }
        let response = request.send().await?;
        if matches!(
            response.status(),
            reqwest::StatusCode::NOT_FOUND | reqwest::StatusCode::BAD_REQUEST
        ) {
            return Ok(None);
        }
        let place: PlaceResponse = response.error_for_status()?.json().await?;
        let Some(location) = place.location else {
            return Ok(None);
        };

        let address_components = place.address_components.unwrap_or_default();
        let photos = place.photos.unwrap_or_default();
        Ok(Some(PlaceDetails {
            place_id: place.id,
            name: Some(text(place.display_name)),
            short_formatted_address: place.short_formatted_address,
            lat: location.latitude,
            lng: location.longitude,
            locality: locality(&address_components),
            photo_names: photos.iter().map(|photo| photo.name.clone()).collect(),
            photo_metadata: photos.into_iter().next(),
            address_components,
            geohash: None,
        }))
    }

    #[instrument]
    async fn photo_uri(&self, photo_name: &str, max_height_px: u32) -> Result<Option<String>> {
        self.ensure_configured()?;
        let response: PhotoMediaResponse = self
            .client
            .get(format!("{PLACES_BASE_URL}/{photo_name}/media"))
            .query(&[
                ("maxHeightPx", max_height_px.to_string()),
                ("skipHttpRedirect", "true".into()),
            ])
            .header("X-Goog-Api-Key", &self.api_key)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        Ok(response.photo_uri)
    }

    #[instrument]
    async fn place_id_by_lat_lng(&self, lat: f64, lng: f64) -> Result<Option<String>> {
        self.ensure_configured()?;
        let response: GeocodeResponse = self
            .client
            .get(GEOCODE_URL)
            .query(&[
                ("latlng", format!("{lat},{lng}")),
                ("result_type", "locality".into()),
                ("key", self.api_key.clone()),
            ])
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        if let Some(error) = response.error_message {
            bail!("geocoding failed: {error}");
        }
        Ok(response
            .results
            .into_iter()
            .next()
            .map(|result| result.place_id))
    }
}

pub fn locality(address_components: &[AddressComponent]) -> Option<String> {
    address_components
        .iter()
        .find(|component| component.types.iter().any(|t| t == "locality"))
        .and_then(|component| component.short_text.clone())
}

fn text(value: Option<LocalizedText>) -> String {
    value.and_then(|value| value.text).unwrap_or_default()
}

#[derive(Debug, Default, Deserialize)]
struct LocalizedText {
    text: Option<String>,
}

#[derive(Debug, Deserialize)]
struct AutocompleteResponse {
    suggestions: Option<Vec<Suggestion>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Suggestion {
    place_prediction: Option<Prediction>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Prediction {
    place_id: String,
    text: Option<LocalizedText>,
    structured_format: Option<StructuredFormat>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StructuredFormat {
    main_text: Option<LocalizedText>,
    secondary_text: Option<LocalizedText>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PlaceResponse {
    id: String,
    display_name: Option<LocalizedText>,
    short_formatted_address: Option<String>,
    location: Option<LatLng>,
    address_components: Option<Vec<AddressComponent>>,
    photos: Option<Vec<PhotoMetadata>>,
}

#[derive(Debug, Deserialize)]
struct LatLng {
    latitude: f64,
    longitude: f64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PhotoMediaResponse {
    photo_uri: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GeocodeResponse {
    #[serde(default)]
    results: Vec<GeocodeResult>,
    error_message: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GeocodeResult {
    place_id: String,
}
