import Foundation
@preconcurrency import FirebaseRemoteConfig

/// `lib/data/prod/remote_config_impl.dart`
public struct FirebaseRemoteConfigRepository: RemoteConfigRepository {
    static let downForMaintenanceKey = "down_for_maintenance"
    static let bookingFeeKey = "booking_fee"
    static let minimumAppVersionKey = "ios_minimum_app_version"
    static let latestAppVersionKey = "ios_latest_app_version"
    static let premiumWaitlistKey = "premium_waitlist_enabled"

    public init() {}

    private var remoteConfig: RemoteConfig { RemoteConfig.remoteConfig() }

    public func fetchAndActivate() async throws -> Bool {
        remoteConfig.setDefaults([
            Self.downForMaintenanceKey: false as NSNumber,
            Self.bookingFeeKey: 0.0 as NSNumber,
            Self.minimumAppVersionKey: "" as NSString,
            Self.latestAppVersionKey: "" as NSString,
            Self.premiumWaitlistKey: false as NSNumber,
        ])
        return try await remoteConfig.fetchAndActivate() != .error
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
