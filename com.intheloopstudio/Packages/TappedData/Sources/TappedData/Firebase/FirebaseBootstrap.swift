import Foundation
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseCore
@preconcurrency import FirebaseCrashlytics
@preconcurrency import FirebaseMessaging
@preconcurrency import FirebaseStorage
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
        useEmulators()
        if let clientId = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        }
    }

    public static var isConfigured: Bool { FirebaseApp.app() != nil }

    /// Debug builds launched with `FIREBASE_AUTH_EMULATOR_HOST` (and optionally `FIREBASE_STORAGE_EMULATOR_HOST`),
    /// as `host:port`, sign in against the local Firebase emulators instead of the production project.
    public static var usesEmulators: Bool {
        #if DEBUG
        emulatorAddress("FIREBASE_AUTH_EMULATOR_HOST") != nil
        #else
        false
        #endif
    }

    static func emulatorAddress(
        _ key: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> (host: String, port: Int)? {
        guard let value = environment[key], let separator = value.lastIndex(of: ":"),
              let port = Int(value[value.index(after: separator)...]) else { return nil }
        let host = String(value[..<separator])
        return host.isEmpty ? nil : (host, port)
    }

    private static func useEmulators() {
        #if DEBUG
        if let auth = emulatorAddress("FIREBASE_AUTH_EMULATOR_HOST") {
            Auth.auth().useEmulator(withHost: auth.host, port: auth.port)
        }
        if let storage = emulatorAddress("FIREBASE_STORAGE_EMULATOR_HOST") {
            Storage.storage().useEmulator(withHost: storage.host, port: storage.port)
        }
        #endif
    }

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
