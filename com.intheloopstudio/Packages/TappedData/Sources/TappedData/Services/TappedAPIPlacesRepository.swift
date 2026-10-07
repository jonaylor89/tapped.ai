import FirebaseAuth
import Foundation

/// Live `PlacesRepository` backed by the Tapped API's `/app/v1/places` proxy.
///
/// The app holds no Google key: the API caches responses server-side and persists place details in
/// Firestore `googlePlacesCache`, so Google is only billed once per place across every client.
/// `GooglePlacesCache` additionally deduplicates requests within an app session.
public struct TappedAPIPlacesRepository: PlacesRepository {
    public typealias IDTokenProvider = @Sendable () async throws -> String?

    private let baseURL: URL
    private let session: URLSession
    private let idToken: IDTokenProvider
    private let cache: GooglePlacesCache

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        idToken: @escaping IDTokenProvider = { try await Auth.auth().currentUser?.getIDToken() }
    ) {
        self.init(baseURL: baseURL, session: session, idToken: idToken, cache: GooglePlacesCache())
    }

    init(baseURL: URL, session: URLSession, idToken: @escaping IDTokenProvider, cache: GooglePlacesCache) {
        self.baseURL = baseURL
        self.session = session
        self.idToken = idToken
        self.cache = cache
    }

    public func searchPlace(_ query: String) async throws -> [AutocompletePrediction] {
        try await searchPlace(query, sessionToken: nil)
    }

    public func searchPlace(_ query: String, sessionToken: String?) async throws -> [AutocompletePrediction] {
        let query = normalizedQuery(query)
        guard !query.isEmpty else { return [] }
        if let cached = await cache.autocomplete(for: query) { return cached }

        var queryItems = [URLQueryItem(name: "query", value: query)]
        if let sessionToken { queryItems.append(URLQueryItem(name: "sessionToken", value: sessionToken)) }
        let response: [PredictionResponse] = try await get("app/v1/places/autocomplete", queryItems: queryItems)
        let predictions = response.map {
            AutocompletePrediction(
                placeId: $0.placeId,
                fullText: $0.fullText,
                primaryText: $0.primaryText,
                secondaryText: $0.secondaryText
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

        let queryItems = sessionToken.map { [URLQueryItem(name: "sessionToken", value: $0)] } ?? []
        let place: PlaceResponse
        do {
            place = try await get("app/v1/places/\(placeId)", queryItems: queryItems)
        } catch PlacesAPIError.requestFailed(statusCode: 404) {
            await cache.storePlace(nil, for: placeId)
            return nil
        }
        let result = PlaceData(
            placeId: place.placeId,
            name: place.name ?? place.shortFormattedAddress ?? "",
            shortFormattedAddress: place.shortFormattedAddress,
            lat: place.lat,
            lng: place.lng,
            locality: place.locality,
            photoNames: place.photoNames ?? []
        )
        await cache.storePlace(result, for: placeId)
        return result
    }

    public func getPhotoUrl(photoName: String, maxHeightPx: Int) async throws -> URL? {
        let cacheKey = "\(photoName)|\(maxHeightPx)"
        if let cached = await cache.photo(for: cacheKey) { return cached }
        let photo: PhotoResponse = try await get("app/v1/places/photo", queryItems: [
            URLQueryItem(name: "name", value: photoName),
            URLQueryItem(name: "maxHeightPx", value: String(maxHeightPx)),
        ])
        let result = photo.photoUri.flatMap(URL.init(string:))
        await cache.storePhoto(result, for: cacheKey)
        return result
    }

    public func getPlaceIdByLatLng(lat: Double, lng: Double) async throws -> String? {
        let cacheKey = String(format: "%.4f,%.4f", lat, lng)
        if let cached = await cache.reverseGeocode(for: cacheKey) { return cached }
        let response: ReverseGeocodeResponse = try await get("app/v1/places/reverse-geocode", queryItems: [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
        ])
        await cache.storeReverseGeocode(response.placeId, for: cacheKey)
        return response.placeId
    }

    func makeRequest(_ path: String, queryItems: [URLQueryItem]) async throws -> URLRequest {
        guard let token = try await idToken(), !token.isEmpty else { throw PlacesAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        return request
    }

    private func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem]) async throws -> T {
        let (data, response) = try await session.data(for: makeRequest(path, queryItems: queryItems))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PlacesAPIError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func normalizedQuery(_ query: String) -> String {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }
}

public enum PlacesAPIError: LocalizedError, Sendable, Equatable {
    case notSignedIn
    case requestFailed(statusCode: Int?)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: "sign in to search places"
        case .requestFailed: "error loading places"
        }
    }
}

private struct PredictionResponse: Decodable {
    let placeId: String
    let fullText: String
    let primaryText: String
    let secondaryText: String
}

private struct PlaceResponse: Decodable {
    let placeId: String
    let name: String?
    let shortFormattedAddress: String?
    let lat: Double
    let lng: Double
    let locality: String?
    let photoNames: [String]?
}

private struct PhotoResponse: Decodable { let photoUri: String? }

private struct ReverseGeocodeResponse: Decodable { let placeId: String? }
