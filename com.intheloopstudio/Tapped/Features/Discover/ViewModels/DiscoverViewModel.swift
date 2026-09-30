import Foundation
import Observation
import TappedData
import TappedDomain
import TappedUI

enum MapOverlay: String, CaseIterable, Hashable, Sendable {
    case venues
    case gigs

    var systemImage: String {
        switch self {
        case .venues: "building.2.fill"
        case .gigs: "music.mic"
        }
    }
}

/// One-shot camera instruction for `DiscoverMapView`.
struct MapCameraRequest: Equatable {
    enum Kind: Equatable {
        case center(Location, spanDegrees: Double)
        case zoom(factor: Double)
    }

    let id = UUID()
    let kind: Kind
}

struct QuickAction: Identifiable, Equatable {
    let title: String
    let systemImage: String
    let route: Route
    var isDestructiveTint = false

    var id: String { title }
}

enum DiscoverModal: String, Identifiable {
    case filters
    case allResults

    var id: String { rawValue }
}

/// Port of `DiscoverCubit` + `DiscoverState`.
@Observable
@MainActor
final class DiscoverViewModel {
    static let defaultSpanDegrees = 0.12
    static let capacityLimit = 1000.0

    let currentUser: UserModel
    var isPremium: Bool
    let claims: [CustomClaim]

    private(set) var overlay: MapOverlay = .venues
    private(set) var venueHits: [UserModel] = []
    private(set) var opportunityHits: [Opportunity] = []
    private(set) var featuredPerformers: [UserModel] = []
    private(set) var featuredOpportunities: [Opportunity] = []
    private(set) var genreFilters: [Genre] = []
    private(set) var capacityRange: ClosedRange<Double> = 0...capacityLimit
    private(set) var resultsExpired = false
    private(set) var isSearching = false
    private(set) var errorMessage: String?
    private(set) var contactedVenuesCount = 1
    private(set) var confirmedBookingsCount = 0
    private(set) var searchedBounds: GeoBounds?

    var sheetDetent: MapsSheetDetent
    var sheetProgress: CGFloat = 0
    var sheetTop: CGFloat = 0
    var modal: DiscoverModal?
    var isTasksBannerDismissed = false
    private(set) var cameraRequest: MapCameraRequest?

    private var visibleBounds: GeoBounds?
    private let database: any DatabaseRepository
    private let search: any SearchRepository
    private let analytics: any AnalyticsRepository

    init(
        dependencies: Dependencies,
        currentUser: UserModel,
        isPremium: Bool,
        claims: [CustomClaim] = [],
        initialDetent: MapsSheetDetent = .collapsed
    ) {
        self.currentUser = currentUser
        self.isPremium = isPremium
        self.claims = claims
        sheetDetent = initialDetent
        database = dependencies.database
        search = dependencies.search
        analytics = dependencies.analytics
    }

    /// Profile location, falling back to Flutter's `DiscoverState` default (Richmond, VA).
    var home: Location { currentUser.location ?? .rva }

    // MARK: Loading

    func load() async {
        async let performers = try? database.getFeaturedPerformers()
        async let opportunities = try? database.getFeaturedOpportunities()
        async let contacted = try? database.getContactedVenues(currentUser.id)
        async let requesteeBookings = try? database.getBookingsByRequestee(currentUser.id, status: .confirmed)
        async let requesterBookings = try? database.getBookingsByRequester(currentUser.id, status: .confirmed)

        featuredPerformers = await performers ?? []
        featuredOpportunities = await opportunities ?? []
        contactedVenuesCount = await contacted?.count ?? 1
        confirmedBookingsCount = (await requesteeBookings?.count ?? 0) + (await requesterBookings?.count ?? 0)
    }

    // MARK: Map

    func mapRegionChanged(to bounds: GeoBounds) async {
        visibleBounds = bounds
        guard let searchedBounds else {
            await runSearch(in: bounds)
            return
        }
        resultsExpired = bounds != searchedBounds
    }

    func searchThisArea() async {
        guard let visibleBounds else { return }
        await analytics.track("discover_search_this_area")
        await runSearch(in: visibleBounds)
    }

    func select(_ overlay: MapOverlay) async {
        guard overlay != self.overlay else { return }
        self.overlay = overlay
        await analytics.track("discover_overlay_change", properties: ["overlay": .string(overlay.rawValue)])
        if let bounds = visibleBounds ?? searchedBounds { await runSearch(in: bounds) }
    }

    func locate() {
        cameraRequest = MapCameraRequest(kind: .center(home, spanDegrees: Self.defaultSpanDegrees))
        Task { await analytics.track("discover_seek_home") }
    }

    func zoom(by factor: Double) {
        cameraRequest = MapCameraRequest(kind: .zoom(factor: factor))
    }

    // MARK: Filters (premium-gated like Flutter)

