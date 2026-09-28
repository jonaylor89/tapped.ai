import Foundation
import Observation
import TappedData
import TappedDomain

/// Port of `opportunities_results_view.dart`: list with applied badges and batch apply.
@Observable
@MainActor
final class OpportunitiesListViewModel {
    let opportunities: [Opportunity]
    private(set) var appliedIds: Set<String> = []
    private(set) var venueNames: [String: String] = [:]
    private(set) var remainingQuota: Int?
    private(set) var isApplying = false
    private(set) var errorMessage: String?
    var isSelecting = false {
        didSet { if !isSelecting { selectedIds = [] } }
    }
    var selectedIds: Set<String> = []

    private let database: any DatabaseRepository
    private let application: OpportunityApplication
    private let currentUser: UserModel

    init(dependencies: Dependencies, currentUser: UserModel, isPremium: Bool, opportunities: [Opportunity]) {
        self.opportunities = opportunities.sorted { $0.startTime < $1.startTime }
        self.currentUser = currentUser
        database = dependencies.database
        application = OpportunityApplication(dependencies: dependencies, userId: currentUser.id, isPremium: isPremium)
    }

    var isPremium: Bool { application.isPremium }
    var selectable: [Opportunity] { opportunities.filter { !appliedIds.contains($0.id) && $0.userId != currentUser.id } }
    var allSelected: Bool { !selectable.isEmpty && selectedIds.count == selectable.count }
    var selectedOpportunities: [Opportunity] { opportunities.filter { selectedIds.contains($0.id) } }

    func load() async {
        let database = database
        let userId = currentUser.id
        let applied = await withTaskGroup(of: String?.self) { group in
            for opportunity in opportunities {
                group.addTask {
                    (try? await database.isUserAppliedForOpportunity(opportunityId: opportunity.id, userId: userId)) == true ? opportunity.id : nil
                }
            }
            var ids: Set<String> = []
            for await id in group { if let id { ids.insert(id) } }
            return ids
        }
        appliedIds = applied
        for venueId in Set(opportunities.map { $0.venueId ?? $0.userId }) where venueNames[venueId] == nil {
            if let user = try? await database.getUserById(venueId) {
                venueNames[venueId] = user.displayName
            }
        }
        remainingQuota = await application.remainingQuota()
    }

    func venueName(for opportunity: Opportunity) -> String? {
        venueNames[opportunity.venueId ?? opportunity.userId]
    }

    func toggle(_ opportunity: Opportunity) {
        guard !appliedIds.contains(opportunity.id) else { return }
        if selectedIds.contains(opportunity.id) { selectedIds.remove(opportunity.id) } else { selectedIds.insert(opportunity.id) }
    }

    func selectAll(_ selected: Bool) {
        selectedIds = selected ? Set(selectable.map(\.id)) : []
    }

    func applySelected() async -> OpportunityApplication.Outcome? {
        let targets = selectedOpportunities
        guard !targets.isEmpty else { return nil }
        isApplying = true
        defer { isApplying = false }
        do {
            let outcome = try await application.apply(to: targets, comment: "")
            if outcome == .applied {
                appliedIds.formUnion(targets.map(\.id))
                remainingQuota = remainingQuota.map { max($0 - targets.count, 0) }
                isSelecting = false
            }
            return outcome
        } catch {
            errorMessage = "error applying to opportunities"
            return nil
        }
    }

    func dismissError() {
        errorMessage = nil
    }
}
