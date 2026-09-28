import TappedData
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard AppEnvironment.dependencies.mode == .live else { return true }
        FirebaseBootstrap.configure()
        let config = TappedConfig.fromBundle()
        PostHogAnalytics.configure(apiKey: config.postHogAPIKey, host: config.postHogHost)
        UNUserNotificationCenter.current().delegate = self
        // Permission is requested during onboarding (session 5); registering is harmless before that.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        FirebaseBootstrap.setAPNSToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        FirebaseBootstrap.record(error: error)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .badge, .sound]
    }
}
