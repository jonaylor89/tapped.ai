import TappedData
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set before launch finishes so a notification tap that cold-starts the app is delivered to `didReceive`.
        UNUserNotificationCenter.current().delegate = self
        guard AppEnvironment.dependencies.mode == .live else { return true }
        FirebaseBootstrap.configure()
        let config = TappedConfig.fromBundle()
        PostHogAnalytics.configure(apiKey: config.postHogAPIKey, host: config.postHogHost)
        // Provisional permission at sign in (`AppSession`), full prompt from `NotificationsPromptCard`.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        FirebaseBootstrap.setAPNSToken(deviceToken)
        AppEnvironment.inbound.apnsTokenRegistered()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        FirebaseBootstrap.record(error: error)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .badge, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let payload = NotificationPayload(userInfo: response.notification.request.content.userInfo)
        await MainActor.run { AppEnvironment.inbound.receive(payload) }
    }
}
