import FirebaseAuth
import Foundation

public enum TappedAPIError: LocalizedError, Sendable, Equatable {
    case notSignedIn
    case invalidResponse
    case requestFailed(statusCode: Int?)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: "sign in to make this request"
        case .invalidResponse: "the API returned an invalid response"
        case .requestFailed: "error sending the request"
        }
    }
}

/// Firebase-authenticated replacement for `notifyVenueOfInterestedOpportunities`.
public struct TappedAPIOpportunityNotificationRepository: OpportunityNotificationRepository {
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

    public func notifyVenueOfInterestedOpportunities(opportunityIds: [String], note: String) async throws {
        let request = try await makeRequest(NotificationRequest(opportunityIds: opportunityIds, note: note))
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TappedAPIError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode)
        }
    }

    func makeRequest(_ notification: NotificationRequest) async throws -> URLRequest {
        guard let token = try await idToken(), !token.isEmpty else { throw TappedAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appending(path: "app/v1/opportunity-venue-notifications"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        request.httpBody = try JSONEncoder().encode(notification)
        return request
    }
}

struct NotificationRequest: Codable, Equatable, Sendable {
    let opportunityIds: [String]
    let note: String
}
