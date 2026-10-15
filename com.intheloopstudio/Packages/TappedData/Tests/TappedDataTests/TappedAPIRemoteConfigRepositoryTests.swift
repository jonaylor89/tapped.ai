import Foundation
import Synchronization
import Testing
@testable import TappedData

@Suite("API app config", .serialized)
struct TappedAPIRemoteConfigRepositoryTests {
    let defaults = UserDefaults(suiteName: "TappedAPIRemoteConfigRepositoryTests.\(UUID().uuidString)")!

    func repository(host: String = "api.example.test") -> TappedAPIRemoteConfigRepository {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubAppConfigProtocol.self]
        return TappedAPIRemoteConfigRepository(baseURL: URL(string: "https://\(host)")!,
                                               session: URLSession(configuration: config), defaults: defaults)
    }

    @Test func defaultsApplyUntilAnythingIsCached() async {
        let config = repository()
        #expect(await !config.activateCached())
        #expect(await !config.getDownForMaintenanceStatus())
        #expect(await config.getMinimumAppVersion() == "")
        #expect(await !config.getPremiumWaitlistEnabled())
    }

    @Test func fetchActivatesAndCachesForTheNextLaunch() async throws {
        StubAppConfigProtocol.respond(#"{"downForMaintenance":true,"bookingFee":0.1,"iosMinimumAppVersion":"2.0.0","iosLatestAppVersion":"2.1.0","premiumWaitlistEnabled":true}"#)
        let config = repository()
        #expect(try await config.fetchAndActivate())
        let request = try #require(StubAppConfigProtocol.lastRequest)
        #expect(request.url?.path == "/app/v1/public/app-config")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil, "launch gates are read before sign-in")
        #expect(request.timeoutInterval == TappedAPIRemoteConfigRepository.fetchTimeout)
        #expect(await config.getDownForMaintenanceStatus())
        #expect(await config.getLatestAppVersion() == "2.1.0")

        let nextLaunch = repository()
        #expect(await nextLaunch.activateCached())
        #expect(await nextLaunch.getDownForMaintenanceStatus())
        #expect(await nextLaunch.getMinimumAppVersion() == "2.0.0")
        #expect(await nextLaunch.getBookingFee() == 0.1)

        let otherHost = repository(host: "localhost")
        #expect(await !otherHost.activateCached(), "a local-stack API never reads production's cached gates")
    }

    @Test func failedFetchKeepsTheActiveConfig() async throws {
        StubAppConfigProtocol.respond(#"{"downForMaintenance":true}"#)
        let config = repository()
        try await config.fetchAndActivate()
        StubAppConfigProtocol.respond("{}", status: 503)
        await #expect(throws: TappedAPIError.requestFailed(statusCode: 503)) { try await config.fetchAndActivate() }
        #expect(await config.getDownForMaintenanceStatus())
    }

    @Test func missingKeysKeepTheirDefaults() async throws {
        StubAppConfigProtocol.respond(#"{"iosMinimumAppVersion":"3.0.0","retiredGate":1}"#)
        let config = repository()
        try await config.fetchAndActivate()
        #expect(await config.getMinimumAppVersion() == "3.0.0")
        #expect(await !config.getDownForMaintenanceStatus())
    }
}

final class StubAppConfigProtocol: URLProtocol, @unchecked Sendable {
    private static let state = Mutex<(body: Data, status: Int, request: URLRequest?)>((Data(), 200, nil))
    static func respond(_ json: String, status: Int = 200) { state.withLock { $0 = (Data(json.utf8), status, nil) } }
    static var lastRequest: URLRequest? { state.withLock { $0.request } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let request = request
        let response = Self.state.withLock { value in value.request = request; return (value.body, value.status) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: response.1, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.0)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
