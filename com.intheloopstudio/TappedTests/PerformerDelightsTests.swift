import CoreImage
import Foundation
import TappedData
import TappedDomain
import Testing
import UIKit
@testable import Tapped

@MainActor
@Suite("Performer delights: notification actions, shortcuts links, QR card, Gig Night")
struct PerformerDelightsTests {
    let now = Samples.referenceDate

    private func router(_ database: MockDatabaseRepository, confirmed: @escaping @MainActor (Booking) async -> Void = { _ in }) -> NotificationActionRouter {
        var dependencies = Dependencies.mock(signedIn: true)
        dependencies.database = database
        return NotificationActionRouter(dependencies: dependencies, now: { now }, onBookingConfirmed: confirmed)
    }

    private func response(_ action: String, category: String = NotificationCategories.bookingRequest, _ userInfo: [AnyHashable: Any], text: String? = nil) -> NotificationActionResponse {
        NotificationActionResponse(categoryIdentifier: category, actionIdentifier: action, userInfo: userInfo, text: text)
    }

    // MARK: notification actions

    @Test func registersBookingAndGigCategories() {
        let categories = NotificationCategories.make(applyOpensApp: false)
        let byId = Dictionary(uniqueKeysWithValues: categories.map { ($0.identifier, $0) })
        #expect(byId["NEW_GIG"]?.actions.map(\.title) == ["Apply"])
        #expect(byId["BOOKING_REQUEST"]?.actions.map(\.title) == ["Accept", "Decline", "Reply"])
        #expect(byId["BOOKING_REQUEST"]?.actions.last is UNTextInputNotificationAction)
        #expect(byId["NEW_GIG"]?.actions.first?.options.contains(.foreground) == false)
        let paywalled = NotificationCategories.make(applyOpensApp: true).first { $0.identifier == "NEW_GIG" }
        #expect(paywalled?.actions.first?.options.contains(.foreground) == true)
    }

    @Test func acceptConfirmsThePendingBooking() async throws {
        let database = MockDatabaseRepository()
        var confirmed: [String] = []
        let outcome = await router(database) { confirmed.append($0.id) }.handle(response("ACCEPT", ["bookingId": "booking-2"]))
        #expect(outcome == .bookingUpdated(bookingId: "booking-2", status: .confirmed))
        #expect(try await database.getBookingById("booking-2")?.status == .confirmed)
        #expect(confirmed == ["booking-2"])
    }

    @Test func declineCancelsAndUsesTheExistingUrlKey() async throws {
        let database = MockDatabaseRepository()
        let outcome = await router(database).handle(response("DECLINE", ["url": "https://app.tapped.ai/booking/booking-2"]))
        #expect(outcome == .bookingUpdated(bookingId: "booking-2", status: .canceled))
        #expect(try await database.getBookingById("booking-2")?.status == .canceled)
    }

    @Test func acceptRejectsBookingsThatAreNotMineOrNotPending() async {
        let database = MockDatabaseRepository()
        let router = router(database)
        #expect(await router.handle(response("ACCEPT", ["bookingId": "booking-1"])) == .failed(NotificationPayload(link: .booking(bookingId: "booking-1"))))
        #expect(await router.handle(response("ACCEPT", ["bookingId": "missing"])) == .failed(NotificationPayload(link: .booking(bookingId: "missing"))))
    }

    @Test func replyMessagesTheBooker() async {
        let router = router(MockDatabaseRepository())
        let outcome = await router.handle(response("REPLY", ["bookingId": "booking-2"], text: "  we're in!  "))
        guard case .replied = outcome else { Issue.record("expected reply, got \(outcome)"); return }
        #expect(await router.handle(response("REPLY", ["bookingId": "booking-2"], text: "   ")) == .failed(NotificationPayload(link: .booking(bookingId: "booking-2"))))
    }

    @Test func applyReusesOpportunityApplication() async throws {
        let database = MockDatabaseRepository()
        let opportunityId = try #require(Samples.opportunities.first { $0.endTime > .now }?.id)
        let outcome = await router(database).handle(response("APPLY", category: NotificationCategories.newGig, ["opportunityId": opportunityId]))
        #expect(outcome == .applied(opportunityId: opportunityId))
        #expect(try await database.isUserAppliedForOpportunity(opportunityId: opportunityId, userId: Samples.performer.id))
    }

    @Test func applyWithoutQuotaNeedsThePaywall() async throws {
        let database = MockDatabaseRepository(defaultOpportunityQuota: 0)
        let opportunityId = try #require(Samples.opportunities.first { $0.endTime > .now }?.id)
        let outcome = await router(database).handle(response("APPLY", category: NotificationCategories.newGig, ["opportunityId": opportunityId]))
        #expect(outcome == .needsPremium(opportunityId: opportunityId))
    }

    @Test func plainTapsAndMismatchedPayloadsAreNotActions() async {
        let router = router(MockDatabaseRepository())
        let tap = response(UNNotificationDefaultActionIdentifier, ["bookingId": "booking-2"])
        #expect(!tap.isAction)
        #expect(await router.handle(tap) == .unhandled)
        #expect(await router.handle(response("APPLY", ["bookingId": "booking-2"])) == .failed(NotificationPayload(link: .booking(bookingId: "booking-2"))))
    }

    // MARK: shortcut links

