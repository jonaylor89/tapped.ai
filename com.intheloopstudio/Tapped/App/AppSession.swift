import Foundation
import Observation
import TappedData
import TappedDomain

/// App-wide auth + current-user state that drives the gate in `ContentView`.
@Observable
@MainActor
final class AppSession {
    enum Phase: Equatable {
        case splash
        case maintenance
        /// Remote Config `ios_minimum_app_version` is newer than this build.
        case updateRequired(minimum: String)
        case signedOut
        /// Email/password account without a `users/{uid}` document that hasn't verified its email.
        case confirmEmail(AuthUser)
        /// Signed in with Firebase but no `users/{uid}` document yet.
        case onboarding(uid: String)
        case signedIn(UserModel)
    }

    static let skippedUpdateKey = "tapped.skippedUpdateVersion"

    private(set) var phase: Phase = .splash
    private(set) var isPremium = false
    private(set) var claims: [CustomClaim] = []
    /// Remote Config `ios_latest_app_version` when newer than this build and not ignored.
    private(set) var availableUpdate: String?
    private(set) var premiumWaitlistEnabled = false
    let launchOptions: LaunchOptions
    let appVersion: AppVersion

    private let dependencies: Dependencies
    private let defaults: UserDefaults
    private var started = false
    /// Post-sign-in side effects (push token, `latestAppVersion`); exposed for tests.
    private(set) var deviceRegistration: Task<Void, Never>?

    init(
        dependencies: Dependencies,
        launchOptions: LaunchOptions = .none,
        appVersion: AppVersion = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.dependencies = dependencies
        self.launchOptions = launchOptions
        self.appVersion = appVersion
        self.defaults = defaults
    }

    var currentUser: UserModel? {
        if case let .signedIn(user) = phase { user } else { nil }
    }

    /// Runs for the lifetime of the scene (`ContentView.task`).
    func run() async {
        guard !started else { return }
        started = true
        if launchOptions.screen != nil { return }

        let remoteConfig = dependencies.remoteConfig
        _ = try? await remoteConfig.fetchAndActivate()
        if await remoteConfig.getDownForMaintenanceStatus() {
            phase = .maintenance
            return
        }
        if let minimum = AppVersion(await remoteConfig.getMinimumAppVersion()), appVersion < minimum {
            phase = .updateRequired(minimum: minimum.description)
            return
        }
        if let latest = AppVersion(await remoteConfig.getLatestAppVersion()), appVersion < latest,
           defaults.string(forKey: Self.skippedUpdateKey) != latest.description {
            availableUpdate = latest.description
        }
        premiumWaitlistEnabled = await remoteConfig.getPremiumWaitlistEnabled()

        async let premium: Void = observePremium()
        for await authUser in dependencies.auth.authStateChanges() {
            await resolve(authUser)
        }
        await premium
    }

    func refreshCurrentUser() async {
        guard let uid = currentUser?.id else { return }
        if let user = try? await dependencies.database.getUserById(uid) {
            phase = .signedIn(user)
        }
    }

    func updateCurrentUser(_ user: UserModel) {
        guard currentUser?.id == user.id else { return }
        phase = .signedIn(user)
    }

    func signOut() async {
        await dependencies.chat.disconnect()
        try? await dependencies.auth.logout()
        await dependencies.analytics.reset()
    }

    /// Re-reads the Firebase user (confirm-email "i've verified") and re-runs the gate.
    func reloadAuthUser() async throws {
        let authUser = try await dependencies.auth.reloadUser()
        await resolve(authUser)
    }

    /// Onboarding wrote `users/{uid}`; enter the app without waiting for another auth event.
    func completeOnboarding(_ user: UserModel) async {
        await enter(user)
    }

    /// Upgrade prompt buttons (`upgrader`: ignore / later / update now).
    func dismissUpdate(ignoreVersion: Bool) {
        if ignoreVersion, let availableUpdate {
            defaults.set(availableUpdate, forKey: Self.skippedUpdateKey)
        }
        availableUpdate = nil
    }

    /// APNs can deliver the device token after sign-in; FCM needs it before `token()` succeeds.
    func saveDeviceTokenIfSignedIn() async {
        guard let userId = currentUser?.id else { return }
        do {
            try await dependencies.notifications.saveDeviceToken(userId: userId)
        } catch {
            FirebaseBootstrap.record(error: error)
        }
    }

    private func resolve(_ authUser: AuthUser?) async {
        guard let authUser else {
            if currentUser != nil { await dependencies.chat.disconnect() }
            claims = []
            phase = .signedOut
            return
        }
        claims = (try? await dependencies.auth.getCustomClaims()) ?? []
        do {
            if let user = try await dependencies.database.getUserById(authUser.uid) {
                await enter(user)
                return
            }
        } catch {
            FirebaseBootstrap.record(error: error)
        }
        phase = authUser.requiresEmailVerification ? .confirmEmail(authUser) : .onboarding(uid: authUser.uid)
    }

    private func enter(_ user: UserModel) async {
        phase = .signedIn(user)
        await dependencies.analytics.identify(userId: user.id, properties: ["username": .string(user.username.username)])
        deviceRegistration?.cancel()
        let dependencies = dependencies
        deviceRegistration = Task {
            do {
                _ = try await dependencies.database.publishLatestAppVersion(user.id)
            } catch {
                FirebaseBootstrap.record(error: error)
            }
            do {
                // Quiet provisional delivery only; the system prompt waits for `NotificationsPromptCard`.
                try await dependencies.notifications.requestProvisionalAuthorization()
                try await dependencies.notifications.saveDeviceToken(userId: user.id)
            } catch {
                FirebaseBootstrap.record(error: error)
            }
        }
    }

    private func observePremium() async {
        for await entitlements in dependencies.purchases.entitlementUpdates() {
            isPremium = entitlements.contains(.premium)
        }
    }
}
