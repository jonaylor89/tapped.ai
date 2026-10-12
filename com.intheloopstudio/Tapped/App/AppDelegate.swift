import TappedData
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        LaunchSignposts.mark(.didFinishLaunching)
        LaunchSignposts.begin(.launch)
        // Set before launch finishes so a notification tap that cold-starts the app is delivered to `didReceive`.
        UNUserNotificationCenter.current().delegate = self
        NotificationCategories.register()
        GigNightCoordinator.shared.start()
        guard AppEnvironment.dependencies.mode == .live else { return true }
        FirebaseBootstrap.configure()
        let config = TappedConfig.fromBundle()
        // Local-stack runs must not report into production analytics.
        guard !FirebaseBootstrap.usesEmulators else {
            application.registerForRemoteNotifications()
            return true
        }
        PostHogAnalytics.configure(apiKey: config.postHogAPIKey, host: config.postHogHost)
        AppTelemetry.start(config: config)
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

    // The async variant returns to UIKit off the main thread, which crashes on a banner tap.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let action = NotificationActionResponse(response)
        let payload = NotificationPayload(userInfo: response.notification.request.content.userInfo)
        Task { @MainActor in
            if action.isAction {
                await NotificationActionRouter.perform(action)
            } else {
                AppEnvironment.inbound.receive(payload)
            }
            completionHandler()
        }
    }
}
