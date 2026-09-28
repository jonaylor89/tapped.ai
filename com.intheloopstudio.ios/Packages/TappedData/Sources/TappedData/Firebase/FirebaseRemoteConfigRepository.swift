import Foundation
@preconcurrency import FirebaseRemoteConfig

/// `lib/data/prod/remote_config_impl.dart`
public struct FirebaseRemoteConfigRepository: RemoteConfigRepository {
    static let downForMaintenanceKey = "down_for_maintenance"
    static let bookingFeeKey = "booking_fee"

    public init() {}

    private var remoteConfig: RemoteConfig { RemoteConfig.remoteConfig() }

    public func fetchAndActivate() async throws -> Bool {
        remoteConfig.setDefaults([
            Self.downForMaintenanceKey: false as NSNumber,
            Self.bookingFeeKey: 0.0 as NSNumber,
        ])
        return try await remoteConfig.fetchAndActivate() != .error
    }

    public func getDownForMaintenanceStatus() async -> Bool {
        remoteConfig.configValue(forKey: Self.downForMaintenanceKey).boolValue
    }

    public func getBookingFee() async -> Double {
        remoteConfig.configValue(forKey: Self.bookingFeeKey).numberValue.doubleValue
    }
}
