import FirebaseAuth
import Foundation

/// Asks the API to re-index the signed-in user. The API derives the UID from the Firebase ID token
/// and re-reads `users/{uid}`, so the request has no body.
public struct TappedAPISearchIndexRepository: SearchIndexRepository {
    public typealias IDTokenProvider = @Sendable () async throws -> String?

    private let baseURL: URL
    private let session: URLSession
    private let idToken: IDTokenProvider

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        idToken: @escaping IDTokenProvider = { try await Auth.auth().currentUser?.getIDToken() }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.idToken = idToken
    }

    public func syncCurrentUser() async throws {
        let request = try await makeRequest()
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TappedAPIError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode)
        }
    }

    func makeRequest() async throws -> URLRequest {
        guard let token = try await idToken(), !token.isEmpty else { throw TappedAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appending(path: "app/v1/search/users/sync"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}
