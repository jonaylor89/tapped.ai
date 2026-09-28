import Foundation
import Testing
@testable import TappedDomain

@Suite("Firestore model decoding")
struct ModelDecodingTests {
    @Test func booking() throws {
        let booking = try Fixture.decode(Booking.self, "booking")
        #expect(booking.status == .confirmed)
        #expect(booking.endTime.timeIntervalSince(booking.startTime) == 7200)
        #expect(booking.timestamp == Date(timeIntervalSince1970: 1_719_835_200))
        #expect(booking.note.isEmpty)
        #expect(booking.verified == false)
        #expect(booking.requesterId == "venue-1")
        #expect(booking.rate == 25_000)
    }

    @Test func opportunity() throws {
        let op = try Fixture.decode(Opportunity.self, "opportunity")
        #expect(op.title == "friday night openers")
        #expect(op.deadline == nil)
        #expect(op.touched == .like)
        #expect(op.isPaid)
        #expect(op.description.isEmpty)
        #expect(op.timestamp == Date(timeIntervalSince1970: 1_720_000_000))
    }

    @Test func activityVariants() throws {
        let activities = try Fixture.decode([Activity].self, "activities")
        #expect(activities.map(\.type) == [.follow, .bookingRequest, .bookingUpdate, .bookingReminder, .searchAppearance])
        guard case let .bookingUpdate(update) = activities[2] else {
            Issue.record("expected booking update")
            return
        }
        #expect(update.status == .canceled)
        #expect(activities[1].common.markedRead)
        #expect(!activities[0].common.markedRead)
        #expect(activities[0].copyAsRead().common.markedRead)
        guard case let .searchAppearance(appearance) = activities[4] else {
            Issue.record("expected search appearance")
            return
        }
        #expect(appearance.count == 12)
    }

    @Test func reviewVariants() throws {
        let reviews = try Fixture.decode([Review].self, "reviews")
        #expect(reviews.map(\.type) == [.booker, .performer])
        #expect(reviews[1].fields.bookingId == "b1")
        #expect(reviews[0].fields.overallRating == 5)
    }

    @Test func contactVenueRequest() throws {
        let request = try Fixture.decode(ContactVenueRequest.self, "contact_venue_request")
        #expect(request.venue.username == "thecamel")
        #expect(request.collaborators.count == 1)
        #expect(request.opportunityIds.isEmpty)
        #expect(request.subject == nil)
    }

    @Test func paymentUserUsesSnakeCaseKeys() throws {
        let user = try Fixture.decode(PaymentUser.self, "payment_user")
        #expect(user.chargesEnabled)
        #expect(!user.payoutsEnabled)
        #expect(user.createdAt == Date(timeIntervalSince1970: 1_720_000_000))
    }

    @Test func serviceDefaultsAndCost() throws {
        let data = Data(#"{"id":"s1","userId":"u1","rate":6000,"rateType":"hourly"}"#.utf8)
        let service = try TappedCoding.jsonDecoder().decode(Service.self, from: data)
        #expect(service.rateType == .hourly)
        let start = Date(timeIntervalSince1970: 0)
        #expect(service.performerCost(start: start, end: start.addingTimeInterval(90 * 60)) == 9000)
        #expect(Service(id: "s", userId: "u", rate: 500).performerCost(start: start, end: start) == 500)
    }

    @Test(arguments: Genre.allCases)
    func genreRoundTrips(genre: Genre) throws {
        let data = try JSONEncoder().encode([genre])
        #expect(try JSONDecoder().decode([Genre].self, from: data) == [genre])
        #expect(!genre.formattedName.isEmpty)
    }

    @Test func genreUsesFlutterJsonValues() throws {
        #expect(Genre.axe.rawValue == "axé")
        #expect(Genre.hipHop.rawValue == "hipHop")
        #expect(Genre.allCases.count == 135)
    }

    @Test func enumsUseFlutterJsonValues() {
        #expect(BookingStatus.allCases.map(\.rawValue) == ["pending", "confirmed", "canceled"])
        #expect(PerformerCategory.hometownHero.rawValue == "hometownHero")
        #expect(VenueType.artGallery.rawValue == "artGallery")
        #expect(RateType.allCases.map(\.rawValue) == ["hourly", "fixed"])
        #expect(OpportunityInteraction.allCases.map(\.rawValue) == ["like", "dislike"])
    }
}
