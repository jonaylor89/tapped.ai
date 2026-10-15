import Foundation
import TappedData
import TappedDomain

/// Unmetered applications. The session owns premium access, not individual features.
struct OpportunityApplication: Sendable {
    enum Outcome: Equatable, Sendable {
        case applied
    }

    let database: any DatabaseRepository
    let analytics: any AnalyticsRepository
    let opportunityNotifications: any OpportunityNotificationRepository
    let userId: String

    init(dependencies: Dependencies, userId: String) {
        database = dependencies.database
        analytics = dependencies.analytics
        opportunityNotifications = dependencies.opportunityNotifications
        self.userId = userId
    }

    func apply(to opportunities: [Opportunity], comment: String) async throws -> Outcome {
        for opportunity in opportunities {
            try await database.applyForOpportunity(opportunity: opportunity, userId: userId, userComment: comment)
        }
        // The API write completes first; venue notifications retry in the background.
        let opportunityIds = opportunities.map(\.id)
        Task.detached(priority: .utility) { [analytics, opportunityNotifications, userId] in
            await analytics.track("apply_for_opportunity", properties: ["user_id": .string(userId), "opportunity_count": .int(opportunityIds.count)])
            await Self.notifyVenue(opportunityNotifications, opportunityIds: opportunityIds, note: comment)
        }
        return .applied
    }

    /// Retries the venue notification on a short backoff, then reports the final failure to error tracking.
    static func notifyVenue(
        _ opportunityNotifications: any OpportunityNotificationRepository,
        opportunityIds: [String],
        note: String,
        maxAttempts: Int = 3
    ) async {
        for attempt in 1...maxAttempts {
            do {
                try await opportunityNotifications.notifyVenueOfInterestedOpportunities(opportunityIds: opportunityIds, note: note)
                return
            } catch {
                guard attempt < maxAttempts else {
                    ErrorReporting.record(error: error)
                    return
                }
                try? await Task.sleep(for: .milliseconds(500 * attempt))
            }
        }
    }

    func dislike(_ opportunity: Opportunity) async throws {
        try await database.dislikeOpportunity(opportunity: opportunity, userId: userId)
    }

    static func shareURL(for opportunity: Opportunity) -> URL {
        URL(string: "https://app.tapped.ai/opportunity/\(opportunity.id)") ?? URL(filePath: "/")
    }
}
