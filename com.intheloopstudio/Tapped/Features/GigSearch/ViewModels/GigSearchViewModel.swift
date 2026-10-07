import Foundation
import Observation
import TappedData
import TappedDomain

/// Port of `GigSearchCubit` + `venue_fit_utils.dart`: search venues in a city by genre and capacity,
/// sort good fits first, pick the ones to reach out to.
@Observable
@MainActor
final class GigSearchViewModel {
    static let capacityLimit = 1000.0
    /// Dart: `capacityRangeEnd == maxCapacity ? 100000 : capacityRangeEnd`.
    static let unboundedCapacity = 100_000

    enum SearchOutcome: Equatable {
        case results
        case needsPremium
        case invalid(String)
    }

    let currentUser: UserModel
    var isPremium: Bool

    var place: PlaceData?
    var genres: Set<Genre>
    var minCapacity = 0.0
    var maxCapacity: Double

    private(set) var results: [UserModel] = []
    private(set) var fits: [String: VenueFit] = [:]
    var selectedIds: Set<String> = []
    private(set) var isSearching = false
    private(set) var failed = false

    private let search: any SearchRepository
    private let places: any PlacesRepository
    private let analytics: any AnalyticsRepository

    init(dependencies: Dependencies, currentUser: UserModel, isPremium: Bool) {
        self.currentUser = currentUser
        self.isPremium = isPremium
        search = dependencies.search
        places = dependencies.places
        analytics = dependencies.analytics
        let performer = currentUser.performerInfo
        genres = Set((performer?.genres ?? []).compactMap(Genre.init(rawValue:)))
        maxCapacity = min(Double(performer?.category.suggestedMaxCapacity ?? Int(Self.capacityLimit)), Self.capacityLimit)
    }

    var canSearch: Bool { place != nil && !genres.isEmpty }
    var selectedVenues: [UserModel] { results.filter { selectedIds.contains($0.id) } }
    var allSelected: Bool { !results.isEmpty && selectedIds.count == results.count }

    /// `initPlace`: resolve the user's saved location.
    func loadInitialPlace() async {
        guard place == nil, let location = currentUser.location else { return }
        place = try? await places.getPlaceById(location.placeId)
    }

    func capacityBounds() -> ClosedRange<Int> {
        let upper = maxCapacity >= Self.capacityLimit ? Self.unboundedCapacity : Int(maxCapacity)
        return Int(minCapacity)...max(upper, Int(minCapacity))
    }

    func searchVenues() async -> SearchOutcome {
        guard isPremium else { return .needsPremium }
        guard !genres.isEmpty else { return .invalid("please select at least one genre") }
        guard let place else { return .invalid("please select a city") }
        isSearching = true
        defer { isSearching = false }
        do {
            let hits = try await search.queryUsers(
                "",
                filters: .venues(genres: genres.map(\.rawValue).sorted(), capacity: capacityBounds()),
                lat: place.lat,
                lng: place.lng,
                radius: 50_000,
                limit: 150
            )
            // Hits carry `venueInfo`, so they're used as-is; profiles re-read the venue when opened.
            let performer = currentUser.performerInfo
            results = VenueFit.sorted(hits, for: performer)
            fits = Dictionary(uniqueKeysWithValues: results.map { ($0.id, VenueFit(venue: $0, performer: performer)) })
            selectedIds = []
            failed = false
        } catch {
            results = []
            failed = true
        }
        await analytics.track("gig_search", properties: ["result_count": .int(results.count)])
        return .results
    }

    func fit(for venue: UserModel) -> VenueFit {
        fits[venue.id] ?? VenueFit(venue: venue, performer: currentUser.performerInfo)
    }

    func subtitle(for venue: UserModel) -> String {
        let shared = fit(for: venue).sharedGenres
        let base = VenueRow.subtitle(venue)
        return shared.isEmpty ? base : "\(base) · \(shared.count) shared \(shared.count == 1 ? "genre" : "genres")"
    }

    func toggle(_ venue: UserModel) {
        if selectedIds.contains(venue.id) { selectedIds.remove(venue.id) } else { selectedIds.insert(venue.id) }
    }

    func selectAll(_ selected: Bool) {
        selectedIds = selected ? Set(results.map(\.id)) : []
    }
}
