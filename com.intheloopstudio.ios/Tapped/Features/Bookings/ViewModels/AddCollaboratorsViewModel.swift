import Foundation
import TappedData
import TappedDomain

/// `lib/ui/gig_search/components/add_collaborators_view.dart`: performer search that builds a bill.
@Observable
@MainActor
final class AddCollaboratorsViewModel {
    var query = ""
    private(set) var results: [UserModel] = []
    private(set) var isSearching = false

    let maxCollaborators: Int
    private let currentUserId: String
    private let search: any SearchRepository

    init(dependencies: Dependencies, currentUserId: String, maxCollaborators: Int = 5) {
        search = dependencies.search
        self.currentUserId = currentUserId
        self.maxCollaborators = maxCollaborators
    }

    func isAtMax(_ collaborators: [UserModel]) -> Bool { collaborators.count >= maxCollaborators }

    /// Performer search bar: `queryUsers(query, unclaimed: false)`, excluding venues and the current user.
    func runSearch() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            results = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        let hits = (try? await search.queryUsers(term, filters: UserSearchFilters(unclaimed: false))) ?? []
        guard !Task.isCancelled else { return }
        results = hits.filter { !$0.isVenue && $0.id != currentUserId }
    }
}
