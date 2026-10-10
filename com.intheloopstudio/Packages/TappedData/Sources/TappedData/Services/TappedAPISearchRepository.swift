import Foundation
import TappedDomain

/// Search is an API read from current Postgres records; no secondary-index/client key is required.
public struct TappedAPISearchRepository: SearchRepository {
    let client: TappedAPIDataClient

    public init(config: TappedConfig, session: URLSession = .shared, idToken: TappedAPIDataClient.IDTokenProvider? = nil) {
        if let idToken { client = TappedAPIDataClient(baseURL: config.tappedAPIURL, session: session, idToken: idToken) }
        else { client = TappedAPIDataClient(baseURL: config.tappedAPIURL, session: session) }
    }

    struct Parameters: Encodable {
        var q: String
        var hitsPerPage: Int?
        var labels: [String]?
        var genres: [String]?
        var occupations: [String]?
        var occupationsBlacklist: [String]?
        var venueGenres: [String]?
        var unclaimed: Bool?
        var lat: Double?
        var lng: Double?
        var radius: Int?
        var swLat: Double?
        var swLng: Double?
        var neLat: Double?
        var neLng: Double?
        var minCapacity: Int?
        var maxCapacity: Int?
        var startTime: String?
    }

    static func userParameters(_ input: String, filters: UserSearchFilters, limit: Int) -> Parameters {
        var p = Parameters(q: input, hitsPerPage: limit)
        p.labels = filters.labels
        p.genres = filters.genres
        p.occupations = filters.occupations
        p.venueGenres = filters.venueGenres
        p.unclaimed = filters.unclaimed
        p.minCapacity = filters.minCapacity
        p.maxCapacity = filters.maxCapacity
        return p
    }

    func search<T: Decodable>(_ collection: String, _ parameters: Parameters) async throws -> [T] {
        let privateSearch = collection == "bookings"
        let path = privateSearch ? ["search", collection] : ["public", "search", collection]
        guard let data = try await client.request(path, method: "POST",
                                                  body: JSONEncoder().encode(parameters), authenticated: privateSearch) else { return [] }
        return try TappedCoding.jsonDecoder().decode([T].self, from: data)
    }

    func bounded(_ p: Parameters, _ bounds: GeoBounds) -> Parameters {
        var p = p
        p.swLat = bounds.swLatitude; p.swLng = bounds.swLongitude
        p.neLat = bounds.neLatitude; p.neLng = bounds.neLongitude
        return p
    }

    public func queryUsers(_ input: String, filters: UserSearchFilters, lat: Double?, lng: Double?, radius: Int, limit: Int) async throws -> [UserModel] {
        var p = Self.userParameters(input, filters: filters, limit: limit)
        p.lat = lat; p.lng = lng; p.radius = radius
        return try await search("users", p)
    }

    public func queryUsersInBoundingBox(_ input: String, bounds: GeoBounds, filters: UserSearchFilters, limit: Int) async throws -> [UserModel] {
        try await search("users", bounded(Self.userParameters(input, filters: filters, limit: limit), bounds))
    }

    public func queryBookings(_ input: String, lat: Double?, lng: Double?, radius: Int) async throws -> [Booking] {
        var p = Parameters(q: input)
        p.lat = lat; p.lng = lng; p.radius = radius
        return try await search("bookings", p)
    }

    public func queryBookingsInBoundingBox(_ input: String, bounds: GeoBounds, limit: Int) async throws -> [Booking] {
        try await search("bookings", bounded(Parameters(q: input, hitsPerPage: limit), bounds))
    }

    public func queryOpportunities(_ input: String, lat: Double?, lng: Double?, radius: Int, startTime: Date?) async throws -> [Opportunity] {
        var p = Parameters(q: input)
        p.lat = lat; p.lng = lng; p.radius = radius
        p.startTime = startTime?.ISO8601Format(.init(includingFractionalSeconds: true))
        return try await search("opportunities", p)
    }

    public func queryOpportunitiesInBoundingBox(_ input: String, bounds: GeoBounds, limit: Int, startTime: Date?) async throws -> [Opportunity] {
        var p = Parameters(q: input, hitsPerPage: limit)
        p.startTime = startTime?.ISO8601Format(.init(includingFractionalSeconds: true))
        return try await search("opportunities", bounded(p, bounds))
    }
}
