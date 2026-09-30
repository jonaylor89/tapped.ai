import Foundation
import Observation
import TappedData
import TappedDomain

/// Port of `opportunity_view.dart`'s state: load opportunity, venue + booker, applied state and quota.
@Observable
@MainActor
final class OpportunityViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case notFound
    }

    let opportunityId: String
    let currentUser: UserModel
    let claims: [CustomClaim]
    private(set) var opportunity: Opportunity?
    private(set) var venue: UserModel?
    private(set) var booker: UserModel?
    private(set) var phase: Phase
    private(set) var isApplied = false
    private(set) var isDisliked = false
    private(set) var remainingQuota: Int?
    private(set) var isApplying = false
    private(set) var errorMessage: String?

    private let database: any DatabaseRepository
    private var application: OpportunityApplication

    init(dependencies: Dependencies, currentUser: UserModel, isPremium: Bool, claims: [CustomClaim], opportunityId: String, opportunity: Opportunity?) {
        self.opportunityId = opportunityId
        self.currentUser = currentUser
        self.claims = claims
        self.opportunity = opportunity
        phase = opportunity == nil ? .loading : .loaded
        database = dependencies.database
        application = OpportunityApplication(dependencies: dependencies, userId: currentUser.id, isPremium: isPremium)
    }

    var isPremium: Bool {
        get { application.isPremium }
        set {
            application.isPremium = newValue
            if newValue { remainingQuota = nil }
        }
    }
    var canSeeApplicants: Bool { opportunity?.userId == currentUser.id || claims.contains(.admin) }
    var canApply: Bool { opportunity.map { $0.userId != currentUser.id } ?? false }
    var isPastDeadline: Bool { opportunity?.deadline.map { $0 < .now } ?? false }
    var shareURL: URL? { opportunity.map(OpportunityApplication.shareURL(for:)) }

    func load() async {
        if opportunity == nil {
            opportunity = try? await database.getOpportunityById(opportunityId)
        }
        guard let opportunity, !opportunity.deleted else {
            phase = .notFound
            return
        }
        phase = .loaded
        async let venueUser = database.getUserById(opportunity.venueId ?? opportunity.userId)
        async let bookerUser = database.getUserById(opportunity.userId)
        async let applied = database.isUserAppliedForOpportunity(opportunityId: opportunity.id, userId: currentUser.id)
        venue = try? await venueUser
        let loadedBooker = try? await bookerUser
        booker = loadedBooker?.id == venue?.id ? nil : loadedBooker
        let hasApplied = (try? await applied) ?? false
        isApplied = isApplied || hasApplied
        remainingQuota = await application.remainingQuota()
    }

    func apply(comment: String) async -> OpportunityApplication.Outcome? {
        guard let opportunity else { return nil }
        isApplying = true
        defer { isApplying = false }
        do {
            let outcome = try await application.apply(to: [opportunity], comment: comment.trimmingCharacters(in: .whitespacesAndNewlines))
            if outcome == .applied {
                isApplied = true
                remainingQuota = remainingQuota.map { max($0 - 1, 0) }
            }
            return outcome
        } catch {
            errorMessage = "error applying to opportunity"
            return nil
        }
    }

    func dislike() async {
        guard let opportunity else { return }
        do {
            try await application.dislike(opportunity)
            isDisliked = true
        } catch {
            errorMessage = "couldn't update this gig"
        }
    }

    func dismissError() {
        errorMessage = nil
    }
}
