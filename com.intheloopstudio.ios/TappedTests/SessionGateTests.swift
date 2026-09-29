import Foundation
import TappedData
import TappedDomain
import Testing
@testable import Tapped

@MainActor
@Suite("Session gates")
struct SessionGateTests {
    private func defaults() -> UserDefaults {
        let suite = "tapped.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test func minimumVersionBlocksOlderBuilds() async {
        let session = AppSession(
            dependencies: .mock(minimumAppVersion: "2.1.0"),
            appVersion: AppVersion("2.0.9")!,
            defaults: defaults()
        )
        await session.run()
        #expect(session.phase == .updateRequired(minimum: "2.1.0"))
    }

    @Test func latestVersionPromptCanBeIgnored() async throws {
        let store = defaults()
        let dependencies = Dependencies.mock(signedIn: true, latestAppVersion: "2.1")
        let session = AppSession(dependencies: dependencies, appVersion: AppVersion("2.0.0")!, defaults: store)
        let run = Task { await session.run() }
        defer { run.cancel() }
        try await waitUntil { session.currentUser != nil }
        #expect(session.availableUpdate == "2.1")
        session.dismissUpdate(ignoreVersion: true)
        #expect(session.availableUpdate == nil)
        #expect(store.string(forKey: AppSession.skippedUpdateKey) == "2.1")

        let next = AppSession(dependencies: .mock(signedIn: true, latestAppVersion: "2.1"), appVersion: AppVersion("2.0.0")!, defaults: store)
        let nextRun = Task { await next.run() }
        defer { nextRun.cancel() }
        try await waitUntil { next.currentUser != nil }
        #expect(next.availableUpdate == nil)
    }

    @Test func unverifiedSignUpWaitsOnConfirmEmailThenOnboards() async throws {
        let dependencies = Dependencies.mock()
        let session = AppSession(dependencies: dependencies, defaults: defaults())
        let run = Task { await session.run() }
        defer { run.cancel() }
        try await waitUntil { session.phase == .signedOut }

        _ = try await dependencies.auth.signUpWithCredentials(email: "new@example.com", password: "secret1")
        try await waitUntil {
            if case .confirmEmail = session.phase { true } else { false }
        }

        let model = ConfirmEmailViewModel(dependencies: dependencies, authUser: MockAuthRepository.newUser)
        #expect(await model.checkVerification(session: session))
        #expect(session.phase == .onboarding(uid: MockAuthRepository.newUser.uid))
    }

    @Test func confirmEmailReportsStillUnverified() async {
        let dependencies = Dependencies(
            mode: .mock,
            auth: MockAuthRepository(
                signedInAs: AuthUser(uid: "new-artist", email: "new@example.com", providerIds: ["password"]),
                verifiesOnReload: false
            ),
            database: MockDatabaseRepository(),
            search: MockSearchRepository(),
            places: MockPlacesRepository(),
            purchases: MockPurchasesRepository(),
            analytics: MockAnalytics(),
            remoteConfig: MockRemoteConfigRepository()
        )
        let model = ConfirmEmailViewModel(dependencies: dependencies, authUser: MockAuthRepository.newUser)
        #expect(await !model.checkVerification(session: nil))
        #expect(model.errorMessage == "we couldn't confirm your email yet. tap the link in your inbox first")
        await model.resend()
        #expect(model.didResend)
    }

    @Test func signInRegistersForPushAndPublishesVersion() async throws {
        let notifications = MockNotificationRepository()
        let dependencies = Dependencies.mock(signedIn: true, notifications: notifications)
        let session = AppSession(dependencies: dependencies, defaults: defaults())
        let run = Task { await session.run() }
        defer { run.cancel() }
        try await waitUntil { session.currentUser != nil }
        await session.deviceRegistration?.value

        let userId = MockAuthRepository.sampleUser.uid
        #expect(await notifications.provisionalRequests == 1)
        #expect(await notifications.authorizationRequests == 0)
        #expect(await notifications.savedTokens[userId] == [MockNotificationRepository.sampleToken: "ios"])
        #expect(try await dependencies.database.getUserById(userId)?.latestAppVersion == AppVersion.current().firestoreValue)
    }

    @Test func onboardingCompletionEntersShell() async throws {
        let dependencies = Dependencies.mock(onboarding: true)
        let session = AppSession(dependencies: dependencies, defaults: defaults())
        let run = Task { await session.run() }
        defer { run.cancel() }
        try await waitUntil { session.phase == .onboarding(uid: MockAuthRepository.newUser.uid) }

        let user = UserModel(id: MockAuthRepository.newUser.uid, username: "nova_waves")
        try await dependencies.database.createUser(user)
        await session.completeOnboarding(user)
        #expect(session.currentUser?.id == user.id)
    }

    @Test func reauthenticationUsesLinkedProviders() async throws {
        let auth = MockAuthRepository(signedInAs: AuthUser(uid: "u", email: "a@b.co", providerIds: ["apple.com", "password"]))
        let dependencies = Dependencies(
            mode: .mock, auth: auth, database: MockDatabaseRepository(), search: MockSearchRepository(),
            places: MockPlacesRepository(), purchases: MockPurchasesRepository(), analytics: MockAnalytics(),
            remoteConfig: MockRemoteConfigRepository()
        )
        let model = ReauthenticationViewModel(dependencies: dependencies)
        await model.load()
        #expect(model.methods == [.password, .apple])
        #expect(!model.canSubmitPassword)

        model.password = "wrong"
        #expect(await !model.reauthenticate(with: .password))
        #expect(model.errorMessage == "invalid email or password")

        model.password = "secret"
        #expect(await model.reauthenticate(with: .password))
        #expect(await model.reauthenticate(with: .apple))
        #expect(await auth.reauthentications == [.password, .apple])
    }

    @Test func waitlistJoin() async throws {
        let dependencies = Dependencies.mock(signedIn: true, premiumWaitlist: true)
        let model = PremiumWaitlistViewModel(dependencies: dependencies, userId: "performer-nova")
        await model.load()
        #expect(!model.isOnWaitlist)
        await model.join()
        #expect(model.isOnWaitlist)
        #expect(try await dependencies.database.isOnPremiumWailist("performer-nova"))
    }

    @Test func launchOptionsForSession5Screens() {
        let options = LaunchOptions.from([
            "TAPPED_MOCK": "1",
            "TAPPED_MOCK_ONBOARDING_STEP": "genres",
            "TAPPED_MOCK_SHEET": "reauth",
            "TAPPED_MOCK_ROUTE": "paywall",
            "TAPPED_MOCK_LINK": "https://app.tapped.ai/settings",
        ])
        #expect(options.onboardingStep == .genres)
        #expect(options.sheet == .reauth)
        #expect(options.routes == [.paywall])
        #expect(options.link?.path == "/settings")
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("condition not met")
    }
}
