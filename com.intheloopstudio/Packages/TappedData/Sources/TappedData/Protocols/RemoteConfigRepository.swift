import Foundation

/// `lib/data/remote_config_repository.dart`
public protocol RemoteConfigRepository: Sendable {
    /// Activates the config fetched on a previous launch (or the defaults) without touching the network.
    @discardableResult
    func activateCached() async -> Bool
    /// Network fetch, bounded by a short timeout; launch runs it in the background after `activateCached()`.
    @discardableResult
    func fetchAndActivate() async throws -> Bool
    func getDownForMaintenanceStatus() async -> Bool
    func getBookingFee() async -> Double
    /// Hard gate that replaces Flutter `upgrader`: builds below this version must update. Empty = no gate.
    func getMinimumAppVersion() async -> String
    /// Soft prompt: builds below this version see a dismissible "update available" alert. Empty = no prompt.
    func getLatestAppVersion() async -> String
    /// When true, `Route.paywall` shows the premium waitlist instead of the StoreKit paywall.
    func getPremiumWaitlistEnabled() async -> Bool
}