    /// Returns `false` when the user must see the paywall instead.
    @discardableResult
    func applyFilters(genres: [Genre], capacity: ClosedRange<Double>) async -> Bool {
        guard isPremium else { return false }
        genreFilters = genres
        capacityRange = capacity
        if let bounds = visibleBounds ?? searchedBounds { await runSearch(in: bounds) }
        return true
    }

    func clearFilters() async {
        await applyFilters(genres: [], capacity: 0...Self.capacityLimit)
    }

    // MARK: Derived state

    /// `SheetHandle._countLabel` + " nearby".
    var headerTitle: String {
        let count = overlay == .venues ? venueHits.count : opportunityHits.count
        let noun = switch overlay {
        case .venues: count == 1 ? "venue" : "venues"
        case .gigs: count == 1 ? "gig" : "gigs"
        }
        return "\(count)\(count >= 75 ? "+" : "") \(noun) nearby"
    }

    var genreFilterLabel: String? {
        guard !genreFilters.isEmpty else { return nil }
        return "\(genreFilters.count) \(genreFilters.count == 1 ? "genre" : "genres")"
    }

    /// `DiscoverState.genreCounts`: lowercased venue genres by frequency.
    var genreCounts: [(genre: String, count: Int)] {
        var counts: [String: Int] = [:]
        for genre in venueHits.flatMap({ $0.venueInfo?.genres ?? [] }) {
            counts[genre.lowercased(), default: 0] += 1
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count == $1.count ? $0.genre < $1.genre : $0.count > $1.count }
    }

    /// `sortVenuesByFit`: good fits first, stable otherwise.
    var sortedVenueHits: [UserModel] {
        venueHits.enumerated()
            .sorted { lhs, rhs in
                let l = isGoodFit(lhs.element), r = isGoodFit(rhs.element)
                return l == r ? lhs.offset < rhs.offset : l
            }
            .map(\.element)
    }

    /// `isVenueGoodFit`: capacity within the performer category's suggested max and at least one shared genre.
    func isGoodFit(_ venue: UserModel) -> Bool {
        guard let performer = currentUser.performerInfo,
              let venueInfo = venue.venueInfo,
              let capacity = venueInfo.capacity
        else { return false }
        let venueGenres = Set(venueInfo.genres.map { $0.lowercased() })
        let userGenres = Set(performer.genres.map { $0.lowercased() })
        return performer.category.suggestedMaxCapacity >= capacity && !venueGenres.isDisjoint(with: userGenres)
    }

    /// `TasksBanner`: the same five checklist items as the tasks screen.
    var incompleteTaskCount: Int {
        TasksViewModel.tasks(
            for: currentUser,
            hasBookings: confirmedBookingsCount > 0,
            contactedVenuesCount: contactedVenuesCount
        ).filter { !$0.isCompleted }.count
    }

    var tasksBannerMessage: String? {
        let n = incompleteTaskCount
        guard n > 0, !isTasksBannerDismissed else { return nil }
        return "\(n) \(n == 1 ? "task" : "tasks") left to get booked"
    }

    var quickActions: [QuickAction] {
        var actions = [
            QuickAction(title: "search a city", systemImage: "map.fill", route: .gigSearch),
            QuickAction(title: "my bookings", systemImage: "calendar", route: .bookings(userId: currentUser.id)),
            QuickAction(title: "settings", systemImage: "person.crop.circle", route: .settings),
        ]
        if claims.contains(.admin) || claims.contains(.booker) {
            actions.append(QuickAction(title: "add gig", systemImage: "plus", route: .admin, isDestructiveTint: true))
        }
        return actions
    }

    var annotations: [DiscoverAnnotationItem] {
        switch overlay {
        case .venues:
            venueHits.compactMap { venue in
                venue.location.map { DiscoverAnnotationItem(id: venue.id, kind: .venue, title: venue.displayName.lowercased(), location: $0) }
            }
        case .gigs:
            opportunityHits.map {
                DiscoverAnnotationItem(id: $0.id, kind: .gig, title: $0.title.lowercased(), location: $0.location)
            }
        }
    }

    func route(forAnnotation id: String) -> Route? {
        if let venue = venueHits.first(where: { $0.id == id }) { return .profile(userId: venue.id, user: venue) }
        if let gig = opportunityHits.first(where: { $0.id == id }) { return .opportunity(opportunityId: gig.id, opportunity: gig) }
        return nil
    }

    // MARK: Private

    private func runSearch(in bounds: GeoBounds) async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            switch overlay {
            case .venues:
                let capacity = Int(capacityRange.lowerBound)...Int(capacityRange.upperBound)
                let filters = UserSearchFilters.venues(
                    genres: genreFilters.map(\.rawValue),
                    capacity: capacityRange == 0...Self.capacityLimit ? nil : capacity
                )
                venueHits = try await search.queryUsersInBoundingBox("", bounds: bounds, filters: filters)
            case .gigs:
                opportunityHits = try await search.queryOpportunitiesInBoundingBox("", bounds: bounds, startTime: .now)
            }
            searchedBounds = bounds
            resultsExpired = false
        } catch {
            errorMessage = "couldn't load results"
        }
    }
}
