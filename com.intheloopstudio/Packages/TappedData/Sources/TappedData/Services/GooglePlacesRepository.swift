import Foundation

/// Google Places API (New) + Geocoding API over `URLSession`. Place IDs are identical to the ones the Flutter
/// app stores in `location.placeId`.
public struct GooglePlacesRepository: PlacesRepository {
    let apiKey: String
    let session: URLSession
    private let cache: GooglePlacesCache

    public init(apiKey: String, session: URLSession = .shared) {
        self.init(apiKey: apiKey, session: session, cache: GooglePlacesCache())
    }

    init(apiKey: String, session: URLSession, cache: GooglePlacesCache) {
        self.apiKey = apiKey
        self.session = session
        self.cache = cache
    }

    public func searchPlace(_ query: String) async throws -> [AutocompletePrediction] {
        try await searchPlace(query, sessionToken: nil)
    }

    public func searchPlace(_ query: String, sessionToken: String?) async throws -> [AutocompletePrediction] {
        let query = normalizedQuery(query)
        guard !query.isEmpty else { return [] }
        if let cached = await cache.autocomplete(for: query) { return cached }

        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:autocomplete")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        var body = ["input": query]
        if let sessionToken { body["sessionToken"] = sessionToken }
        request.httpBody = try JSONEncoder().encode(body)
        let response: AutocompleteResponse = try await send(request)
        let predictions: [AutocompletePrediction] = (response.suggestions ?? []).compactMap { suggestion in
            guard let prediction = suggestion.placePrediction else { return nil }
            return AutocompletePrediction(
                placeId: prediction.placeId,
                fullText: prediction.text?.text ?? "",
                primaryText: prediction.structuredFormat?.mainText?.text ?? prediction.text?.text ?? "",
                secondaryText: prediction.structuredFormat?.secondaryText?.text ?? ""
            )
        }
        await cache.storeAutocomplete(predictions, for: query)
        return predictions
    }

    public func getPlaceById(_ placeId: String) async throws -> PlaceData? {
        try await getPlaceById(placeId, sessionToken: nil)
    }

    public func getPlaceById(_ placeId: String, sessionToken: String?) async throws -> PlaceData? {
        if let cached = await cache.place(for: placeId) { return cached }
        var components = URLComponents(string: "https://places.googleapis.com/v1/places/\(placeId)")
        if let sessionToken {
            components?.queryItems = [URLQueryItem(name: "sessionToken", value: sessionToken)]
        }
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("id,displayName,shortFormattedAddress,location,addressComponents,photos", forHTTPHeaderField: "X-Goog-FieldMask")
        let place: PlaceResponse = try await send(request)
        guard let location = place.location else {
            await cache.storePlace(nil, for: placeId)
            return nil
        }
        let result = PlaceData(
            placeId: place.id,
            name: place.displayName?.text ?? "",
            shortFormattedAddress: place.shortFormattedAddress,
            lat: location.latitude,
            lng: location.longitude,
            locality: place.addressComponents?.first { $0.types.contains("locality") }?.shortText,
            photoNames: place.photos?.map(\.name) ?? []
        )
        await cache.storePlace(result, for: placeId)
        return result
    }

    public func getPhotoUrl(photoName: String, maxHeightPx: Int) async throws -> URL? {
        let cacheKey = "\(photoName)|\(maxHeightPx)"
        if let cached = await cache.photo(for: cacheKey) { return cached }
        var components = URLComponents(string: "https://places.googleapis.com/v1/\(photoName)/media")
        components?.queryItems = [
            URLQueryItem(name: "maxHeightPx", value: String(maxHeightPx)),
            URLQueryItem(name: "skipHttpRedirect", value: "true"),
            URLQueryItem(name: "key", value: apiKey),
        ]
        guard let url = components?.url else { return nil }
        let photo: PhotoMediaResponse = try await send(URLRequest(url: url))
        let result = photo.photoUri.flatMap(URL.init(string:))
        await cache.storePhoto(result, for: cacheKey)
        return result
    }

    public func getPlaceIdByLatLng(lat: Double, lng: Double) async throws -> String? {
        let cacheKey = String(format: "%.4f,%.4f", lat, lng)
        if let cached = await cache.reverseGeocode(for: cacheKey) { return cached }
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/geocode/json")
        components?.queryItems = [
            URLQueryItem(name: "latlng", value: "\(lat),\(lng)"),
            URLQueryItem(name: "result_type", value: "locality"),
            URLQueryItem(name: "key", value: apiKey),
        ]
        guard let url = components?.url else { return nil }
        let response: GeocodeResponse = try await send(URLRequest(url: url))
        let result = response.results.first?.place_id
        await cache.storeReverseGeocode(result, for: cacheKey)
        return result
    }

    private func normalizedQuery(_ query: String) -> String {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
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
