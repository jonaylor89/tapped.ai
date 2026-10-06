import Foundation
import Observation
import TappedData
import TappedDomain

/// Port of `OpportunityFeedCubit`: page through `opportunityFeeds/{uid}/opportunities` one card at a time.
@Observable
@MainActor
final class OpportunityFeedViewModel {
    static let pageSize = 10

    enum SwipeAction: Equatable {
        case apply
        case dislike
        case dismiss
    }

    let currentUser: UserModel
    private(set) var opportunities: [Opportunity] = []
    private(set) var currentIndex = 0
    private(set) var isLoading = true
    private(set) var failed = false
    private(set) var appliedCount = 0
    private(set) var remainingQuota: Int?
    private(set) var venues: [String: UserModel] = [:]
    private var reachedEnd = false
    private var isFetchingMore = false

    private let database: any DatabaseRepository
    private var application: OpportunityApplication

    init(dependencies: Dependencies, currentUser: UserModel, isPremium: Bool) {
        self.currentUser = currentUser
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

    var current: Opportunity? { opportunities.indices.contains(currentIndex) ? opportunities[currentIndex] : nil }
    var next: Opportunity? { opportunities.indices.contains(currentIndex + 1) ? opportunities[currentIndex + 1] : nil }
    var isCaughtUp: Bool { !isLoading && current == nil }

    func venue(for opportunity: Opportunity) -> UserModel? {
        venues[opportunity.venueId ?? opportunity.userId]
    }

    func load() async {
        isLoading = true
        do {
            let page = try await database.getOpportunityFeedByUserId(currentUser.id, limit: Self.pageSize, lastOpportunityId: nil)
            opportunities = page
            currentIndex = 0
            reachedEnd = page.count < Self.pageSize
            failed = false
        } catch {
            failed = true
        }
        // The first card can render as soon as its page lands; the quota and the venue
        // reads fill in behind it in parallel.
        isLoading = false
        async let quotaLoad: () = loadQuota()
        await loadVenues()
        await quotaLoad
    }

    private func loadQuota() async {
        remainingQuota = await application.remainingQuota()
    }

    /// Returns `.needsPremium` when the swipe couldn't be applied (quota exhausted).
    @discardableResult
    func perform(_ action: SwipeAction, comment: String = "") async -> OpportunityApplication.Outcome? {
        guard let opportunity = current else { return nil }
        switch action {
        case .apply:
            do {
                let outcome = try await application.apply(to: [opportunity], comment: comment)
                guard outcome == .applied else { return outcome }
                appliedCount += 1
                remainingQuota = remainingQuota.map { max($0 - 1, 0) }
            } catch {
                return nil
            }
        case .dislike:
            try? await application.dislike(opportunity)
        case .dismiss:
            break
        }
        advance()
        return action == .apply ? .applied : nil
    }

    private func advance() {
        currentIndex += 1
        if currentIndex >= opportunities.count - 2 {
            Task { await fetchMore() }
        }
    }

    private func fetchMore() async {
        guard !reachedEnd, !isFetchingMore, let last = opportunities.last else { return }
        isFetchingMore = true
        defer { isFetchingMore = false }
        guard let page = try? await database.getOpportunityFeedByUserId(currentUser.id, limit: Self.pageSize, lastOpportunityId: last.id) else { return }
        let known = Set(opportunities.map(\.id))
        opportunities += page.filter { !known.contains($0.id) }
        reachedEnd = page.count < Self.pageSize
        await loadVenues()
    }

    private func loadVenues() async {
        var seen: Set<String> = []
        var ids = opportunities.compactMap { opportunity -> String? in
            let id = opportunity.venueId ?? opportunity.userId
            guard seen.insert(id).inserted, venues[id] == nil else { return nil }
            return id
        }
        // The visible card's venue loads first so it fills in as early as possible.
        if let current, let index = ids.firstIndex(of: current.venueId ?? current.userId) {
            ids.swapAt(0, index)
        }
        if let first = ids.first {
            if let user = try? await database.getUserById(first) { venues[first] = user }
            ids.removeFirst()
        }
        await withTaskGroup(of: (String, UserModel?).self) { group in
            for id in ids {
                group.addTask { [database] in
                    (id, try? await database.getUserById(id))
                }
            }
            for await (id, user) in group {
                if let user { venues[id] = user }
            }
        }
    }
}
