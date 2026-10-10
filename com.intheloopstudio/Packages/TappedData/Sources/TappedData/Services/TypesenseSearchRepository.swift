import Foundation
import TappedDomain

/// Typesense over `URLSession` (`lib/data/prod/typesense_search_impl.dart`).
/// Users are decoded straight from the search document. Bookings and opportunities come back as ids only and are
/// read from the database per hit (their Typesense documents don't carry every field the cards need).
public struct TypesenseSearchRepository: SearchRepository {
    let config: TappedConfig
    let session: URLSession
    let database: any DatabaseRepository

    public init(config: TappedConfig, database: any DatabaseRepository, session: URLSession = .shared) {
        self.config = config
        self.database = database
        self.session = session
    }

    static let userQueryBy = "artistName,username,bio,performerInfo.label,venueInfo.type"

    /// The `UserModel` fields the UI reads from a hit, as nested objects or flattened `object.*` keys.
    static let userIncludeFields = [
        "id", "timestamp", "username", "email", "phoneNumber", "website", "unclaimed", "artistName", "profilePicture",
        "bio", "occupations", "placeId", "badgesCount", "deleted",
        "location", "location.*", "performerInfo", "performerInfo.*", "bookerInfo", "bookerInfo.*",
        "venueInfo", "venueInfo.*", "socialFollowing", "socialFollowing.*",
    ].joined(separator: ",")

    public func queryUsers(_ input: String, filters: UserSearchFilters, lat: Double?, lng: Double?, radius: Int, limit: Int) async throws -> [UserModel] {
        var filterBy = Self.filterClauses(filters)
        var sortBy = "_text_match:desc"
        if let lat, let lng {
            filterBy.append("location:(\(lat), \(lng), \(Double(radius) / 1000) km)")
            sortBy = "location(\(lat), \(lng)):asc"
        }
        return try await searchUsers([
            "q": input.isEmpty ? "*" : input,
            "query_by": Self.userQueryBy,
            "filter_by": filterBy.joined(separator: " && "),
            "sort_by": sortBy,
            "per_page": String(limit),
        ])
    }

    public func queryUsersInBoundingBox(_ input: String, bounds: GeoBounds, filters: UserSearchFilters, limit: Int) async throws -> [UserModel] {
        var filterBy = Self.filterClauses(filters)
        filterBy.append(Self.polygon(bounds))
        return try await searchUsers([
            "q": input.isEmpty ? "*" : input,
            "query_by": Self.userQueryBy,
            "filter_by": filterBy.joined(separator: " && "),
            "per_page": String(limit),
        ])
    }

    public func queryBookings(_ input: String, lat: Double?, lng: Double?, radius: Int) async throws -> [Booking] {
        var params = ["q": input.isEmpty ? "*" : input, "query_by": "name,note"]
        if let lat, let lng {
            params["filter_by"] = "location:(\(lat), \(lng), \(Double(radius) / 1000) km)"
            params["sort_by"] = "location(\(lat), \(lng)):asc"
        }
        let ids = try await searchIDs(collection: "bookings", params: params)
        let database = database
        return try await ids.concurrentCompactMap { try await database.getBookingById($0) }
    }

    public func queryBookingsInBoundingBox(_ input: String, bounds: GeoBounds, limit: Int) async throws -> [Booking] {
        let ids = try await searchIDs(collection: "bookings", params: [
            "q": input.isEmpty ? "*" : input,
            "query_by": "name,note",
            "filter_by": Self.polygon(bounds),
            "per_page": String(limit),
        ])
        let database = database
        return try await ids.concurrentCompactMap { try await database.getBookingById($0) }
    }

    public func queryOpportunities(_ input: String, lat: Double?, lng: Double?, radius: Int, startTime: Date?) async throws -> [Opportunity] {
        var filterBy = ["deleted:=false"]
        if let startTime { filterBy.append("startTime:>\(Int(startTime.timeIntervalSince1970 * 1000))") }
        var params = ["q": input.isEmpty ? "*" : input, "query_by": "title,description"]
        if let lat, let lng {
            filterBy.append("location:(\(lat), \(lng), \(Double(radius) / 1000) km)")
            params["sort_by"] = "location(\(lat), \(lng)):asc"
        }
        params["filter_by"] = filterBy.joined(separator: " && ")
        let ids = try await searchIDs(collection: "opportunities", params: params)
        let database = database
        return try await ids.concurrentCompactMap { try await database.getOpportunityById($0) }
    }

