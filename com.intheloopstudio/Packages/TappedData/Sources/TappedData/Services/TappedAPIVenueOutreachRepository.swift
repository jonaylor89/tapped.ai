import FirebaseAuth
import Foundation

/// Live `VenueOutreachRepository` backed by the Tapped API (`TappedApiClient.createVenueEmailThread`).
public struct TappedAPIVenueOutreachRepository: VenueOutreachRepository {
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

    public func createVenueEmailThread(id: String, venueId: String, subject: String, textBody: String) async throws {
        let request = try await makeRequest(VenueEmailThread(id: id, venueId: venueId, subject: subject, textBody: textBody))
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw VenueOutreachError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode)
        }
    }

    func makeRequest(_ thread: VenueEmailThread) async throws -> URLRequest {
        guard let token = try await idToken(), !token.isEmpty else { throw VenueOutreachError.notSignedIn }
        var request = URLRequest(url: baseURL.appending(path: "app/v1/venue-email-threads"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        request.httpBody = try JSONEncoder().encode(thread)
        return request
    }
}

public enum VenueOutreachError: LocalizedError, Sendable, Equatable {
    case notSignedIn
    case requestFailed(statusCode: Int?)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: "sign in to contact venues"
        case .requestFailed: "error sending the request"
        }
    }
}
