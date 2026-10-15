import Foundation
import Synchronization
import UIKit
import UserNotifications

/// The APNs device token from `didRegisterForRemoteNotificationsWithDeviceToken`, held until the session uploads it.
public enum APNsDeviceToken {
    private static let current = Mutex<String?>(nil)

    public static func set(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        current.withLock { $0 = hex }
    }

    public static var value: String? { current.withLock { $0 } }
}

/// Permission, APNs registration and badge plumbing. The Rust identity worker delivers straight to APNs.
/// Stream Chat `addDevice` is owned by the messaging session (session 6).
public struct APNsNotificationRepository: NotificationRepository {
    static let platform = "ios"
    /// Matches the `aps-environment` entitlement: Debug signs with development, Release with production.
    static var environment: String {
        #if DEBUG
        "development"
        #else
        "production"
        #endif
    }

    private let client: TappedAPIDataClient
    private let deviceToken: @Sendable () -> String?

    public init(
        baseURL: URL = URL(string: "https://api.tapped.ai")!,
        deviceToken: @escaping @Sendable () -> String? = { APNsDeviceToken.value }
    ) {
        client = TappedAPIDataClient(baseURL: baseURL)
        self.deviceToken = deviceToken
    }

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
        // APNs may not have answered yet; `InboundLinks.apnsRegistrations` triggers the retry when it does.
        guard let token = deviceToken() else { return }
        try await client.registerAPNsDeviceToken(token, platform: Self.platform, environment: Self.environment)
    }

    public func setBadgeCount(_ count: Int) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }
}
