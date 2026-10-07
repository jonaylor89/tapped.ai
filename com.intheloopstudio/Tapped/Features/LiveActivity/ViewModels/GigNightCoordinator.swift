import Foundation
import TappedData
import TappedDomain
import UIKit
import WidgetKit

/// Keeps the "Gig Night" Live Activity and the "Next gig" widget in sync with the performer's confirmed bookings.
/// Runs on sign in and when the app becomes active (at most every `refreshInterval`); no server push is needed.
@MainActor
final class GigNightCoordinator {
    static let shared = GigNightCoordinator(
        dependencies: AppEnvironment.dependencies,
        liveActivities: ActivityKitLiveActivityRepository(),
        store: WidgetSnapshotStore(),
        reloadWidgets: { WidgetCenter.shared.reloadAllTimelines() },
        openURL: { AppEnvironment.inbound.open($0) }
    )

    nonisolated static let nearbyRadius = 50_000
    nonisolated static let bookingLimit = 25
    /// Foregrounding refreshes at most this often; sign in and confirmed bookings always refresh.
    static let refreshInterval: TimeInterval = 15 * 60

    private let dependencies: Dependencies
    private let liveActivities: any LiveActivityRepository
    private let store: WidgetSnapshotStore
    private let reloadWidgets: @MainActor () -> Void
    private let openURL: @MainActor (URL) -> Void
    private let now: () -> Date
    private var isStarted = false
    private var pendingRatings: [String: Int] = [:]
    private var lastRefresh: Date?
    private var inFlight: Task<Void, Never>?

