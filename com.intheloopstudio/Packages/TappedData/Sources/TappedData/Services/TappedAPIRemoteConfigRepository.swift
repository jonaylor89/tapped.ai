import Foundation
import Synchronization

/// Launch gates from `GET /app/v1/public/app-config` (Postgres `app_config`), replacing Firebase Remote Config.
/// The last response is cached per API host, so launch gates without the network and local-stack runs never
/// read config cached from production.
public final class TappedAPIRemoteConfigRepository: RemoteConfigRepository {
    struct Values: Decodable, Equatable, Sendable {
        var downForMaintenance = false
        var bookingFee = 0.0
        var iosMinimumAppVersion = ""
        var iosLatestAppVersion = ""
        var premiumWaitlistEnabled = false

        init() {}

        /// Missing keys keep their defaults, so the server can add or retire gates independently of builds.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = Values()
            downForMaintenance = try container.decodeIfPresent(Bool.self, forKey: .downForMaintenance) ?? defaults.downForMaintenance
            bookingFee = try container.decodeIfPresent(Double.self, forKey: .bookingFee) ?? defaults.bookingFee
            iosMinimumAppVersion = try container.decodeIfPresent(String.self, forKey: .iosMinimumAppVersion) ?? defaults.iosMinimumAppVersion
            iosLatestAppVersion = try container.decodeIfPresent(String.self, forKey: .iosLatestAppVersion) ?? defaults.iosLatestAppVersion
            premiumWaitlistEnabled = try container.decodeIfPresent(Bool.self, forKey: .premiumWaitlistEnabled) ?? defaults.premiumWaitlistEnabled
        }

        private enum CodingKeys: String, CodingKey {
            case downForMaintenance, bookingFee, iosMinimumAppVersion, iosLatestAppVersion, premiumWaitlistEnabled
        }
    }

    /// Bounds the launch fetch so a poor network can't hold the splash.
    static let fetchTimeout: TimeInterval = 3

    private let url: URL
    private let session: URLSession
    nonisolated(unsafe) private let defaults: UserDefaults
    let cacheKey: String
    private let active = Mutex(Values())

    public init(baseURL: URL, session: URLSession = .shared, defaults: UserDefaults = .standard) {
        url = baseURL.appending(path: "app/v1/public/app-config")
        self.session = session
        self.defaults = defaults
        cacheKey = "tapped.appConfig.\(baseURL.host() ?? "")"
    }

    public func activateCached() async -> Bool {
        guard let data = defaults.data(forKey: cacheKey),
              let values = try? JSONDecoder().decode(Values.self, from: data) else { return false }
        active.withLock { $0 = values }
        return true
    }

    public func fetchAndActivate() async throws -> Bool {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.fetchTimeout)
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw TappedAPIError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw TappedAPIError.requestFailed(statusCode: response.statusCode)
        }
        let values = try JSONDecoder().decode(Values.self, from: data)
        defaults.set(data, forKey: cacheKey)
        active.withLock { $0 = values }
        return true
    }

    private var values: Values { active.withLock { $0 } }

    public func getDownForMaintenanceStatus() async -> Bool { values.downForMaintenance }
    public func getBookingFee() async -> Double { values.bookingFee }
    public func getMinimumAppVersion() async -> String { values.iosMinimumAppVersion }
    public func getLatestAppVersion() async -> String { values.iosLatestAppVersion }
    public func getPremiumWaitlistEnabled() async -> Bool { values.premiumWaitlistEnabled }
}
