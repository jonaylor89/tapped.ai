import Foundation
import Testing
@testable import TappedDomain

@Suite("Gig Night + Next gig widget")
struct GigNightTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    static func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    static let format = GigFormat(calendar: calendar, locale: Locale(identifier: "en_US"))
    /// Friday Oct 2 2026, 9 pm – 11 pm at The Camel.
    static let camel = GigNight(bookingId: "b1", venueName: "The Camel", latitude: 37.5511, longitude: -77.457, startTime: date(2, 21), endTime: date(2, 23))

    @Test func phasesFollowTheSet() {
        let gig = Self.camel
        #expect(gig.phase(at: Self.date(2, 18)) == .upcoming)
        #expect(gig.phase(at: Self.date(2, 22)) == .onStage)
        #expect(gig.phase(at: Self.date(3, 1)) == .review)
        #expect(gig.phase(at: Self.date(3, 11, 1)) == .over)
        #expect(gig.staleDate(for: .upcoming) == gig.startTime)
        #expect(gig.staleDate(for: .onStage) == gig.endTime)
        #expect(gig.staleDate(for: .review) == Self.date(3, 11))
        #expect(gig.staleDate(for: .over) == nil)
    }

    @Test func gigNightIsTheDayOfTheSetThroughItsReviewWindow() {
        let gig = Self.camel
        #expect(!gig.isGigNight(at: Self.date(1, 23), calendar: Self.calendar))
        #expect(gig.isGigNight(at: Self.date(2, 9), calendar: Self.calendar))
        #expect(gig.isGigNight(at: Self.date(3, 2), calendar: Self.calendar))
        #expect(!gig.isGigNight(at: Self.date(3, 12), calendar: Self.calendar))
    }

    @Test func gigFromBookingKeepsVenueNameAsTyped() throws {
        var booking = Samples.bookings[0]
        let gig = try #require(GigNight(booking: booking, venueName: "The Camel"))
        #expect(gig.venueName == "The Camel")
        #expect(gig.latitude == booking.location?.lat)
        #expect(GigNight(booking: booking, venueName: nil)?.venueName == booking.name)
        booking.status = .pending
        #expect(GigNight(booking: booking, venueName: "The Camel") == nil)
    }

    @Test func directionsOpenAppleMapsAtTheVenue() throws {
        let url = try #require(Self.camel.directionsURL)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.host == "maps.apple.com")
        #expect(items.first { $0.name == "ll" }?.value == "37.5511,-77.457")
        #expect(items.first { $0.name == "q" }?.value == "The Camel")
        #expect(GigNight(bookingId: "x", venueName: "v", startTime: .now, endTime: .now).directionsURL == nil)
        #expect(Self.camel.bookingURL.absoluteString == "https://app.tapped.ai/booking/b1")
    }

    @Test func syncStartsUpdatesAndEnds() {
        let gig = Self.camel
        let tomorrow = GigNight(bookingId: "b2", venueName: "Canal Club", startTime: Self.date(3, 21), endTime: Self.date(3, 23))
        let morning = Self.date(2, 10)
        #expect(GigNightSync.actions(gigs: [gig, tomorrow], running: [:], dismissed: [], now: morning, calendar: Self.calendar) == [.start(gig, .upcoming)])
        #expect(GigNightSync.actions(gigs: [gig], running: ["b1": .upcoming], dismissed: [], now: morning, calendar: Self.calendar).isEmpty)
        #expect(GigNightSync.actions(gigs: [gig], running: ["b1": .upcoming], dismissed: [], now: Self.date(3, 0), calendar: Self.calendar) == [.update(gig, .review)])
        #expect(GigNightSync.actions(gigs: [gig], running: ["b1": .review], dismissed: ["b1"], now: Self.date(3, 0), calendar: Self.calendar) == [.end(bookingId: "b1")])
        #expect(GigNightSync.actions(gigs: [gig], running: ["b1": .review, "gone": .upcoming], dismissed: [], now: Self.date(3, 12), calendar: Self.calendar) == [.end(bookingId: "b1"), .end(bookingId: "gone")])
    }

    @Test func formatsTheNextGigLine() {
        let format = Self.format
        #expect(format.nextGig(Self.camel, now: Self.date(2, 10).addingTimeInterval(-4 * 86_400)) == "Fri · The Camel · 9 pm")
        #expect(format.nextGig(Self.camel, now: Self.date(2, 10)) == "tonight · The Camel · 9 pm")
        #expect(format.nextGig(Self.camel, now: Self.date(1, 10)) == "tomorrow · The Camel · 9 pm")
        #expect(format.nextGigInline(Self.camel, now: Self.date(2, 10)) == "The Camel · 9 pm")
        #expect(format.nextGigInline(Self.camel, now: Self.date(1, 10)) == "tomorrow · The Camel · 9 pm")
        #expect(format.day(Self.date(2, 13), now: Self.date(2, 9)) == "today")
        #expect(format.time(Self.date(2, 21, 30)) == "9:30 pm")
        #expect(format.setTime(start: Self.camel.startTime, end: Self.camel.endTime) == "9 pm – 11 pm")
        #expect(GigFormat.reviewPrompt("The Camel") == "how was The Camel?")
    }

    @Test(arguments: [(4, "4 new gigs near you"), (1, "1 new gig near you"), (0, "find gigs near you")])
    func formatsNearbyGigs(count: Int, expected: String) {
        #expect(GigFormat.nearbyGigs(count) == expected)
    }

    @Test func countdown() {
        let start = Self.camel.startTime
        #expect(GigFormat.countdown(from: start.addingTimeInterval(-(2 * 3600 + 14 * 60)), to: start) == "2h 14m")
        #expect(GigFormat.countdown(from: start.addingTimeInterval(-14 * 60 + 5), to: start) == "14m")
        #expect(GigFormat.countdown(from: start.addingTimeInterval(-3 * 3600), to: start) == "3h")
        #expect(GigFormat.countdown(from: start.addingTimeInterval(10), to: start) == "now")
    }

    @Test func timelineShowsNextGigThenFallsBackToNearby() {
        let later = GigNight(bookingId: "b2", venueName: "Canal Club", startTime: Self.date(9, 21), endTime: Self.date(9, 23))
        let snapshot = WidgetSnapshot(upcomingGigs: [later, Self.camel], nearbyGigCount: 4)
        let now = Self.date(1, 12)
        let entries = NextGigTimeline.entries(snapshot, now: now)
        #expect(entries == [
            .init(date: now, content: .gig(Self.camel)),
            .init(date: Self.camel.endTime, content: .gig(later)),
            .init(date: later.endTime, content: .nearby(count: 4)),
        ])
        #expect(NextGigTimeline.reloadDate(snapshot, now: now) == later.endTime.addingTimeInterval(60))
        let empty = WidgetSnapshot(nearbyGigCount: 4)
        #expect(NextGigTimeline.entries(empty, now: now) == [.init(date: now, content: .nearby(count: 4))])
        #expect(NextGigTimeline.reloadDate(empty, now: now) == now.addingTimeInterval(NextGigTimeline.refreshInterval))
    }

    @Test func snapshotStoreRoundTrips() throws {
        let suite = "GigNightTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WidgetSnapshotStore(defaults: defaults)
        #expect(store.load() == .empty)
        let snapshot = WidgetSnapshot(upcomingGigs: [Self.camel], nearbyGigCount: 4, updatedAt: Self.date(1, 12))
        store.save(snapshot)
        #expect(store.load() == snapshot)
        store.update { $0.nearbyGigCount = 7 }
        #expect(store.load().nearbyGigCount == 7)
        store.dismissGigNight("b1")
        store.dismissGigNight("b1")
        #expect(store.dismissedGigNights == ["b1"])
    }

    @Test func paidThisWeekendFilter() {
        let now = Self.date(1, 12)
        func gig(_ id: String, day: Int, hour: Int, paid: Bool) -> Opportunity {
            Opportunity(id: id, userId: "v", location: Location(placeId: "p", lat: 0, lng: 0), timestamp: now, startTime: Self.date(day, hour), endTime: Self.date(day, hour + 2), isPaid: paid)
        }
        let opportunities = [
            gig("fri-late", day: 2, hour: 21, paid: true),
            gig("sat-unpaid", day: 3, hour: 20, paid: false),
            gig("sun", day: 4, hour: 18, paid: true),
            gig("thu", day: 1, hour: 20, paid: true),
            gig("next-fri", day: 9, hour: 21, paid: true),
        ]
        let ids = GigFilter.paidThisWeekend.apply(opportunities, now: now, calendar: Self.calendar).map(\.id)
        #expect(ids == ["fri-late", "sun"])
        #expect(GigFilter(paidOnly: true).apply(opportunities, now: now, calendar: Self.calendar).count == 4)
    }
}
