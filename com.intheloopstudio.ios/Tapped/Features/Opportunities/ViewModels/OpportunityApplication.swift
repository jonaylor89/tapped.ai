import Foundation
import TappedData
import TappedDomain

/// Port of `OpportunityBloc`'s `ApplyForOpportunity` / `BatchApplyForOpportunities`: non-premium users spend
/// `credits/{uid}.opportunityQuota`; running out sends them to the paywall.
struct OpportunityApplication: Sendable {
    enum Outcome: Equatable, Sendable {
        case applied
        case needsPremium
    }

    let database: any DatabaseRepository
    let analytics: any AnalyticsRepository
    let functions: any FunctionsRepository
    let userId: String
    var isPremium: Bool

    init(dependencies: Dependencies, userId: String, isPremium: Bool) {
        database = dependencies.database
        analytics = dependencies.analytics
        functions = dependencies.functions
        self.userId = userId
        self.isPremium = isPremium
    }

    /// `nil` for premium users (unlimited).
    func remainingQuota() async -> Int? {
        guard !isPremium else { return nil }
        return (try? await database.getUserOpportunityQuota(userId)) ?? 0
    }

    func apply(to opportunities: [Opportunity], comment: String) async throws -> Outcome {
        if !isPremium {
            let quota = (try? await database.getUserOpportunityQuota(userId)) ?? 0
            guard quota >= opportunities.count else {
                await analytics.track("quota_limit_hit", properties: ["user_id": .string(userId), "opportunity_count": .int(opportunities.count)])
                return .needsPremium
            }
        }
        for opportunity in opportunities {
            try await database.applyForOpportunity(opportunity: opportunity, userId: userId, userComment: comment)
        }
        try await functions.notifyVenueOfInterestedOpportunities(opportunityIds: opportunities.map(\.id), userId: userId, note: comment)
        if !isPremium {
            for _ in opportunities {
                try? await database.decrementUserOpportunityQuota(userId)
            }
        }
        await analytics.track("apply_for_opportunity", properties: ["user_id": .string(userId), "opportunity_count": .int(opportunities.count)])
        return .applied
    }

    func dislike(_ opportunity: Opportunity) async throws {
        try await database.dislikeOpportunity(opportunity: opportunity, userId: userId)
    }

    static func shareURL(for opportunity: Opportunity) -> URL {
        URL(string: "https://app.tapped.ai/opportunity/\(opportunity.id)") ?? URL(filePath: "/")
    }
}
