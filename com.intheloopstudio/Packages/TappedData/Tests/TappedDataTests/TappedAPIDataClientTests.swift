import Foundation
import os
import TappedDomain
import Testing
@testable import TappedData

@Suite("API-only database", .serialized)
struct TappedAPIDataClientTests {
    func client() -> TappedAPIDataClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubAPIDataProtocol.self]
        return TappedAPIDataClient(baseURL:URL(string:"https://api.example.test")!,
            session:URLSession(configuration:config),idToken:{ "identity-test" })
    }
    func repository() -> TappedAPIDatabaseRepository {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubAPIDataProtocol.self]
        return TappedAPIDatabaseRepository(baseURL: URL(string: "https://api.example.test")!,
            session: URLSession(configuration: config), idToken: { "identity-test" })
    }
    @Test func authenticatesReadsAndDecodesPostgresDates() async throws {
        StubAPIDataProtocol.respond(#"{"id":"u1","username":"nova","timestamp":"2026-10-10T20:00:00.123+00:00"}"#)
        let user: UserModel? = try await client().read(["data","users","u1"])
        #expect(user?.id == "u1")
        #expect(user?.timestamp != nil)
        let request = try #require(StubAPIDataProtocol.lastRequest)
        #expect(request.url?.path == "/app/v1/data/users/u1")
        #expect(request.value(forHTTPHeaderField:"Authorization") == "Bearer identity-test")
    }
    @Test func missingRecordsAndServerErrorsAreNotSwallowed() async throws {
        StubAPIDataProtocol.respond("{}",status:404)
        let user: UserModel? = try await client().read(["data","users","missing"])
        #expect(user == nil)
        StubAPIDataProtocol.respond("{}",status:403)
        await #expect(throws:TappedAPIError.requestFailed(statusCode:403)) {
            let _: UserModel? = try await client().read(["data","users","someone"])
        }
    }
    @Test func deviceTokensAreOnlySentToTheAuthenticatedAPI() async throws {
        StubAPIDataProtocol.respond("{}")
        try await client().registerDeviceToken("device-test",platform:"ios")
        let request = try #require(StubAPIDataProtocol.lastRequest)
        #expect(request.url?.path == "/app/v1/device-token")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField:"Authorization") == "Bearer identity-test")
    }
    @Test func missingIdentityFailsBeforeNetwork() async {
        let client = TappedAPIDataClient(baseURL:URL(string:"https://api.example.test")!,idToken:{ nil })
        await #expect(throws:TappedAPIError.notSignedIn) { _ = try await client.request(["data","users","u"]) }
    }
    @Test func profilesSendFactsAndNeverDerivedCounters() async throws {
        StubAPIDataProtocol.respond("{}")
        let user = UserModel(id: "u1", username: .empty,
            performerInfo: PerformerInfo(genres: ["Jazz"], rating: 4, reviewCount: 2, bookingCount: 9))
        try await repository().createUser(user)
        let request = try #require(StubAPIDataProtocol.lastRequest)
        #expect(request.url?.path == "/app/v1/profiles")
        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let performer = try #require(object["performerInfo"] as? [String: Any])
        #expect(performer["bookingCount"] == nil)
        #expect(performer["rating"] == nil)
        #expect(performer["reviewCount"] == nil)
        #expect(performer["genres"] as? [String] == ["Jazz"])
    }
    @Test func bookingAcceptanceUsesAnAtomicDomainCommand() async throws {
        StubAPIDataProtocol.respond(#"{"id":"b1","requesterId":"venue","requesteeId":"artist","status":"pending","startTime":"2026-12-01T20:00:00Z","endTime":"2026-12-01T22:00:00Z","timestamp":"2026-12-01T19:00:00Z"}"#)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let booking = Booking(id: "b1", requesteeId: "artist", status: .confirmed,
            startTime: start, endTime: start.addingTimeInterval(3600), timestamp: start, requesterId: "venue")
        try await repository().updateBooking(booking)
        let request = try #require(StubAPIDataProtocol.lastRequest)
        #expect(request.url?.path == "/app/v1/bookings/b1/accept")
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["status"] == nil)
    }
    @Test func pollingStopsWhenItsConsumerIsCancelled() async throws {
        actor Counter {
            var value = 0
            func next() -> Int { value += 1; return value }
        }
        let counter = Counter()
        let stream = apiPolling(interval:.seconds(10)) { await counter.next() }
        let consumer = Task { for try await _ in stream {} }
        try await Task.sleep(for:.milliseconds(60))
        consumer.cancel()
        _ = try? await consumer.value
        try await Task.sleep(for:.milliseconds(30))
        let stopped = await counter.value
        try await Task.sleep(for:.milliseconds(80))
        #expect(await counter.value == stopped)
    }
}
final class StubAPIDataProtocol: URLProtocol, @unchecked Sendable {
    private static let state = OSAllocatedUnfairLock<(body:Data,status:Int,request:URLRequest?)>(initialState:(Data(),200,nil))
    static func respond(_ json:String,status:Int=200) { state.withLock { $0=(Data(json.utf8),status,nil) } }
    static var lastRequest:URLRequest? { state.withLock { $0.request } }
    override class func canInit(with request:URLRequest) -> Bool { true }
    override class func canonicalRequest(for request:URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            var body = Data()
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                body.append(contentsOf: bytes.prefix(count))
            }
            stream.close()
            captured.httpBody = body
        }
        let normalized = captured
        let response=Self.state.withLock { value in value.request=normalized; return (value.body,value.status) }
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:response.1,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:response.0)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