    @Test func shortcutLinksParseOnTheCustomSchemeOnly() throws {
        #expect(DeepLink(url: FindPaidGigsIntent.url) == .gigs(.paidThisWeekend))
        #expect(DeepLink(url: try #require(URL(string: "com.intheloopstudio://gigs"))) == .gigs(nil))
        #expect(DeepLink(url: ShareProfileIntent.url) == .shareProfile(showsQR: true))
        #expect(DeepLink(url: try #require(URL(string: "https://app.tapped.ai/gigs"))) == .profile(username: "gigs"))
    }

    @Test func gigsLinkResolvesToFilteredFeed() async {
        let resolver = DeepLinkResolver(database: MockDatabaseRepository())
        let feed = await resolver.resolve(.gigs(nil), currentUser: Samples.performer)
        #expect(feed.route == .opportunityFeed)
        let share = await resolver.resolve(.shareProfile(showsQR: true), currentUser: Samples.performer)
        #expect(share.route == .shareProfile(userId: Samples.performer.id, user: Samples.performer))
        #expect(ShareProfileQRRequest.take())
        #expect(!ShareProfileQRRequest.take())
    }

    // MARK: QR card

    @Test func qrCodeEncodesThePublicProfileURL() throws {
        let url = Samples.performer.profileURL
        let qr = try #require(ShareProfileCardRenderer.qrCode(for: url))
        #expect(qr.width == qr.height)
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let padded = CIImage(cgImage: qr).composited(over: CIImage(color: .white).cropped(to: CGRect(x: -40, y: -40, width: qr.width + 80, height: qr.height + 80)))
        let messages = detector.features(in: padded).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        #expect(messages == [url.absoluteString])
    }

    @Test func cardRendersToAnImage() async {
        let model = ShareProfileViewModel(dependencies: .mock(signedIn: true), userId: Samples.performer.id, user: Samples.performer) { _ in nil }
        await model.load()
        #expect(model.qrCode != nil)
        #expect(model.cardImage != nil)
        #expect(!model.showsFullScreenQR)
        ShareProfileQRRequest.isPending = true
        await model.load()
        #expect(model.showsFullScreenQR)
    }

    // MARK: Gig Night

    @Test func coordinatorStartsReviewsAndRates() async throws {
        let suite = "PerformerDelightsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let activities = MockLiveActivityRepository()
        var opened: [URL] = []
        let date = Date.now
        let coordinator = GigNightCoordinator(
            dependencies: .mock(signedIn: true),
            liveActivities: activities,
            store: WidgetSnapshotStore(defaults: defaults),
            openURL: { opened.append($0) },
            now: { date }
        )
        let gig = GigNight(bookingId: "b1", venueName: "The Camel", startTime: date.addingTimeInterval(60), endTime: date.addingTimeInterval(3600))
        await coordinator.syncLiveActivities([gig], now: date)
        #expect(await activities.runningGigNights() == ["b1": .upcoming])
        await coordinator.syncLiveActivities([gig], now: date.addingTimeInterval(4000))
        #expect(await activities.runningGigNights() == ["b1": .review])

        coordinator.rate(bookingId: "b1", rating: 9)
        #expect(opened.map(\.absoluteString) == ["https://app.tapped.ai/booking/b1"])
        #expect(coordinator.takePendingRating(for: "b1") == 5)
        #expect(coordinator.takePendingRating(for: "b1") == nil)

        await coordinator.reviewed(bookingId: "b1")
        #expect(await activities.ended == ["b1"])
        await coordinator.syncLiveActivities([gig], now: date.addingTimeInterval(4000))
        #expect(await activities.runningGigNights().isEmpty)
    }

    @Test func refreshWritesTheWidgetSnapshot() async throws {
        let suite = "PerformerDelightsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var reloads = 0
        let store = WidgetSnapshotStore(defaults: defaults)
        let coordinator = GigNightCoordinator(
            dependencies: .mock(signedIn: true),
            liveActivities: MockLiveActivityRepository(),
            store: store,
            reloadWidgets: { reloads += 1 },
            now: { now }
        )
        await coordinator.refresh()
        let snapshot = store.load()
        #expect(reloads == 1)
        #expect(snapshot.upcomingGigs.map(\.bookingId) == ["booking-1"])
        #expect(snapshot.upcomingGigs.first?.venueName == Samples.venues.first { $0.id == "venue-camel" }?.displayName)
        #expect(snapshot.nearbyGigCount != nil)
    }

    @Test func foregroundRefreshIsThrottledUnlessForced() async throws {
        let suite = "PerformerDelightsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var reloads = 0
        var date = Samples.referenceDate
        let coordinator = GigNightCoordinator(
            dependencies: .mock(signedIn: true),
            liveActivities: MockLiveActivityRepository(),
            store: WidgetSnapshotStore(defaults: defaults),
            reloadWidgets: { reloads += 1 },
            now: { date }
        )
        async let first: Void = coordinator.refresh()
        async let overlapping: Void = coordinator.refresh()
        _ = await (first, overlapping)
        #expect(reloads == 1)

        date.addTimeInterval(5 * 60)
        await coordinator.refresh()
        #expect(reloads == 1)

        let booking = try #require(Samples.bookings.first { $0.isConfirmed })
        await coordinator.bookingConfirmed(booking)
        #expect(reloads == 2)

        date.addTimeInterval(GigNightCoordinator.refreshInterval)
        await coordinator.refresh()
        #expect(reloads == 3)
    }
}
