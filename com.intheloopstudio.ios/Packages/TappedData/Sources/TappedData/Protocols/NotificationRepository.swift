import Foundation

/// `lib/data/notification_repository.dart` + the APNs / badge plumbing Flutter got from `firebase_messaging`.
public protocol NotificationRepository: Sendable {
    /// Prompts for alert/badge/sound permission and registers with APNs. Returns whether alerts are allowed.
    @discardableResult
    func requestAuthorization() async throws -> Bool
    /// Writes the FCM token to `device_tokens/{userId}/tokens/{token}` (`{token, platform}`), same as Flutter.
    func saveDeviceToken(userId: String) async throws
    func setBadgeCount(_ count: Int) async
}
