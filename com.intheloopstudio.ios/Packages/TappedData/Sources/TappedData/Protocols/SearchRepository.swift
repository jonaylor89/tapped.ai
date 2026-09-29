import Foundation
import TappedDomain

/// `lib/data/search_repository.dart` (Typesense).
public protocol SearchRepository: Sendable {
    func queryUsers(_ input: String, filters: UserSearchFilters, lat: Double?, lng: Double?, radius: Int, limit: Int) async throws -> [UserModel]
    func queryUsersInBoundingBox(_ input: String, bounds: GeoBounds, filters: UserSearchFilters, limit: Int) async throws -> [UserModel]
    func queryBookings(_ input: String, lat: Double?, lng: Double?, radius: Int) async throws -> [Booking]
    func queryBookingsInBoundingBox(_ input: String, bounds: GeoBounds, limit: Int) async throws -> [Booking]
    func queryOpportunities(_ input: String, lat: Double?, lng: Double?, radius: Int, startTime: Date?) async throws -> [Opportunity]
    func queryOpportunitiesInBoundingBox(_ input: String, bounds: GeoBounds, limit: Int, startTime: Date?) async throws -> [Opportunity]
}

/// The optional named filters of Dart `queryUsers` / `queryUsersInBoundingBox`.
public struct UserSearchFilters: Sendable, Hashable {
    public var labels: [String]?
    public var genres: [String]?
    public var venueGenres: [String]?
    public var occupations: [String]?
    public var unclaimed: Bool?
    public var minCapacity: Int?
    public var maxCapacity: Int?

    public init(
        labels: [String]? = nil,
        genres: [String]? = nil,
        venueGenres: [String]? = nil,
        occupations: [String]? = nil,
        unclaimed: Bool? = nil,
        minCapacity: Int? = nil,
        maxCapacity: Int? = nil
    ) {
        self.labels = labels
        self.genres = genres
        self.venueGenres = venueGenres
        self.occupations = occupations
        self.unclaimed = unclaimed
        self.minCapacity = minCapacity
        self.maxCapacity = maxCapacity
    }

    /// Discover's venue query: `occupations:=['Venue', 'venue']`.
    public static func venues(genres: [String]? = nil, capacity: ClosedRange<Int>? = nil) -> UserSearchFilters {
        UserSearchFilters(
            venueGenres: genres?.isEmpty == false ? genres : nil,
            occupations: ["Venue", "venue"],
            minCapacity: capacity?.lowerBound,
            maxCapacity: capacity?.upperBound
        )
    }
}

public struct GeoBounds: Sendable, Hashable {
    public var swLatitude: Double
    public var swLongitude: Double
    public var neLatitude: Double
    public var neLongitude: Double

    public init(swLatitude: Double, swLongitude: Double, neLatitude: Double, neLongitude: Double) {
        self.swLatitude = swLatitude
        self.swLongitude = swLongitude
        self.neLatitude = neLatitude
        self.neLongitude = neLongitude
    }

    public func contains(lat: Double, lng: Double) -> Bool {
        (swLatitude...neLatitude).contains(lat) && (swLongitude...neLongitude).contains(lng)
    }
}

public extension SearchRepository {
    func queryUsers(_ input: String, filters: UserSearchFilters = .init(), lat: Double? = nil, lng: Double? = nil) async throws -> [UserModel] {
        try await queryUsers(input, filters: filters, lat: lat, lng: lng, radius: 50_000, limit: 20)
    }

    func queryUsersInBoundingBox(_ input: String, bounds: GeoBounds, filters: UserSearchFilters = .init()) async throws -> [UserModel] {
        try await queryUsersInBoundingBox(input, bounds: bounds, filters: filters, limit: 100)
    }

    func queryOpportunities(_ input: String, lat: Double? = nil, lng: Double? = nil, startTime: Date? = nil) async throws -> [Opportunity] {
        try await queryOpportunities(input, lat: lat, lng: lng, radius: 50_000, startTime: startTime)
    }

    func queryOpportunitiesInBoundingBox(_ input: String, bounds: GeoBounds, startTime: Date? = nil) async throws -> [Opportunity] {
        try await queryOpportunitiesInBoundingBox(input, bounds: bounds, limit: 100, startTime: startTime)
    }
}
