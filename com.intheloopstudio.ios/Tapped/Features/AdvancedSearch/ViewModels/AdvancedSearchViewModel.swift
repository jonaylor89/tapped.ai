import Foundation
import Observation
import TappedData
import TappedDomain

/// Port of `advanced_search_view.dart` + the filter half of `SearchBloc`.
@Observable
@MainActor
final class AdvancedSearchViewModel {
    static let capacityLimit = 1000.0
    static let radiusOptions = [10, 25, 50, 100, 250]
    static let metersPerMile = 1609.344

    var occupations: Set<Occupation> = []
    var genres: Set<Genre> = []
    var labels: Set<Label> = []
    var place: PlaceData?
    var radiusMiles = 50
    var minCapacity = 0.0
    var maxCapacity = AdvancedSearchViewModel.capacityLimit

    private(set) var results: [UserModel] = []
    private(set) var isSearching = false
    private(set) var failed = false

    private let search: any SearchRepository
    private let analytics: any AnalyticsRepository

    init(dependencies: Dependencies) {
        search = dependencies.search
        analytics = dependencies.analytics
    }

    /// Capacity only applies to venues, and venue genres live on `venueInfo`.
    var isVenueSearch: Bool { occupations == [.venue] }

    var hasFilters: Bool {
        !occupations.isEmpty || !genres.isEmpty || !labels.isEmpty || place != nil
            || minCapacity > 0 || maxCapacity < Self.capacityLimit
    }

    var radiusMeters: Int { Int(Double(radiusMiles) * Self.metersPerMile) }

    var filters: UserSearchFilters {
        let genreNames = genres.map(\.rawValue).sorted()
        let occupationNames = occupations.map(\.rawValue).sorted()
        return UserSearchFilters(
            labels: labels.isEmpty ? nil : labels.map(\.rawValue).sorted(),
            genres: isVenueSearch || genreNames.isEmpty ? nil : genreNames,
            venueGenres: isVenueSearch && !genreNames.isEmpty ? genreNames : nil,
            occupations: occupationNames.isEmpty ? nil : (isVenueSearch ? ["Venue", "venue"] : occupationNames),
            minCapacity: isVenueSearch && minCapacity > 0 ? Int(minCapacity) : nil,
            // Mirrors gig search: the slider's max means "and up".
            maxCapacity: isVenueSearch && maxCapacity < Self.capacityLimit ? Int(maxCapacity) : nil
        )
    }

    func clear() {
        occupations = []
        genres = []
        labels = []
        place = nil
        radiusMiles = 50
        minCapacity = 0
        maxCapacity = Self.capacityLimit
        results = []
    }

    func runSearch() async {
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await search.queryUsers("", filters: filters, lat: place?.lat, lng: place?.lng, radius: radiusMeters, limit: 50)
            failed = false
        } catch {
            results = []
            failed = true
        }
        await analytics.track("advanced_search", properties: ["result_count": .int(results.count)])
    }
}
