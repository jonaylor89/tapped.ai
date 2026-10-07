import Foundation
@preconcurrency import FirebaseRemoteConfig

/// `lib/data/prod/remote_config_impl.dart`
public struct FirebaseRemoteConfigRepository: RemoteConfigRepository {
    static let downForMaintenanceKey = "down_for_maintenance"
    static let bookingFeeKey = "booking_fee"
    static let minimumAppVersionKey = "ios_minimum_app_version"
    static let latestAppVersionKey = "ios_latest_app_version"
    static let premiumWaitlistKey = "premium_waitlist_enabled"
    /// Firebase defaults to 60 s, which held the launch splash on poor networks.
    static let fetchTimeout: TimeInterval = 3
    /// Firebase's default; repeat fetches inside this window are served from the cache.
    static let minimumFetchInterval: TimeInterval = 12 * 60 * 60

    public init() {}

    private var remoteConfig: RemoteConfig { RemoteConfig.remoteConfig() }

    public func activateCached() async -> Bool {
        (try? await configured().activate()) ?? false
    }

    public func fetchAndActivate() async throws -> Bool {
        try await configured().fetchAndActivate() != .error
    }

    private func configured() -> RemoteConfig {
        let remoteConfig = remoteConfig
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = Self.minimumFetchInterval
        settings.fetchTimeout = Self.fetchTimeout
        remoteConfig.configSettings = settings
        remoteConfig.setDefaults([
            Self.downForMaintenanceKey: false as NSNumber,
            Self.bookingFeeKey: 0.0 as NSNumber,
            Self.minimumAppVersionKey: "" as NSString,
            Self.latestAppVersionKey: "" as NSString,
            Self.premiumWaitlistKey: false as NSNumber,
        ])
        return remoteConfig
    }

    public func getDownForMaintenanceStatus() async -> Bool {
        remoteConfig.configValue(forKey: Self.downForMaintenanceKey).boolValue
    }

    public func getBookingFee() async -> Double {
        remoteConfig.configValue(forKey: Self.bookingFeeKey).numberValue.doubleValue
    }

    public func getMinimumAppVersion() async -> String {
        remoteConfig.configValue(forKey: Self.minimumAppVersionKey).stringValue
    }

    public func getLatestAppVersion() async -> String {
        remoteConfig.configValue(forKey: Self.latestAppVersionKey).stringValue
    }

    public func getPremiumWaitlistEnabled() async -> Bool {
        remoteConfig.configValue(forKey: Self.premiumWaitlistKey).boolValue
    }
}
