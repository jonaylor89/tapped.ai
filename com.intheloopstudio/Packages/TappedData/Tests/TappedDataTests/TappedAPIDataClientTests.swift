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
        let response=Self.state.withLock { value in value.request=request; return (value.body,value.status) }
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:response.1,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:response.0)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
