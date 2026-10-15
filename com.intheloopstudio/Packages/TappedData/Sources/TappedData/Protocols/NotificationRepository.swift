import Foundation

public enum NotificationAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case denied
    /// Delivered quietly to Notification Center; the user hasn't been prompted yet.
    case provisional
    case authorized
}

/// `lib/data/notification_repository.dart` + the APNs / badge plumbing.
public protocol NotificationRepository: Sendable {
    /// Shows the system alert/badge/sound prompt (also upgrades provisional) and registers with APNs.
    /// Only call after an explicit user action. Returns whether alerts are allowed.
    @discardableResult
    func requestAuthorization() async throws -> Bool
    /// Silent provisional authorization (no prompt) + APNs registration, used at sign-in.
    @discardableResult
    func requestProvisionalAuthorization() async throws -> Bool
    func authorizationStatus() async -> NotificationAuthorizationStatus
    /// Registers the APNs device token (and its environment) with the authenticated Rust API.
    func saveDeviceToken(userId: String) async throws
    func setBadgeCount(_ count: Int) async
}
