import TappedData
import TappedDomain
import Testing
@testable import Tapped

@MainActor
@Suite("App shell")
struct AppShellTests {
    @Test func sessionMovesFromSignedOutToSignedIn() async throws {
        let dependencies = Dependencies.mock()
        let session = AppSession(dependencies: dependencies)
        let run = Task { await session.run() }
        defer { run.cancel() }

        try await waitUntil { session.phase == .signedOut }
        _ = try await dependencies.auth.signInWithCredentials(email: "nova@example.com", password: "secret")
        try await waitUntil { session.currentUser != nil }
        #expect(session.currentUser?.id == MockAuthRepository.sampleUser.uid)

        await session.signOut()
        try await waitUntil { session.phase == .signedOut }
    }

    @Test func maintenanceGate() async {
        let session = AppSession(dependencies: .mock(downForMaintenance: true))
        await session.run()
        #expect(session.phase == .maintenance)
    }

    @Test func routerPushPop() {
        let router = Router()
        router.push(.settings)
        router.push(.tasks)
        #expect(router.path == [.settings, .tasks])
        router.pop()
        #expect(router.path == [.settings])
        router.popToRoot()
        #expect(router.isAtRoot)
    }

    @Test(arguments: [
        Route.settings, .tasks, .search, .gigSearch, .paywall, .admin, .messagingChannelList, .onboarding,
        .profile(userId: "u", user: nil), .bookings(userId: "u"), .reviews(userId: "u"),
    ])
    func routeTitlesAreLowercaseAndOwned(route: Route) {
        #expect(route.title == route.title.lowercased())
        #expect(!route.title.isEmpty)
        #expect(route.owner != nil)
    }

    @Test func launchOptionsOnlyApplyInMockMode() {
        #expect(LaunchOptions.from(["TAPPED_MOCK_SCREEN": "signup"]) == .none)
        let options = LaunchOptions.from(["TAPPED_MOCK": "1", "TAPPED_MOCK_SCREEN": "signup", "TAPPED_MOCK_DETENT": "large"])
        #expect(options.screen == .signup)
        #expect(options.detent == .large)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("condition not met")
    }
}
