import FirebaseAuth
import Foundation
import TappedDomain

/// All application records go through Rust. Firebase is used only to obtain an identity token.
public struct TappedAPIDataClient: Sendable {
    public typealias IDTokenProvider = @Sendable () async throws -> String?
    let baseURL: URL
    let session: URLSession
    let idToken: IDTokenProvider

    public init(baseURL: URL, session: URLSession = .shared,
                idToken: @escaping IDTokenProvider = { try await Auth.auth().currentUser?.getIDToken() }) {
        self.baseURL = baseURL
        self.session = session
        self.idToken = idToken
    }

    func request(_ path: [String], query: [String: String] = [:], method: String = "GET",
                 body: Data? = nil, authenticated: Bool = true) async throws -> Data? {
        var url = baseURL.appending(path: "app/v1")
        for component in path { url.appendPathComponent(component) }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        if authenticated {
            guard let token = try await idToken(), !token.isEmpty else { throw TappedAPIError.notSignedIn }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw TappedAPIError.invalidResponse }
        if response.statusCode == 404 && method == "GET" { return nil }
        guard (200..<300).contains(response.statusCode) else {
            throw TappedAPIError.requestFailed(statusCode: response.statusCode)
        }
        return data
    }

    func read<T: Decodable>(_ path: [String], query: [String: String] = [:],
                            authenticated: Bool = true) async throws -> T? {
        guard let data = try await request(path, query: query, authenticated: authenticated) else { return nil }
        return try TappedCoding.jsonDecoder().decode(T.self, from: data)
    }

    func send<T: Encodable>(_ path: [String], method: String, value: T) async throws {
        let encoder = JSONEncoder()
        // Fractional seconds are accepted by Rust and decoded by TappedCoding.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.ISO8601Format(.init(includingFractionalSeconds: true)))
        }
        _ = try await request(path, method: method, body: encoder.encode(value))
    }

    public func registerDeviceToken(_ token: String, platform: String) async throws {
        try await send(["device-token"], method: "POST", value: ["token": token, "platform": platform])
    }
}

enum APIFeatureUnavailable: LocalizedError {
    case disabled(String)
    var errorDescription: String? {
        switch self { case let .disabled(feature): "\(feature) is unavailable during the API cutover" }
    }
}

/// Cancellation owns the polling Task; no detached refresh survives stream termination.
func apiPolling<Value: Sendable>(
    interval: Duration = .seconds(30),
    fetch: @escaping @Sendable () async throws -> Value
) -> AsyncThrowingStream<Value, any Error> {
    AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
        let task = Task {
            do {
                while !Task.isCancelled {
                    let value = try await fetch()
                    try Task.checkCancellation()
                    continuation.yield(value)
                    try await Task.sleep(for: interval)
                }
                continuation.finish()
            } catch is CancellationError { continuation.finish() }
              catch { continuation.finish(throwing: error) }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
