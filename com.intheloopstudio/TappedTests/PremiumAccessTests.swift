import Foundation
import TappedData
import TappedDomain
import Testing
@testable import Tapped

@MainActor
@Suite("Premium-only access")
struct PremiumAccessTests {
    @Test func savedProfileResumesAtActivationAfterRelaunch() async throws {
        let dependencies = Dependencies.mock(onboarding: true)
        let session = AppSession(dependencies: dependencies)
        let run = Task { await session.run() }
        try await waitUntil { session.phase == .onboarding(uid: MockAuthRepository.newUser.uid) }
        let onboarding = OnboardingViewModel(dependencies: dependencies)
        onboarding.artistName = "New Artist"
        let user = try #require(await onboarding.finish())
        await session.completeOnboarding(user)
        #expect(session.phase == .premiumRequired(user))
        #expect(session.currentUser == nil)
        #expect(session.deviceRegistration == nil)
        run.cancel()
        await run.value

        let resumed = AppSession(dependencies: dependencies)
        let resumedRun = Task { await resumed.run() }
        defer { resumedRun.cancel() }
        try await waitUntil { resumed.phase == .premiumRequired(user) }
        let paywall = PaywallViewModel(dependencies: dependencies)
        await paywall.load()
        await paywall.purchase()
        try await waitUntil { resumed.currentUser?.id == user.id }
        #expect(resumed.isPremium)
    }

    @Test func existingNonSubscriberNeverEntersShell() async throws {
        let session = AppSession(dependencies: .mock(signedIn: true, premiumWaitlist: true))
        let run = Task { await session.run() }
        defer { run.cancel() }
        try await waitUntil { if case .premiumRequired = session.phase { true } else { false } }
        #expect(session.currentUser == nil)
        #expect(session.deviceRegistration == nil)
        await session.refreshCurrentUser()
        #expect(session.currentUser == nil)
    }

    @Test func revocationAndRestoreUseTheSameGate() async throws {
        let purchases = ControlledPurchases(premium: true)
        var dependencies = Dependencies.mock(signedIn: true)
        dependencies.purchases = purchases
        let session = AppSession(dependencies: dependencies)
        let run = Task { await session.run() }
        defer { run.cancel() }
        try await waitUntil { session.currentUser != nil }
        await purchases.setPremium(false)
        try await waitUntil { if case .premiumRequired = session.phase { true } else { false } }
        #expect(session.currentUser == nil)
        await purchases.enableRestore()
        let paywall = PaywallViewModel(dependencies: dependencies)
        await paywall.restore()
        try await waitUntil { session.currentUser != nil }
        #expect(paywall.isPremium)

        await session.signOut()
        try await waitUntil { session.phase == .signedOut }
        await purchases.setPremium(true)
        await session.refreshPremiumAccess()
        #expect(session.phase == .signedOut)
        #expect(session.currentUser == nil)
    }

    @Test func foregroundRefreshCatchesSilentExpiration() async throws {
        let purchases = ControlledPurchases(premium: true)
        var dependencies = Dependencies.mock(signedIn: true)
        dependencies.purchases = purchases
        let session = AppSession(dependencies: dependencies)
        let run = Task { await session.run() }
        defer { run.cancel() }
        try await waitUntil { session.currentUser != nil }
        await purchases.setPremium(false, publish: false)
        await session.refreshPremiumAccess()
        #expect(session.currentUser == nil)
        if case .premiumRequired = session.phase {} else { Issue.record("expected activation") }
    }

    @Test(arguments: [PurchaseOutcome.cancelled, .pending, .purchased])
    func purchaseOutcomeAloneCannotUnlockAccess(outcome: PurchaseOutcome) async {
        var dependencies = Dependencies.mock(signedIn: true)
        dependencies.purchases = ControlledPurchases(outcome: outcome)
        let paywall = PaywallViewModel(dependencies: dependencies)
        await paywall.load()
        let selected = paywall.selectedProductId
        await paywall.purchase()
        #expect(!paywall.isPremium, "only a verified active entitlement grants access")
        #expect(paywall.selectedProductId == selected)
        #expect(!paywall.isBusy)
        if outcome == .cancelled { #expect(paywall.notice == nil) }
        if outcome == .pending { #expect(paywall.notice == "purchase pending approval") }
    }

    @Test func missingPlansAndRestoreFailureStayRecoverable() async {
        var dependencies = Dependencies.mock(signedIn: true)
        dependencies.purchases = ControlledPurchases(unavailable: true)
        let paywall = PaywallViewModel(dependencies: dependencies)
        await paywall.load()
        if case .failed = paywall.phase {} else { Issue.record("expected retryable load failure") }
        #expect(paywall.selectedProduct == nil)
        await paywall.restore()
        #expect(!paywall.isPremium)
        #expect(paywall.notice != nil)
        #expect(!paywall.isBusy)
    }

    @Test func backgroundActionsCannotBypassActivation() async throws {
        let dependencies = Dependencies.mock(signedIn: true)
        let router = NotificationActionRouter(dependencies: dependencies)
        for (action, info) in [("APPLY", ["opportunityId": Samples.opportunities[0].id]), ("ACCEPT", ["bookingId": "booking-2"]), ("REPLY", ["bookingId": "booking-2"])] {
            let response = NotificationActionResponse(categoryIdentifier: "", actionIdentifier: action, userInfo: info, text: "hello")
            #expect(await router.handle(response) == .requiresActivation(response.payload))
        }
        #expect(try await dependencies.database.getBookingById("booking-2")?.status == .pending)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("access transition did not complete")
    }
}

private actor ControlledPurchases: PurchasesRepository {
    private var premium: Bool
    private var restores = false
    private let outcome: PurchaseOutcome
    private let unavailable: Bool
    private var observers: [UUID: AsyncStream<Set<Entitlement>>.Continuation] = [:]

    init(premium: Bool = false, outcome: PurchaseOutcome = .cancelled, unavailable: Bool = false) {
        self.premium = premium
        self.outcome = outcome
        self.unavailable = unavailable
    }

    func products() async throws -> [PremiumProduct] {
        if unavailable { return [] }
        return try await MockPurchasesRepository().products()
    }
    func purchase(productId: String) async throws -> PurchaseOutcome { outcome }
    func enableRestore() { restores = true }
    func restorePurchases() async throws {
        if unavailable { throw URLError(.notConnectedToInternet) }
        if restores { setPremium(true) }
    }
    func activeEntitlements() async -> Set<Entitlement> { premium ? [.premium] : [] }
    func setPremium(_ value: Bool, publish: Bool = true) {
        premium = value
        guard publish else { return }
        for observer in observers.values { observer.yield(value ? [.premium] : []) }
    }
    nonisolated func entitlementUpdates() -> AsyncStream<Set<Entitlement>> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addObserver(id, continuation) }
            continuation.onTermination = { _ in Task { await self.removeObserver(id) } }
        }
    }
    private func addObserver(_ id: UUID, _ continuation: AsyncStream<Set<Entitlement>>.Continuation) {
        observers[id] = continuation
        continuation.yield(premium ? [.premium] : [])
    }
    private func removeObserver(_ id: UUID) { observers[id] = nil }
}
