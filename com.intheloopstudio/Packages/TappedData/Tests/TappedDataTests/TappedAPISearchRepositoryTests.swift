import Foundation
import os
import TappedDomain
import Testing
@testable import TappedData

@Suite("API search", .serialized)
struct TappedAPISearchRepositoryTests {
    func repository() -> TappedAPISearchRepository {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [SearchAPIStub.self]
        return TappedAPISearchRepository(config: TappedConfig(tappedAPIURL: URL(string: "https://api.test")!),
                                        session: URLSession(configuration: c), idToken: { "test-identity" })
    }
    @Test func currentDocumentsNeedNoClientKeyOrPerHitFetch() async throws {
        SearchAPIStub.respond(#"[{"id":"current","username":"current","artistName":"Current","timestamp":"2026-10-11T01:02:03.456Z"}]"#)
        let users = try await repository().queryUsers("new artist", filters: .init(), lat: 40, lng: -74, radius: 50_000, limit: 100)
        #expect(users.map(\.id) == ["current"])
        let request = try #require(SearchAPIStub.request)
        #expect(request.url?.path == "/app/v1/public/search/users")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "X-TYPESENSE-API-KEY") == nil)
        let p = try #require(SearchAPIStub.parameters)
        #expect(p["q"] as? String == "new artist")
        #expect(p["radius"] as? Int == 50_000)
        #expect(p["lat"] as? Double == 40)
        #expect(p["hitsPerPage"] as? Int == 100)
    }
    @Test func venueFiltersAndBoundingBoxAreStructured() async throws {
        SearchAPIStub.respond("[]")
        let bounds = GeoBounds(swLatitude: 1, swLongitude: 2, neLatitude: 3, neLongitude: 4)
        _ = try await repository().queryUsersInBoundingBox("", bounds: bounds, filters: .venues(genres: ["rock"], capacity: 0...1000), limit: 50)
        let p = try #require(SearchAPIStub.parameters)
        #expect(p["venueGenres"] as? [String] == ["rock"])
        #expect(p["minCapacity"] as? Int == 0)
        #expect(p["maxCapacity"] as? Int == 1000)
        #expect(p["swLng"] as? Double == 2)
        #expect(p["neLat"] as? Double == 3)
    }
    @Test func opportunityTimeKeepsFractionalSeconds() async throws {
        SearchAPIStub.respond("[]")
        _ = try await repository().queryOpportunities("", lat: nil, lng: nil, radius: 1000,
                                                       startTime: Date(timeIntervalSince1970: 1_791_676_800.125))
        let p = try #require(SearchAPIStub.parameters)
        #expect((p["startTime"] as? String)?.contains(".125") == true)
        #expect(SearchAPIStub.request?.url?.path == "/app/v1/public/search/opportunities")
    }
    @Test func bookingSearchUsesIdentityForOwnedPendingRecords() async throws {
        SearchAPIStub.respond("[]")
        _ = try await repository().queryBookings("", lat: nil, lng: nil, radius: 1000)
        let request = try #require(SearchAPIStub.request)
        #expect(request.url?.path == "/app/v1/search/bookings")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-identity")
        #expect(request.value(forHTTPHeaderField: "X-TYPESENSE-API-KEY") == nil)
    }
    @Test func failuresPropagateWithoutFallback() async {
        SearchAPIStub.respond("{}", status: 503)
        await #expect(throws: TappedAPIError.self) {
            _ = try await repository().queryUsers("", filters: .init(), lat: nil, lng: nil, radius: 1000, limit: 10)
        }
    }
    @Test func emptySearchIsAnEmptyArray() async throws {
        SearchAPIStub.respond("[]")
        let users = try await repository().queryUsers("", filters: .init(), lat: nil, lng: nil, radius: 1000, limit: 10)
        #expect(users.isEmpty)
    }
}
final class SearchAPIStub: URLProtocol, @unchecked Sendable {
    struct State { var response = Data(); var status = 200; var request: URLRequest?; var body = Data() }
    private static let state = OSAllocatedUnfairLock(initialState: State())
    static func respond(_ json: String, status: Int = 200) {
        state.withLock { $0 = State(response: Data(json.utf8), status: status) }
    }
    static var request: URLRequest? { state.withLock { $0.request } }
    static var parameters: [String: Any]? { let body = state.withLock { $0.body }; return try? JSONSerialization.jsonObject(with: body) as? [String: Any] }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; body.append(buffer, count: count) }
            stream.close()
        }
        let capturedBody = body
        let result = Self.state.withLock { s in s.request = request; s.body = capturedBody; return (s.response,s.status) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: result.1, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.0)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
