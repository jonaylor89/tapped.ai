import Foundation

/// Most-recent-first search terms persisted in `UserDefaults` (Flutter's `lastRememberedSearchTerm`, kept as a list).
struct RecentSearches {
    static let key = "tapped.recentSearches"
    static let limit = 8

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var terms: [String] { defaults.stringArray(forKey: Self.key) ?? [] }

    @discardableResult
    func record(_ term: String) -> [String] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return terms }
        let updated = Array(([trimmed] + terms.filter { $0 != trimmed }).prefix(Self.limit))
        defaults.set(updated, forKey: Self.key)
        return updated
    }

    @discardableResult
    func remove(_ term: String) -> [String] {
        let updated = terms.filter { $0 != term }
        defaults.set(updated, forKey: Self.key)
        return updated
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
