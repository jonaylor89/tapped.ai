import Foundation
import TappedData
import TappedDomain
import UIKit
import WidgetKit

/// Keeps the "Gig Night" Live Activity and the "Next gig" widget in sync with the performer's confirmed bookings.
/// Runs on sign in and whenever the app becomes active; no server push is needed.
@MainActor
final class GigNightCoordinator {
    static let shared = GigNightCoordinator(
        dependencies: AppEnvironment.dependencies,
        liveActivities: ActivityKitLiveActivityRepository(),
        store: WidgetSnapshotStore(),
        reloadWidgets: { WidgetCenter.shared.reloadAllTimelines() },
        openURL: { AppEnvironment.inbound.open($0) }
    )

    static let nearbyRadius = 50_000
    static let bookingLimit = 25

    private let dependencies: Dependencies
    private let liveActivities: any LiveActivityRepository
    private let store: WidgetSnapshotStore
    private let reloadWidgets: @MainActor () -> Void
    private let openURL: @MainActor (URL) -> Void
    private let now: () -> Date
    private var isStarted = false
    private var pendingRatings: [String: Int] = [:]

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
                if user == nil { clear() } else { await refresh() }
            }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await GigNightCoordinator.shared.refresh() }
        }
    }

    func refresh() async {
        guard let userId = await dependencies.auth.getAuthUser()?.uid else { return }
        let date = now()
        let gigs = await confirmedGigs(userId: userId, now: date)
        let nearby = await nearbyGigCount(userId: userId, now: date)
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
        await refresh()
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
        store.save(WidgetSnapshot(updatedAt: now()))
        reloadWidgets()
        Task { for bookingId in await liveActivities.runningGigNights().keys { await liveActivities.end(bookingId: bookingId) } }
    }

    private func confirmedGigs(userId: String, now: Date) async -> [GigNight] {
        let database = dependencies.database
        let bookings = (try? await database.getBookingsByRequestee(userId, limit: Self.bookingLimit, lastBookingRequestId: nil, status: .confirmed)) ?? []
        var gigs: [GigNight] = []
        for booking in bookings where booking.isConfirmed && booking.endTime.addingTimeInterval(GigNight.reviewWindow) > now {
            var venue: UserModel?
            if let requesterId = booking.requesterId { venue = try? await database.getUserById(requesterId) }
            if let gig = GigNight(booking: booking, venueName: venue?.displayName) { gigs.append(gig) }
        }
        return gigs.sorted { $0.startTime < $1.startTime }
    }

    private func nearbyGigCount(userId: String, now: Date) async -> Int? {
        guard let location = try? await dependencies.database.getUserById(userId)?.location else { return nil }
        let hits = try? await dependencies.search.queryOpportunities(
            "",
            lat: location.lat,
            lng: location.lng,
            radius: Self.nearbyRadius,
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
