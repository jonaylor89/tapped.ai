import Foundation
import Testing
@testable import TappedData

@Suite("Tapped API search index repository")
struct TappedAPISearchIndexRepositoryTests {
    private let baseURL = URL(string: "https://api.example.com/base/")!

    @Test func syncRequestUsesBearerAuthenticationWithoutUserId() async throws {
        let repository = TappedAPISearchIndexRepository(baseURL: baseURL, idToken: { "firebase-token" })
        let request = try await repository.makeRequest()

        #expect(request.url == URL(string: "https://api.example.com/base/app/v1/search/users/sync"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer firebase-token")
        #expect(request.httpBody == nil)
    }

    @Test func syncRejectsMissingFirebaseToken() async {
        let repository = TappedAPISearchIndexRepository(baseURL: baseURL, idToken: { nil })
        await #expect(throws: TappedAPIError.notSignedIn) { _ = try await repository.makeRequest() }
    }
}
