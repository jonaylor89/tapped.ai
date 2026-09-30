import Foundation

/// Google Places API (New) + Geocoding API over `URLSession`. Place IDs are identical to the ones the Flutter
/// app stores in `location.placeId`.
public struct GooglePlacesRepository: PlacesRepository {
    let apiKey: String
    let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func searchPlace(_ query: String) async throws -> [AutocompletePrediction] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:autocomplete")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.httpBody = try JSONEncoder().encode(["input": query])
        let response: AutocompleteResponse = try await send(request)
        return (response.suggestions ?? []).compactMap { suggestion in
            guard let prediction = suggestion.placePrediction else { return nil }
            return AutocompletePrediction(
                placeId: prediction.placeId,
                fullText: prediction.text?.text ?? "",
                primaryText: prediction.structuredFormat?.mainText?.text ?? prediction.text?.text ?? "",
                secondaryText: prediction.structuredFormat?.secondaryText?.text ?? ""
            )
        }
    }

    public func getPlaceById(_ placeId: String) async throws -> PlaceData? {
        guard let url = URL(string: "https://places.googleapis.com/v1/places/\(placeId)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("id,displayName,shortFormattedAddress,location,addressComponents,photos", forHTTPHeaderField: "X-Goog-FieldMask")
        let place: PlaceResponse = try await send(request)
        guard let location = place.location else { return nil }
        return PlaceData(
            placeId: place.id,
            name: place.displayName?.text ?? "",
            shortFormattedAddress: place.shortFormattedAddress,
            lat: location.latitude,
            lng: location.longitude,
            locality: place.addressComponents?.first { $0.types.contains("locality") }?.shortText,
            photoNames: place.photos?.map(\.name) ?? []
        )
    }

    public func getPhotoUrl(photoName: String, maxHeightPx: Int) async throws -> URL? {
        var components = URLComponents(string: "https://places.googleapis.com/v1/\(photoName)/media")
        components?.queryItems = [
            URLQueryItem(name: "maxHeightPx", value: String(maxHeightPx)),
            URLQueryItem(name: "skipHttpRedirect", value: "true"),
            URLQueryItem(name: "key", value: apiKey),
        ]
        guard let url = components?.url else { return nil }
        let photo: PhotoMediaResponse = try await send(URLRequest(url: url))
        return photo.photoUri.flatMap(URL.init(string:))
    }

    public func getPlaceIdByLatLng(lat: Double, lng: Double) async throws -> String? {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/geocode/json")
        components?.queryItems = [
            URLQueryItem(name: "latlng", value: "\(lat),\(lng)"),
            URLQueryItem(name: "result_type", value: "locality"),
            URLQueryItem(name: "key", value: apiKey),
        ]
        guard let url = components?.url else { return nil }
        let response: GeocodeResponse = try await send(URLRequest(url: url))
        return response.results.first?.place_id
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct LocalizedText: Decodable { let text: String? }

private struct AutocompleteResponse: Decodable {
    struct Suggestion: Decodable {
        struct Prediction: Decodable {
            struct Structured: Decodable {
                let mainText: LocalizedText?
                let secondaryText: LocalizedText?
            }
            let placeId: String
            let text: LocalizedText?
            let structuredFormat: Structured?
        }
        let placePrediction: Prediction?
    }
    let suggestions: [Suggestion]?
}

private struct PlaceResponse: Decodable {
    struct LatLng: Decodable {
        let latitude: Double
        let longitude: Double
    }
    struct AddressComponent: Decodable {
        let shortText: String?
        let types: [String]
    }
    struct Photo: Decodable { let name: String }
    let id: String
    let displayName: LocalizedText?
    let shortFormattedAddress: String?
    let location: LatLng?
    let addressComponents: [AddressComponent]?
    let photos: [Photo]?
}

private struct PhotoMediaResponse: Decodable { let photoUri: String? }

private struct GeocodeResponse: Decodable {
    struct Result: Decodable { let place_id: String }
    let results: [Result]
}
