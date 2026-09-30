import Foundation
import Observation
import TappedData
import TappedDomain

enum SearchScope: String, CaseIterable, Hashable, Sendable {
    case all
    case performers
    case venues
}

/// Port of `SearchBloc` for the search screen: debounced Typesense user search plus recent searches.
@Observable
@MainActor
final class SearchViewModel {
    static let debounce: Duration = .milliseconds(500)

    let currentUser: UserModel
    var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    var scope: SearchScope = .all {
        didSet { if scope != oldValue { scheduleSearch(immediately: true) } }
    }

    private(set) var results: [UserModel] = []
    private(set) var isSearching = false
    private(set) var failed = false
    private(set) var recentSearches: [String]
    private(set) var nearbyOpportunities: [Opportunity] = []

    private let search: any SearchRepository
    private let analytics: any AnalyticsRepository
    private let recents: RecentSearches
    private let debounce: Duration
    private var searchTask: Task<Void, Never>?

    init(dependencies: Dependencies, currentUser: UserModel, recents: RecentSearches = RecentSearches(), debounce: Duration = SearchViewModel.debounce) {
        self.currentUser = currentUser
        search = dependencies.search
        analytics = dependencies.analytics
        self.recents = recents
        self.debounce = debounce
        recentSearches = recents.terms
    }

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isIdle: Bool { trimmedQuery.isEmpty }

    /// "gigs near you" on the idle screen.
    func loadNearby() async {
        guard nearbyOpportunities.isEmpty else { return }
        let location = currentUser.location
        nearbyOpportunities = (try? await search.queryOpportunities("", lat: location?.lat, lng: location?.lng, startTime: nil)) ?? []
    }

    func scheduleSearch(immediately: Bool = false) {
        searchTask?.cancel()
        let term = trimmedQuery
        guard !term.isEmpty else {
            results = []
            isSearching = false
            failed = false
            return
        }
        isSearching = true
        let delay = immediately ? .zero : debounce
        searchTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.runSearch(term)
        }
    }

    /// Awaits the in-flight debounced search (tests).
    func waitForSearch() async {
        await searchTask?.value
    }

    func submit() {
        recentSearches = recents.record(trimmedQuery)
        scheduleSearch(immediately: true)
    }

    func selectRecent(_ term: String) {
        query = term
        submit()
    }

    func removeRecent(_ term: String) {
        recentSearches = recents.remove(term)
    }

    func clearRecents() {
        recents.clear()
        recentSearches = []
    }

    /// Remembers the term that led to a result tap.
    func didSelect(_ user: UserModel) {
        recentSearches = recents.record(trimmedQuery)
        Task { await analytics.track("search_result_selected", properties: ["user_id": .string(user.id)]) }
    }

    func subtitle(for user: UserModel) -> String {
        if user.isVenue { return VenueRow.subtitle(user) }
        let occupation = user.occupations.first?.lowercased()
        return [occupation, "@\(user.username.username)"].compactMap(\.self).joined(separator: " · ")
    }

    private func runSearch(_ term: String) async {
        let filters: UserSearchFilters = scope == .venues ? .venues() : .init()
        do {
            let hits = try await search.queryUsers(term, filters: filters)
            guard !Task.isCancelled, term == trimmedQuery else { return }
            results = scope == .performers ? hits.filter { !$0.isVenue } : hits
            failed = false
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            failed = true
        }
        isSearching = false
    }
}