    init(
        dependencies: Dependencies,
        liveActivities: any LiveActivityRepository,
        store: WidgetSnapshotStore,
        reloadWidgets: @escaping @MainActor () -> Void = {},
        openURL: @escaping @MainActor (URL) -> Void = { _ in },
        now: @escaping () -> Date = { .now }
    ) {
        self.dependencies = dependencies
        self.liveActivities = liveActivities
        self.store = store
        self.reloadWidgets = reloadWidgets
        self.openURL = openURL
        self.now = now
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        Task {
            #if DEBUG
            await seedMockGigNight()
            #endif
            for await user in dependencies.auth.authStateChanges() {
                if user == nil { clear() } else { await refresh(force: true) }
            }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await GigNightCoordinator.shared.refresh() }
        }
    }

    /// Throttled to `refreshInterval` unless `force`d; overlapping calls share the run in flight.
    func refresh(force: Bool = false) async {
        if let running = inFlight {
            await running.value
            guard force else { return }
            if let rerun = inFlight {
                await rerun.value
                return
            }
        }
        if !force, let lastRefresh, now().timeIntervalSince(lastRefresh) < Self.refreshInterval { return }
        let run = Task { await performRefresh() }
        inFlight = run
        await run.value
        if inFlight == run { inFlight = nil }
    }

    private func performRefresh() async {
        guard let userId = await dependencies.auth.getAuthUser()?.uid else { return }
        let date = now()
        lastRefresh = date
        let database = dependencies.database
        let search = dependencies.search
        async let confirmed = Self.confirmedGigs(database: database, userId: userId, now: date)
        async let nearbyCount = Self.nearbyGigCount(database: database, search: search, userId: userId, now: date)
        let (gigs, nearby) = await (confirmed, nearbyCount)
        store.update { snapshot in
            snapshot.upcomingGigs = Array(gigs.filter { $0.endTime > date }.prefix(NextGigTimeline.maxEntries))
            snapshot.nearbyGigCount = nearby ?? snapshot.nearbyGigCount
            snapshot.updatedAt = date
        }
        reloadWidgets()
        await syncLiveActivities(gigs, now: date)
    }

    /// Called when the performer accepts a booking (booking detail or the notification action).
    func bookingConfirmed(_ booking: Booking) async {
        guard booking.isConfirmed else { return }
        await refresh(force: true)
    }

    /// Ends the activity once the performer has reviewed the gig; it isn't restarted.
    func reviewed(bookingId: String) async {
        store.dismissGigNight(bookingId)
        pendingRatings[bookingId] = nil
        await liveActivities.end(bookingId: bookingId)
    }

    /// A star tapped in the post-set prompt: open the booking so its review sheet can start from `rating`.
    func rate(bookingId: String, rating: Int) {
        pendingRatings[bookingId] = min(max(rating, 1), 5)
        guard let url = URL(string: "https://app.tapped.ai/booking/\(bookingId)") else { return }
        openURL(url)
    }

    func takePendingRating(for bookingId: String) -> Int? {
        pendingRatings.removeValue(forKey: bookingId)
    }

    func syncLiveActivities(_ gigs: [GigNight], now: Date) async {
        guard await liveActivities.areActivitiesEnabled() else { return }
        let running = await liveActivities.runningGigNights()
        let actions = GigNightSync.actions(gigs: gigs, running: running, dismissed: store.dismissedGigNights, now: now)
        for action in actions {
            switch action {
            case let .start(gig, phase):
                do {
                    try await liveActivities.start(gig, phase: phase)
                } catch {
                    FirebaseBootstrap.record(error: error)
                }
            case let .update(gig, phase):
                await liveActivities.update(gig, phase: phase)
            case let .end(bookingId):
                await liveActivities.end(bookingId: bookingId)
            }
        }
    }

    private func clear() {
        lastRefresh = nil
        store.save(WidgetSnapshot(updatedAt: now()))
        reloadWidgets()
        Task { for bookingId in await liveActivities.runningGigNights().keys { await liveActivities.end(bookingId: bookingId) } }
    }

    /// Venue names are read in parallel, once per venue.
    nonisolated static func confirmedGigs(database: any DatabaseRepository, userId: String, now: Date) async -> [GigNight] {
        let bookings = ((try? await database.getBookingsByRequestee(userId, limit: bookingLimit, lastBookingRequestId: nil, status: .confirmed)) ?? [])
            .filter { $0.isConfirmed && $0.endTime.addingTimeInterval(GigNight.reviewWindow) > now }
        let venueNames = await withTaskGroup(of: (String, String?).self) { group in
            for venueId in Set(bookings.compactMap(\.requesterId)) {
                group.addTask { (venueId, try? await database.getUserById(venueId)?.displayName) }
            }
            var names: [String: String] = [:]
            for await (venueId, name) in group {
                names[venueId] = name
            }
            return names
        }
        return bookings
            .compactMap { GigNight(booking: $0, venueName: $0.requesterId.flatMap { venueNames[$0] }) }
            .sorted { $0.startTime < $1.startTime }
    }

    nonisolated static func nearbyGigCount(database: any DatabaseRepository, search: any SearchRepository, userId: String, now: Date) async -> Int? {
        guard let location = try? await database.getUserById(userId)?.location else { return nil }
        let hits = try? await search.queryOpportunities(
            "",
            lat: location.lat,
            lng: location.lng,
            radius: nearbyRadius,
            startTime: now
        )
        return hits?.filter { !$0.deleted && $0.startTime > now }.count
    }

    #if DEBUG
    /// `TAPPED_MOCK_GIG_NIGHT=upcoming|onstage|review` adds a confirmed booking at The Camel today for screenshots.
    private func seedMockGigNight() async {
        guard dependencies.mode == .mock,
              let phase = ProcessInfo.processInfo.environment["TAPPED_MOCK_GIG_NIGHT"],
              let userId = await dependencies.auth.getAuthUser()?.uid else { return }
        let date = now()
        let hour: TimeInterval = 60 * 60
        let start: Date = switch phase {
        case "onstage": date.addingTimeInterval(-0.5 * hour)
        case "review": date.addingTimeInterval(-3 * hour)
        default: date.addingTimeInterval(2 * hour + 14 * 60)
        }
        let venue = Samples.venues[0]
        try? await dependencies.database.createBooking(Booking(
            id: "gig-night",
            requesteeId: userId,
            status: .confirmed,
            startTime: start,
            endTime: start.addingTimeInterval(2 * hour),
            timestamp: date,
            requesterId: venue.id,
            name: "Camel Sessions",
            rate: 25_000,
            location: venue.location
        ))
    }
    #endif
}
