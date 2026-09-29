import Foundation
import Observation
import TappedData
import TappedDomain
import TappedUI

enum MapOverlay: String, CaseIterable, Hashable, Sendable {
    case gigs
    case venues

    var systemImage: String {
        switch self {
        case .gigs: "music.mic"
        case .venues: "building.2"
        }
    }
}

/// One-shot camera instruction for `DiscoverMapView`.
struct MapCameraRequest: Equatable {
    enum Kind: Equatable {
        case center(Location, spanDegrees: Double)
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
    /// Free applications granted per day (`credits/{uid}.opportunityQuota` reset).
    static let dailyFreeApplications = 3

    let currentUser: UserModel
    var isPremium: Bool
    let claims: [CustomClaim]

    private(set) var overlay: MapOverlay
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
    /// `nil` for premium users (unlimited applications).
    private(set) var remainingFreeApplications: Int?

    var sheetProgress: CGFloat = 0
    var sheetTop: CGFloat = 0
    var modal: DiscoverModal?
    var isTasksBannerDismissed = false
    private(set) var cameraRequest: MapCameraRequest?

    private var visibleBounds: GeoBounds?
    private let database: any DatabaseRepository
    private let search: any SearchRepository
    private let analytics: any AnalyticsRepository
    private let now: () -> Date

    init(
        dependencies: Dependencies,
        currentUser: UserModel,
        isPremium: Bool,
        claims: [CustomClaim] = [],
        now: @escaping () -> Date = { .now }
    ) {
        self.currentUser = currentUser
        self.isPremium = isPremium
        self.claims = claims
        self.now = now
        overlay = Self.defaultOverlay(for: currentUser, claims: claims)
        database = dependencies.database
        search = dependencies.search
        analytics = dependencies.analytics
    }

    /// Performers look for work first; venue and booker accounts look for venues.
    static func defaultOverlay(for user: UserModel, claims: [CustomClaim]) -> MapOverlay {
        user.isVenue || claims.contains(.booker) ? .venues : .gigs
    }

    /// Performer-first sheet (gigs this week, venues that fit, quota) vs. the venue/booker sheet.
    var isPerformerFirst: Bool { Self.defaultOverlay(for: currentUser, claims: claims) == .gigs }

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

    /// Keeps `remainingFreeApplications` current (applying elsewhere spends quota) until cancelled.
    func observeQuota() async {
        guard !isPremium else {
            remainingFreeApplications = nil
            return
        }
        do {
            for try await quota in database.getUserOpportunityQuotaObserver(currentUser.id) {
                remainingFreeApplications = isPremium ? nil : quota
            }
        } catch {
            remainingFreeApplications = nil
        }
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

    /// "4 open gigs near you".
    var gigsHeadline: String {
        let count = opportunityHits.count
        return "\(count)\(count >= 75 ? "+" : "") open \(count == 1 ? "gig" : "gigs") near you"
    }

    /// Gigs starting between now and the end of the coming weekend (Sunday).
    var gigsThisWeekendCount: Int {
        let calendar = Calendar.current
        let start = now()
        guard let weekend = calendar.nextWeekend(startingAfter: calendar.date(byAdding: .day, value: -1, to: start) ?? start) else { return 0 }
        return opportunityHits.count { $0.startTime >= max(start, weekend.start) && $0.startTime < weekend.end }
    }

    /// "10 venues booking indie pop" (good fits for the performer's first genre), else "10 venues nearby".
    var venuesHeadline: String {
        let fits = goodFitVenues.count
        if fits > 0, let genre = currentUser.performerInfo?.genres.first {
            return "\(fits) \(fits == 1 ? "venue" : "venues") booking \((Genre(rawValue: genre)?.formattedName ?? genre).lowercased())"
        }
        let count = venueHits.count
        return "\(count)\(count >= 75 ? "+" : "") \(count == 1 ? "venue" : "venues") nearby"
    }

    /// Paid gigs in the next seven days, soonest first.
    var paidGigsThisWeek: [Opportunity] {
        let start = now()
        let end = start.addingTimeInterval(7 * 24 * 60 * 60)
        return opportunityHits
            .filter { $0.isPaid && $0.startTime >= start && $0.startTime < end }
            .sorted { $0.startTime < $1.startTime }
    }

    var goodFitVenues: [UserModel] { venueHits.filter(isGoodFit) }

    func venueName(for opportunity: Opportunity) -> String? {
        let venueId = opportunity.venueId ?? opportunity.userId
        return venueHits.first { $0.id == venueId }?.displayName
    }

    /// Shown once the free daily applications are spent.
    var quotaMessage: String? {
        guard !isPremium, isPerformerFirst, remainingFreeApplications == 0 else { return nil }
        let paid = opportunityHits.count(where: \.isPaid)
        let more = paid > 0 ? " — \(paid) more paid \(paid == 1 ? "gig" : "gigs") nearby" : ""
        return "you've used today's \(Self.dailyFreeApplications) free applications\(more)"
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
    private var setupTasks: [SetupTask] {
        TasksViewModel.tasks(
            for: currentUser,
            hasBookings: confirmedBookingsCount > 0,
            contactedVenuesCount: contactedVenuesCount
        )
    }

    var incompleteTaskCount: Int { setupTasks.count { !$0.isCompleted } }

    /// Completed fraction of the setup checklist (progress ring).
    var setupProgress: Double {
        let tasks = setupTasks
        guard !tasks.isEmpty else { return 1 }
        return Double(tasks.count { $0.isCompleted }) / Double(tasks.count)
    }

    var tasksBannerMessage: String? {
        let n = incompleteTaskCount
        guard n > 0, !isTasksBannerDismissed else { return nil }
        return "\(n) \(n == 1 ? "task" : "tasks") left to get booked"
    }

    /// Bookings, settings and city search are tabs now; only bookers keep a shortcut here.
    var quickActions: [QuickAction] {
        guard claims.contains(.admin) || claims.contains(.booker) else { return [] }
        return [QuickAction(title: "add gig", systemImage: "plus", route: .admin, isDestructiveTint: true)]
    }

    var annotations: [DiscoverAnnotationItem] {
        switch overlay {
        case .venues:
            venueHits.compactMap { venue in
                venue.location.map { DiscoverAnnotationItem(id: venue.id, kind: .venue, title: venue.displayName, location: $0) }
            }
        case .gigs:
            opportunityHits.map {
                DiscoverAnnotationItem(id: $0.id, kind: .gig, title: $0.title, location: $0.location)
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
        let capacity = Int(capacityRange.lowerBound)...Int(capacityRange.upperBound)
        let filters = UserSearchFilters.venues(
            genres: genreFilters.map(\.rawValue),
            capacity: capacityRange == 0...Self.capacityLimit ? nil : capacity
        )
        // Both overlays are searched: the sheet header counts gigs and venues whichever is on the map.
        do {
            let startTime = now()
            async let venues = search.queryUsersInBoundingBox("", bounds: bounds, filters: filters)
            async let gigs = search.queryOpportunitiesInBoundingBox("", bounds: bounds, startTime: startTime)
            (venueHits, opportunityHits) = try await (venues, gigs)
            searchedBounds = bounds
            resultsExpired = false
        } catch {
            errorMessage = "couldn't load results"
        }
    }
}