    public func queryOpportunitiesInBoundingBox(_ input: String, bounds: GeoBounds, limit: Int, startTime: Date?) async throws -> [Opportunity] {
        var filterBy = ["deleted:=false", Self.polygon(bounds)]
        if let startTime { filterBy.append("startTime:>\(Int(startTime.timeIntervalSince1970 * 1000))") }
        let ids = try await searchIDs(collection: "opportunities", params: [
            "q": input.isEmpty ? "*" : input,
            "query_by": "title,description",
            "filter_by": filterBy.joined(separator: " && "),
            "per_page": String(limit),
        ])
        let database = database
        return try await ids.concurrentCompactMap { try await database.getOpportunityById($0) }
    }

    // MARK: - request building

    static func filterClauses(_ filters: UserSearchFilters) -> [String] {
        func list(_ values: [String]) -> String { "[" + values.map { "'\($0)'" }.joined(separator: ", ") + "]" }
        var clauses = ["deleted:=false"]
        if let labels = filters.labels, !labels.isEmpty { clauses.append("performerInfo.label:=\(list(labels))") }
        if let genres = filters.genres, !genres.isEmpty { clauses.append("performerInfo.genres:=\(list(genres))") }
        if let occupations = filters.occupations, !occupations.isEmpty { clauses.append("occupations:=\(list(occupations))") }
        if let venueGenres = filters.venueGenres, !venueGenres.isEmpty { clauses.append("venueInfo.genres:=\(list(venueGenres))") }
        if let unclaimed = filters.unclaimed { clauses.append("unclaimed:=\(unclaimed)") }
        if let minCapacity = filters.minCapacity { clauses.append("venueInfo.capacity:>=\(minCapacity)") }
        if let maxCapacity = filters.maxCapacity { clauses.append("venueInfo.capacity:<=\(maxCapacity)") }
        return clauses
    }

    static func polygon(_ b: GeoBounds) -> String {
        "location:(\(b.swLatitude), \(b.swLongitude), \(b.swLatitude), \(b.neLongitude), \(b.neLatitude), \(b.neLongitude), \(b.neLatitude), \(b.swLongitude))"
    }

    func searchURL(collection: String, params: [String: String]) throws -> URL {
        var components = URLComponents()
        components.scheme = config.typesenseProtocol
        components.host = config.typesenseHost
        components.port = config.typesensePort
        components.path = "/collections/\(collection)/documents/search"
        components.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    private func searchUsers(_ params: [String: String]) async throws -> [UserModel] {
        let ids = try await searchIDs(collection:"users",params:params)
        let database = database
        return try await ids.concurrentCompactMap { try await database.getUserById($0) }
    }

    private func searchIDs(collection: String, params: [String: String]) async throws -> [String] {
        var params = params
        params["include_fields"] = "id"
        return try Self.decodeIDs(from: await search(collection: collection, params: params))
    }

    private func search(collection: String, params: [String: String]) async throws -> Data {
        var request = URLRequest(url: try searchURL(collection: collection, params: params))
        request.setValue(config.typesenseSearchAPIKey, forHTTPHeaderField: "X-TYPESENSE-API-KEY")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: - decoding (`_convertTypesenseDocumentToUserModel`)

    static func decodeUsers(from data: Data) throws -> [UserModel] {
        try TappedCoding.jsonDecoder().decode(TypesenseSearchResponse<TypesenseDocument<UserModel>>.self, from: data).documents.map(\.model)
    }

    static func decodeIDs(from data: Data) throws -> [String] {
        try JSONDecoder().decode(TypesenseSearchResponse<TypesenseIDDocument>.self, from: data).documents.map(\.id)
    }
}
