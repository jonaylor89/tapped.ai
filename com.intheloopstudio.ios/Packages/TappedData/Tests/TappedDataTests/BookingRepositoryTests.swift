import Foundation
import TappedDomain
import Testing
@testable import TappedData

@Suite("Bookings, services, reviews + venue outreach (mocks)")
struct BookingRepositoryTests {
    @Test func createAndUpdateBooking() async throws {
        let database = MockDatabaseRepository(bookings: [])
        var booking = Samples.bookings[1]
        try await database.createBooking(booking)
        #expect(try await database.getBookingById(booking.id) == booking)

        booking.status = .confirmed
        try await database.updateBooking(booking)
        #expect(try await database.getBookingById(booking.id)?.status == .confirmed)
        #expect(try await database.getBookingsByRequestee(booking.requesteeId, status: .pending).isEmpty)
    }

    @Test func requesterRequesteePairAndEventQueries() async throws {
        let database = MockDatabaseRepository()
        let pair = try await database.getBookingsByRequesterRequestee("venue-camel", Samples.performer.id, limit: 10, lastBookingRequestId: nil, status: nil)
        #expect(pair.map(\.id) == ["booking-1"])
        let none = try await database.getBookingsByRequesterRequestee("venue-camel", Samples.performer.id, limit: 10, lastBookingRequestId: nil, status: .pending)
        #expect(none.isEmpty)
        #expect(try await database.getBookingsByEventId("missing").isEmpty)
    }

    @Test func serviceCrudSoftDeletes() async throws {
        let database = MockDatabaseRepository(services: [])
        let userId = Samples.performer.id
        var service = Service(id: "s1", userId: userId, title: "dj set", rate: 10_000, rateType: .hourly)
        try await database.createService(service)
        #expect(try await database.getUserServices(userId) == [service])

        service.title = "long dj set"
        try await database.updateService(service)
        #expect(try await database.getServiceById(userId, "s1")?.title == "long dj set")

        try await database.deleteService(userId, "s1")
        #expect(try await database.getUserServices(userId).isEmpty)
        #expect(try await database.getServiceById(userId, "s1")?.deleted == true)
    }

    @Test func sampleServicesSortedByRate() async throws {
        let services = try await MockDatabaseRepository().getUserServices(Samples.performer.id)
        #expect(services.map(\.rate) == services.map(\.rate).sorted())
        #expect(services.count == Samples.services.filter { $0.userId == Samples.performer.id }.count)
    }

    @Test func reviewsAreKeyedByReviewee() async throws {
        let database = MockDatabaseRepository()
        let fields = ReviewFields(id: "r1", bookerId: "venue-camel", performerId: Samples.performer.id, bookingId: "booking-1", timestamp: Samples.referenceDate, overallRating: 5, overallReview: "great", type: .performer)
        try await database.createPerformerReview(PerformerReview(fields: fields))
        #expect(try await database.getPerformerReviewById(revieweeId: Samples.performer.id, reviewId: "r1")?.fields.overallRating == 5)
        #expect(try await database.getPerformerReviewById(revieweeId: "venue-camel", reviewId: "r1") == nil)

        try await database.createBookerReview(BookerReview(fields: fields))
        #expect(try await database.getBookerReviewById(revieweeId: "venue-camel", reviewId: "r1")?.fields.type == .booker)
    }

    @Test func mockOutreachRecordsThreads() async throws {
        let outreach = MockVenueOutreachRepository()
        try await outreach.createVenueEmailThread(id: "req:venue-camel", venueId: "venue-camel", subject: "hi", textBody: "body")
        #expect(await outreach.threads.map(\.venueId) == ["venue-camel"])
        await #expect(throws: VenueOutreachError.notSignedIn) {
            try await MockVenueOutreachRepository(failure: .notSignedIn).createVenueEmailThread(id: "x", venueId: "v", subject: "s", textBody: "t")
        }
    }

    @Test func liveOutreachRequestMatchesTappedApiClient() async throws {
        let repository = TappedAPIVenueOutreachRepository(baseURL: URL(string: "https://api.tapped.ai")!, idToken: { "token" })
        let request = try await repository.makeRequest(VenueEmailThread(id: "req:v1", venueId: "v1", subject: "Performance inquiry from DJ Nova", textBody: "hello"))
        #expect(request.url?.absoluteString == "https://api.tapped.ai/app/v1/venue-email-threads")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(body == ["id": "req:v1", "venue_id": "v1", "subject": "Performance inquiry from DJ Nova", "text_body": "hello"])
    }

    @Test func liveOutreachRequiresToken() async {
        let repository = TappedAPIVenueOutreachRepository(baseURL: URL(string: "https://api.tapped.ai")!, idToken: { nil })
        await #expect(throws: VenueOutreachError.notSignedIn) {
            try await repository.createVenueEmailThread(id: "x", venueId: "v", subject: "s", textBody: "t")
        }
    }

    @Test func bookingHelpers() {
        let booking = Samples.bookings[0]
        #expect(booking.involves(Samples.performer.id))
        #expect(booking.counterpartId(for: Samples.performer.id) == "venue-camel")
        #expect(booking.counterpartId(for: "venue-camel") == Samples.performer.id)
        #expect(booking.isExpired(now: booking.endTime.addingTimeInterval(1)))
        #expect(!booking.isExpired(now: booking.startTime))
        #expect(booking.duration == 2 * 60 * 60)
    }
}
