import Foundation
import os
import TappedDomain
import Testing
@testable import TappedData

@Suite("Typesense request building")
struct TypesenseSearchRepositoryTests {
    let repository = TypesenseSearchRepository(config: TappedConfig(typesenseSearchAPIKey: "key"), database: MockDatabaseRepository())

    @Test func venueFilterMatchesFlutterClauses() {
        let clauses = TypesenseSearchRepository.filterClauses(.venues(genres: ["rock", "pop"], capacity: 0...1000))
        #expect(clauses == [
            "deleted:=false",
            "occupations:=['Venue', 'venue']",
            "venueInfo.genres:=['rock', 'pop']",
            "venueInfo.capacity:>=0",
            "venueInfo.capacity:<=1000",
        ])
    }

    @Test func emptyGenresAreDropped() {
        #expect(!TypesenseSearchRepository.filterClauses(.venues(genres: [])).contains { $0.hasPrefix("venueInfo.genres") })
    }

    @Test func boundingBoxPolygonOrder() {
        let bounds = GeoBounds(swLatitude: 1, swLongitude: 2, neLatitude: 3, neLongitude: 4)
        #expect(TypesenseSearchRepository.polygon(bounds) == "location:(1.0, 2.0, 1.0, 4.0, 3.0, 4.0, 3.0, 2.0)")
    }

    @Test func searchURL() throws {
        let url = try repository.searchURL(collection: "users", params: ["q": "*", "per_page": "20"])
        #expect(url.absoluteString == "https://search.tapped.ai:443/collections/users/documents/search?per_page=20&q=*")
    }

    /// The shape the users collection is actually indexed with: nested models flattened to dotted keys.
    @Test func decodesFlattenedUserDocument() throws {
        let json = """
        {"hits": [{"document": {
            "id": "venue-1", "username": "thecamel", "artistName": "The Camel", "timestamp": 1719878400000,
            "occupations": ["Venue"], "deleted": false, "unclaimed": true,
            "location": [37.5, -77.4], "location.lat": 37.5, "location.lng": -77.4, "location.placeId": "abc",
            "venueInfo.capacity": 250, "venueInfo.genres": ["rock"], "venueInfo.type": "bar",
            "performerInfo.genres": ["rock"], "performerInfo.label": "None"
        }}]}
        """
        let users = try TypesenseSearchRepository.decodeUsers(from: Data(json.utf8))
        let user = try #require(users.first)
        #expect(user.id == "venue-1")
        #expect(user.artistName == "The Camel")
        #expect(user.unclaimed)
        #expect(user.location == Location(placeId: "abc", lat: 37.5, lng: -77.4))
        #expect(user.occupations == ["Venue"])
        #expect(user.venueInfo?.capacity == 250)
        #expect(user.venueInfo?.genres == ["rock"])
        #expect(user.performerInfo?.label == "None")
        #expect(user.timestamp == Date(timeIntervalSince1970: 1_719_878_400))
    }

    @Test func decodesNestedUserDocumentWithBareGeopoint() throws {
        let json = """
        {"hits": [{"document": {
            "id": "venue-1", "username": "thecamel", "timestamp": 1719878400000, "occupations": "Venue",
            "location": [37.5, -77.4], "placeId": "abc", "venueInfo": {"genres": "rock", "capacity": 250}
        }}]}
        """
        let user = try #require(try TypesenseSearchRepository.decodeUsers(from: Data(json.utf8)).first)
        #expect(user.location == Location(placeId: "abc", lat: 37.5, lng: -77.4))
        #expect(user.occupations == ["Venue"])
        #expect(user.venueInfo?.genres == ["rock"])
        #expect(user.venueInfo?.capacity == 250)
    }

    @Test func undecodableHitsAreDropped() throws {
        let json = #"{"hits": [{"document": {"username": "no-id"}}, {"document": {"id": "a"}}, {}]}"#
        #expect(try TypesenseSearchRepository.decodeUsers(from: Data(json.utf8)).map(\.id) == ["a"])
        #expect(try TypesenseSearchRepository.decodeIDs(from: Data(json.utf8)) == ["a"])
        #expect(try TypesenseSearchRepository.decodeIDs(from: Data("{}".utf8)).isEmpty)
    }

    @Test func userIncludeFieldsCoverFlattenedModels() {
        let fields = Set(TypesenseSearchRepository.userIncludeFields.split(separator: ","))
        #expect(fields.isSuperset(of: ["id", "artistName", "location", "location.*", "venueInfo", "venueInfo.*", "performerInfo.*"]))
    }
}

@Suite("Typesense search over the network", .serialized)
struct TypesenseSearchNetworkTests {
    func makeRepository(database: any DatabaseRepository = MockDatabaseRepository()) -> TypesenseSearchRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubTypesenseProtocol.self]
        return TypesenseSearchRepository(config: TappedConfig(typesenseSearchAPIKey: "key"), database: database, session: URLSession(configuration: configuration))
    }

    @Test func opportunitiesAreHydratedInHitOrderWithIdsOnly() async throws {
        StubTypesenseProtocol.respond(#"{"hits": [{"document": {"id": "op-jazz-brunch"}}, {"document": {"id": "gone"}}, {"document": {"id": "op-friday-openers"}}]}"#)
        let bounds = GeoBounds(swLatitude: 1, swLongitude: 2, neLatitude: 3, neLongitude: 4)
        let results = try await makeRepository().queryOpportunitiesInBoundingBox("", bounds: bounds)
        #expect(results.map(\.id) == ["op-jazz-brunch", "op-friday-openers"])
        let query = try #require(StubTypesenseProtocol.lastQuery)
        #expect(query["include_fields"] == "id")
        #expect(query["per_page"] == String(SearchLimits.map))
    }

    @Test func bookingsAreHydratedInHitOrder() async throws {
        StubTypesenseProtocol.respond(#"{"hits": [{"document": {"id": "booking-2"}}, {"document": {"id": "booking-1"}}]}"#)
        let results = try await makeRepository().queryBookings("", lat: nil, lng: nil, radius: 1000)
        #expect(results.map(\.id) == ["booking-2", "booking-1"])
        #expect(StubTypesenseProtocol.lastQuery?["include_fields"] == "id")
    }

    @Test func usersAreHydratedThroughTheDatabaseInsteadOfExposingSearchDocuments() async throws {
        StubTypesenseProtocol.respond(#"{"hits": [{"document": {"id": "not-in-db", "venueInfo.capacity": 80}}]}"#)
        let bounds = GeoBounds(swLatitude: 1, swLongitude: 2, neLatitude: 3, neLongitude: 4)
        let users = try await makeRepository(database: MockDatabaseRepository(users: [])).queryUsersInBoundingBox("", bounds: bounds)
        #expect(users.isEmpty) // Stale/private search documents are not served as profiles.
        let query = try #require(StubTypesenseProtocol.lastQuery)
        #expect(query["include_fields"] == "id")
        #expect(query["per_page"] == String(SearchLimits.map))
    }
}

/// Serves one canned Typesense response and records the query of the last request.
final class StubTypesenseProtocol: URLProtocol, @unchecked Sendable {
    private static let state = OSAllocatedUnfairLock<(body: Data, query: [String: String]?)>(initialState: (Data(), nil))

    static func respond(_ json: String) { state.withLock { $0 = (Data(json.utf8), nil) } }
    static var lastQuery: [String: String]? { state.withLock { $0.query } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let body = Self.state.withLock { state in
            state.query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
            return state.body
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
