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

/// Firebase-authenticated Stream token client. The API derives the Stream ID from the Firebase ID token.
public struct TappedAPIStreamTokenRepository: Sendable {
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

    public func fetch() async throws -> String {
        let request = try await makeRequest()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TappedAPIError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode)
        }
        guard let token = try? JSONDecoder().decode(StreamTokenResponse.self, from: data), !token.token.isEmpty else {
            throw TappedAPIError.invalidResponse
        }
        return token.token
    }

    func makeRequest() async throws -> URLRequest {
        guard let token = try await idToken(), !token.isEmpty else { throw TappedAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appending(path: "app/v1/stream-token"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        return request
    }

    private struct StreamTokenResponse: Decodable {
        let token: String
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
