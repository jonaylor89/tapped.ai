import Foundation
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseMessaging
import UIKit
import UserNotifications

/// `lib/data/prod/cloud_messaging_impl.dart`.
/// Stream Chat `addDevice` is owned by the messaging session (session 6).
public struct FirebaseNotificationRepository: NotificationRepository {
    /// Flutter writes `Platform.operatingSystem`.
    static let platform = "ios"

    public init() {}

    private var tokens: CollectionReference { Firestore.firestore().collection("device_tokens") }

    public func requestAuthorization() async throws -> Bool {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    public func requestProvisionalAuthorization() async throws -> Bool {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .provisional])
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    public func authorizationStatus() async -> NotificationAuthorizationStatus {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .ephemeral: .authorized
        case .provisional: .provisional
        case .denied: .denied
        default: .notDetermined
        }
    }

    public func saveDeviceToken(userId: String) async throws {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let token = try await Messaging.messaging().token()
        try await tokens.document(userId).collection("tokens").document(token).setData([
            "token": token,
            "platform": Self.platform,
        ])
    }

    public func setBadgeCount(_ count: Int) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }
}
