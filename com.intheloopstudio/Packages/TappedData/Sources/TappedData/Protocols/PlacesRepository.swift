import Foundation

/// `lib/data/places_repository.dart` (Google Places API, called over REST — no Google Maps SDK).
public protocol PlacesRepository: Sendable {
    func searchPlace(_ query: String) async throws -> [AutocompletePrediction]
    func getPlaceById(_ placeId: String) async throws -> PlaceData?
    /// Dart `getPhotoUrlFromReference`. `photoName` is the Places (New) resource name `places/{id}/photos/{ref}`.
    func getPhotoUrl(photoName: String, maxHeightPx: Int) async throws -> URL?
    func getPlaceIdByLatLng(lat: Double, lng: Double) async throws -> String?
    /// Groups autocomplete requests and the selected Place Details request into one billable session.
    func searchPlace(_ query: String, sessionToken: String?) async throws -> [AutocompletePrediction]
    func getPlaceById(_ placeId: String, sessionToken: String?) async throws -> PlaceData?
}

public extension PlacesRepository {
    func searchPlace(_ query: String, sessionToken: String?) async throws -> [AutocompletePrediction] {
        try await searchPlace(query)
    }

    func getPlaceById(_ placeId: String, sessionToken: String?) async throws -> PlaceData? {
        try await getPlaceById(placeId)
    }
}

public struct AutocompletePrediction: Sendable, Hashable, Identifiable {
    public var placeId: String
    public var fullText: String
    public var primaryText: String
    public var secondaryText: String

    public var id: String { placeId }

    public init(placeId: String, fullText: String, primaryText: String, secondaryText: String) {
        self.placeId = placeId
        self.fullText = fullText
        self.primaryText = primaryText
        self.secondaryText = secondaryText
    }
}

public struct PlaceData: Sendable, Hashable, Identifiable {
    public var placeId: String
    public var name: String
    public var shortFormattedAddress: String?
    public var lat: Double
    public var lng: Double
    public var locality: String?
    public var photoNames: [String]

    public var id: String { placeId }

    public init(placeId: String, name: String, shortFormattedAddress: String? = nil, lat: Double, lng: Double, locality: String? = nil, photoNames: [String] = []) {
        self.placeId = placeId
        self.name = name
        self.shortFormattedAddress = shortFormattedAddress
        self.lat = lat
        self.lng = lng
        self.locality = locality
        self.photoNames = photoNames
    }
}
