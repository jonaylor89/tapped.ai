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
        case signedOut
        /// Signed in with Firebase but no `users/{uid}` document yet.
        case onboarding(uid: String)
        case signedIn(UserModel)
    }

    private(set) var phase: Phase = .splash
    private(set) var isPremium = false
    private(set) var claims: [CustomClaim] = []
    let launchOptions: LaunchOptions

    private let dependencies: Dependencies
    private var started = false

    init(dependencies: Dependencies, launchOptions: LaunchOptions = .none) {
        self.dependencies = dependencies
        self.launchOptions = launchOptions
    }

    var currentUser: UserModel? {
        if case let .signedIn(user) = phase { user } else { nil }
    }

    /// Runs for the lifetime of the scene (`ContentView.task`).
    func run() async {
        guard !started else { return }
        started = true
        if launchOptions.screen != nil { return }

        _ = try? await dependencies.remoteConfig.fetchAndActivate()
        if await dependencies.remoteConfig.getDownForMaintenanceStatus() {
            phase = .maintenance
            return
        }

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

    func signOut() async {
        try? await dependencies.auth.logout()
        await dependencies.analytics.reset()
    }

    private func resolve(_ authUser: AuthUser?) async {
        guard let authUser else {
            claims = []
            phase = .signedOut
            return
        }
        claims = (try? await dependencies.auth.getCustomClaims()) ?? []
        do {
            if let user = try await dependencies.database.getUserById(authUser.uid) {
                phase = .signedIn(user)
                await dependencies.analytics.identify(userId: user.id, properties: ["username": .string(user.username.username)])
            } else {
                phase = .onboarding(uid: authUser.uid)
            }
        } catch {
            FirebaseBootstrap.record(error: error)
            phase = .onboarding(uid: authUser.uid)
        }
    }

    private func observePremium() async {
        for await entitlements in dependencies.purchases.entitlementUpdates() {
            isPremium = entitlements.contains(.premium)
        }
    }
}
