import Foundation
@preconcurrency import FirebaseCore
@preconcurrency import FirebaseCrashlytics
@preconcurrency import FirebaseMessaging
@preconcurrency import GoogleSignIn

/// All Firebase SDK entry points the app target needs, so `import Firebase*` never appears outside `TappedData`.
public enum FirebaseBootstrap {
    /// True when a real `GoogleService-Info.plist` (not the placeholder) is bundled.
    public static func hasConfiguration(in bundle: Bundle = .main) -> Bool {
        guard let path = bundle.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let appId = plist["GOOGLE_APP_ID"] as? String else { return false }
        return !appId.isEmpty && !appId.contains("PLACEHOLDER")
    }

    @MainActor
    public static func configure() {
        guard FirebaseApp.app() == nil, hasConfiguration() else { return }
        FirebaseApp.configure()
        if let clientId = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        }
    }

    public static var isConfigured: Bool { FirebaseApp.app() != nil }

    /// Google Sign-In OAuth redirect.
    @MainActor
    public static func handle(url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    public static func setAPNSToken(_ deviceToken: Data) {
        guard isConfigured else { return }
        Messaging.messaging().apnsToken = deviceToken
    }

    public static func fcmToken() async throws -> String {
        try await Messaging.messaging().token()
    }

    public static func record(error: any Error) {
        guard isConfigured else { return }
        Crashlytics.crashlytics().record(error: error)
    }
}
