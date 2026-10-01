import Foundation
import Testing
@testable import TappedData

@Suite("Tapped API app-function repositories")
struct TappedAPIAppFunctionsRepositoryTests {
    private let baseURL = URL(string: "https://api.example.com/base/")!

    @Test func streamTokenRequestUsesBearerAuthentication() async throws {
        let repository = TappedAPIStreamTokenRepository(baseURL: baseURL, idToken: { "firebase-token" })
        let request = try await repository.makeRequest()

        #expect(request.url == URL(string: "https://api.example.com/base/app/v1/stream-token"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer firebase-token")
        #expect(request.httpBody == nil)
    }

    @Test func opportunityNotificationRequestSerializesOnlySupportedFields() async throws {
        let repository = TappedAPIOpportunityNotificationRepository(baseURL: baseURL, idToken: { "firebase-token" })
        let request = try await repository.makeRequest(.init(opportunityIds: ["op-1", "op-2"], note: "Available Friday"))
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]

        #expect(request.url == URL(string: "https://api.example.com/base/app/v1/opportunity-venue-notifications"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer firebase-token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(json?["opportunityIds"] as? [String] == ["op-1", "op-2"])
        #expect(json?["note"] as? String == "Available Friday")
        #expect(json?["userId"] == nil)
    }

    @Test func repositoriesRejectMissingFirebaseToken() async {
        let stream = TappedAPIStreamTokenRepository(baseURL: baseURL, idToken: { nil })
        let notifications = TappedAPIOpportunityNotificationRepository(baseURL: baseURL, idToken: { nil })

        await #expect(throws: TappedAPIError.notSignedIn) { _ = try await stream.makeRequest() }
        await #expect(throws: TappedAPIError.notSignedIn) {
            _ = try await notifications.makeRequest(.init(opportunityIds: ["op-1"], note: ""))
        }
    }
}
