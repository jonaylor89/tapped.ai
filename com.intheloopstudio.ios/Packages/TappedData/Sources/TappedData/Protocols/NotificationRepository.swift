import Foundation

public enum NotificationAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case denied
    /// Delivered quietly to Notification Center; the user hasn't been prompted yet.
    case provisional
    case authorized
}

/// `lib/data/notification_repository.dart` + the APNs / badge plumbing Flutter got from `firebase_messaging`.
public protocol NotificationRepository: Sendable {
    /// Shows the system alert/badge/sound prompt (also upgrades provisional) and registers with APNs.
    /// Only call after an explicit user action. Returns whether alerts are allowed.
    @discardableResult
    func requestAuthorization() async throws -> Bool
    /// Silent provisional authorization (no prompt) + APNs registration, used at sign-in.
    @discardableResult
    func requestProvisionalAuthorization() async throws -> Bool
    func authorizationStatus() async -> NotificationAuthorizationStatus
    /// Writes the FCM token to `device_tokens/{userId}/tokens/{token}` (`{token, platform}`), same as Flutter.
    func saveDeviceToken(userId: String) async throws
    func setBadgeCount(_ count: Int) async
}
