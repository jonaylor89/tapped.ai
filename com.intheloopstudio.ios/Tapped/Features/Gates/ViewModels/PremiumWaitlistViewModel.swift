import Foundation
import Observation
import TappedData

/// `premium_waitlist_view.dart`: shown instead of the paywall while Remote Config `premium_waitlist_enabled` is on.
@Observable
@MainActor
final class PremiumWaitlistViewModel {
    private(set) var isOnWaitlist = false
    private(set) var isLoading = true
    var errorMessage: String?

    private let database: any DatabaseRepository
    private let analytics: any AnalyticsRepository
    let userId: String

    init(dependencies: Dependencies, userId: String) {
        database = dependencies.database
        analytics = dependencies.analytics
        self.userId = userId
    }

    func load() async {
        defer { isLoading = false }
        isOnWaitlist = (try? await database.isOnPremiumWailist(userId)) ?? false
    }

    func join() async {
        do {
            try await database.joinPremiumWaitlist(userId)
            isOnWaitlist = true
            await analytics.track("join_premium_waitlist", properties: ["user_id": .string(userId)])
        } catch {
            errorMessage = "couldn't join the waitlist. try again"
        }
    }
}

enum AppStoreLink {
    static let url = URL(string: "https://apps.apple.com/app/id1574937614")!
}
