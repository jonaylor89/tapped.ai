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
    /// Remote Config put the app behind maintenance / update required; auth no longer drives `phase`.
    private var isBlocked = false
    /// Cached Remote Config gate; auth results wait on it before choosing a phase.
    private var launchGate: Task<Void, Never>?
    /// Background Remote Config fetch started once the cached gate passes; exposed for tests.
    private(set) var remoteConfigRefresh: Task<Void, Never>?
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
    ///
    /// The cached Remote Config decides the maintenance / minimum-version gates, while auth, custom claims and the
    /// user doc load concurrently. The network fetch runs in the background and can still close a gate.
    func run() async {
        guard !started else { return }
        started = true
        if launchOptions.screen != nil { return }

        LaunchSignposts.begin(.auth)
        let gate = Task { await applyCachedRemoteConfig() }
        launchGate = gate
        let auth = Task {
            for await authUser in dependencies.auth.authStateChanges() {
                await resolve(authUser)
            }
        }
        await gate.value
        guard !isBlocked else {
            auth.cancel()
            return
        }

        let premium = Task { await observePremium() }
        let remoteConfig = dependencies.remoteConfig
        remoteConfigRefresh = Task {
            _ = try? await remoteConfig.fetchAndActivate()
            LaunchSignposts.mark(.remoteConfigFetched)
            await applyRemoteConfig()
            if isBlocked {
                auth.cancel()
                premium.cancel()
            }
        }
        await withTaskCancellationHandler {
            await auth.value
            await premium.value
        } onCancel: { [remoteConfigRefresh] in
            auth.cancel()
            premium.cancel()
            remoteConfigRefresh?.cancel()
        }
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

    /// Activates the cached config and applies its gates. A cached block is confirmed against the server
    /// (bounded by the fetch timeout) so a stale maintenance flag can't hold the app indefinitely.
    private func applyCachedRemoteConfig() async {
        LaunchSignposts.begin(.remoteConfig)
        defer { LaunchSignposts.end(.remoteConfig) }
        let remoteConfig = dependencies.remoteConfig
        _ = await remoteConfig.activateCached()
        if await blockingPhase() != nil {
            _ = try? await remoteConfig.fetchAndActivate()
        }
        await applyRemoteConfig()
    }

    private func applyRemoteConfig() async {
        if let blocked = await blockingPhase() {
            isBlocked = true
            phase = blocked
            return
        }
        let remoteConfig = dependencies.remoteConfig
        // Only before the shell is up: the prompt swaps the shell for the splash.
        if currentUser == nil, let latest = AppVersion(await remoteConfig.getLatestAppVersion()), appVersion < latest,
           defaults.string(forKey: Self.skippedUpdateKey) != latest.description {
            availableUpdate = latest.description
        }
        premiumWaitlistEnabled = await remoteConfig.getPremiumWaitlistEnabled()
    }

    private func blockingPhase() async -> Phase? {
        let remoteConfig = dependencies.remoteConfig
        if await remoteConfig.getDownForMaintenanceStatus() { return .maintenance }
        if let minimum = AppVersion(await remoteConfig.getMinimumAppVersion()), appVersion < minimum {
            return .updateRequired(minimum: minimum.description)
        }
        return nil
    }

    /// Waits for the launch gate; `false` once Remote Config has blocked the app.
    private func mayChangePhase() async -> Bool {
        await launchGate?.value
        return !isBlocked
    }

    private func resolve(_ authUser: AuthUser?) async {
        guard let authUser else {
            guard await mayChangePhase() else { return }
            claims = []
            phase = .signedOut
            LaunchSignposts.end(.auth)
            return
        }
        let auth = dependencies.auth
        let database = dependencies.database
        LaunchSignposts.begin(.userDoc)
        async let customClaims = try? auth.getCustomClaims()
        async let userDoc = database.getUserById(authUser.uid)
        let resolvedClaims = await customClaims ?? []
        var user: UserModel?
        do {
            user = try await userDoc
        } catch {
            FirebaseBootstrap.record(error: error)
        }
        LaunchSignposts.end(.userDoc)
        guard await mayChangePhase() else { return }
        claims = resolvedClaims
        defer { LaunchSignposts.end(.auth) }
        if let user {
            await enter(user)
            return
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
