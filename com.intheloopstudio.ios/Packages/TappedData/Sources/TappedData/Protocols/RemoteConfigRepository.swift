import Foundation

/// `lib/data/remote_config_repository.dart`
public protocol RemoteConfigRepository: Sendable {
    @discardableResult
    func fetchAndActivate() async throws -> Bool
    func getDownForMaintenanceStatus() async -> Bool
    func getBookingFee() async -> Double
}
