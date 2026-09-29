import Foundation
import TappedData
import TappedDomain
import Testing
@testable import Tapped

@MainActor
@Suite("Bookings, booking flows + services view models")
struct BookingsFeatureTests {
    let now = Samples.referenceDate
    let me = Samples.performer

    private func dependencies(database: MockDatabaseRepository = MockDatabaseRepository(), outreach: MockVenueOutreachRepository = MockVenueOutreachRepository()) -> Dependencies {
        var dependencies = Dependencies.mock(signedIn: true)
        dependencies.database = database
        dependencies.venueOutreach = outreach
        return dependencies
    }

    // MARK: bookings list

    @Test func bookingsAreBucketedLikeFlutter() async {
        let model = BookingsViewModel(dependencies: dependencies(), userId: me.id, now: { now })
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.bookings(in: .pending).map(\.id) == ["booking-2", "booking-3"])
        #expect(model.bookings(in: .upcoming).map(\.id) == ["booking-1"])
        #expect(model.bookings(in: .past).map(\.id) == ["booking-8", "booking-4", "booking-5", "booking-6", "booking-7"])
        #expect(model.segment == .pending)
        #expect(model.counterpart(for: Samples.bookings[0])?.id == "venue-camel")
        #expect(model.counterpart(for: Samples.bookings[2])?.id == "performer-mara")
    }

    @Test func emptyBookingsDefaultToUpcoming() async {
        let model = BookingsViewModel(dependencies: dependencies(database: MockDatabaseRepository(bookings: [])), userId: me.id, now: { now })
        await model.load()
        #expect(model.segment == .upcoming)
        #expect(model.visibleBookings.isEmpty)
        #expect(model.emptyState.title == "no upcoming gigs")
    }

    // MARK: booking detail

    @Test func requesteeCanAcceptPendingRequest() async throws {
        let database = MockDatabaseRepository()
        let model = BookingDetailViewModel(dependencies: dependencies(database: database), booking: Samples.bookings[1], currentUser: me, now: { now })
        await model.load()
        #expect(model.canRespond)
        #expect(!model.canCancel)
        #expect(model.requester?.id == "venue-canal")
        #expect(model.place?.name == "Canal Club")
        await model.confirm()
        #expect(model.booking.status == .confirmed)
        #expect(try await database.getBookingById("booking-2")?.status == .confirmed)
        #expect(model.canCancel)
    }

    @Test func denyAndCancelSetCanceled() async throws {
        let database = MockDatabaseRepository()
        let pending = BookingDetailViewModel(dependencies: dependencies(database: database), booking: Samples.bookings[1], currentUser: me, now: { now })
        await pending.deny()
        #expect(try await database.getBookingById("booking-2")?.status == .canceled)

        let requested = BookingDetailViewModel(dependencies: dependencies(database: database), booking: Samples.bookings[2], currentUser: me, now: { now })
        #expect(!requested.canRespond)
        #expect(requested.canCancel)
        await requested.cancel()
        #expect(try await database.getBookingById("booking-3")?.status == .canceled)
    }

    @Test func pastBookingPromptsForBookerReviewOnce() async throws {
        let database = MockDatabaseRepository()
        let model = BookingDetailViewModel(dependencies: dependencies(database: database), booking: Samples.bookings[3], currentUser: me, now: { now })
        await model.load()
        #expect(model.canReview)
        #expect(!model.canCancel)
        model.reviewRating = 4
        model.reviewText = "  great room  "
        #expect(await model.submitReview())
        #expect(!model.canReview)
        let review = try #require(try await database.getBookerReviewById(revieweeId: "venue-broadberry", reviewId: model.reviewId))
        #expect(review.fields.type == .booker)
        #expect(review.fields.overallReview == "great room")
        #expect(review.fields.bookingId == "booking-4")

        let reopened = BookingDetailViewModel(dependencies: dependencies(database: database), booking: Samples.bookings[3], currentUser: me, now: { now })
        await reopened.load()
        #expect(reopened.hasReviewed)
        #expect(!reopened.canReview)
    }

    @Test func userAddedBookingsHaveNoReviewPrompt() async {
        let model = BookingDetailViewModel(dependencies: dependencies(), booking: Samples.bookings[5], currentUser: me, now: { now })
        await model.load()
        #expect(!model.canReview)
        #expect(!model.canRespond)
    }

    // MARK: create booking

    @Test func createBookingValidatesAndWritesPendingBooking() async throws {
        let database = MockDatabaseRepository()
        let model = CreateBookingViewModel(dependencies: dependencies(database: database), currentUser: me, requesteeId: "performer-mara", service: nil, now: { now }, makeId: { "new-booking" })
        await model.load()
        #expect(model.services.count == 2)
        #expect(model.validationMessage == "add an event name")
        model.name = "rooftop"
        #expect(model.validationMessage == "choose a location")
        model.place = MockPlacesRepository.places[0]
        #expect(model.canSubmit)
        model.end = model.start.addingTimeInterval(-60)
        #expect(model.validationMessage == "the end time must be after the start")
        model.end = model.start.addingTimeInterval(3 * 60 * 60)
        model.selectedServiceId = "service-mara-feature"

        let booking = try #require(await model.submit())
        #expect(booking.id == "new-booking")
        #expect(booking.status == .pending)
        #expect(booking.requesterId == me.id)
        #expect(booking.requesteeId == "performer-mara")
        #expect(booking.serviceId == "service-mara-feature")
        #expect(booking.rate == 36_000)
        #expect(booking.location == MockPlacesRepository.places[0].location)
        #expect(try await database.getBookingById("new-booking") == booking)
    }

    @Test func movingStartPastEndKeepsDuration() {
        let model = CreateBookingViewModel(dependencies: dependencies(), currentUser: me, requesteeId: "performer-mara", service: nil, now: { now })
        let duration = model.duration
        model.start = model.end.addingTimeInterval(60 * 60)
        #expect(model.end > model.start)
        #expect(model.duration == duration)
    }

    @Test func cannotBookYourself() {
        let model = CreateBookingViewModel(dependencies: dependencies(), currentUser: me, requesteeId: me.id, service: nil, now: { now })
        #expect(model.validationMessage == "you can't book yourself")
    }

    // MARK: add past booking

    @Test func addPastBookingCreatesConfirmedUserAddedBooking() async throws {
        let database = MockDatabaseRepository()
        let model = AddPastBookingViewModel(dependencies: dependencies(database: database), currentUser: me, now: { now }, makeId: { "past" })
        model.name = "warehouse"
        model.place = MockPlacesRepository.places[1]
        model.start = now.addingTimeInterval(60 * 60)
        #expect(model.validationMessage == "past bookings must start in the past")
        model.start = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let booking = try #require(await model.submit())
        #expect(booking.status == .confirmed)
        #expect(booking.addedByUser && booking.verified)
        #expect(booking.requesteeId == me.id && booking.requesterId == nil)
        #expect(booking.duration == model.duration)
        #expect(try await database.getBookingById("past") != nil)
    }

    @Test func addPastBookingReclassifiesThePerformer() async throws {
        var legendary = me
        legendary.performerInfo?.category = .legendary
        // A self-added booking has no venue requester, so with no other bookings the performer is undiscovered.
        let database = MockDatabaseRepository(users: [legendary], bookings: [])
        let model = AddPastBookingViewModel(dependencies: dependencies(database: database), currentUser: legendary, now: { now }, makeId: { "past" })
        model.name = "warehouse"
        model.place = MockPlacesRepository.places[1]
        model.start = now.addingTimeInterval(-3 * 24 * 60 * 60)
        _ = try #require(await model.submit())
        #expect(model.updatedUser?.performerInfo?.category == .undiscovered)
        #expect(try await database.getUserById(me.id)?.performerInfo?.category == .undiscovered)
    }

    // MARK: request to perform

    @Test func requestToPerformSendsOneThreadPerVenue() async throws {
        let outreach = MockVenueOutreachRepository()
        let venues = Array(Samples.venues.prefix(2))
        let model = RequestToPerformViewModel(dependencies: dependencies(outreach: outreach), currentUser: me, venues: venues, collaborators: [Samples.performers[2]], makeId: { "req" })
        #expect(model.validationMessage == "write a message to the venue")
        model.note = "hi there"
        let sent = try #require(await model.submit())
        #expect(sent.map(\.id) == venues.map(\.id))
        let threads = await outreach.threads.sorted { $0.id < $1.id }
        #expect(threads.map(\.id) == ["req:venue-camel", "req:venue-national"])
        #expect(threads.allSatisfy { $0.subject == "Performance inquiry from DJ Nova" })
        #expect(threads[0].textBody == "hi there\n\nCollaborators: \(Samples.performers[2].displayName)")
    }

    @Test func requestToPerformSurfacesFailures() async {
        let model = RequestToPerformViewModel(dependencies: dependencies(outreach: MockVenueOutreachRepository(failure: .requestFailed(statusCode: 500))), currentUser: me, venues: [Samples.venues[0]], collaborators: [])
        model.note = "hello"
        #expect(await model.submit() == nil)
        #expect(model.errorMessage == "couldn't send your request")
        model.venues = []
        #expect(model.validationMessage == "add at least one venue")
    }

    // MARK: booking history

    @Test func historyShowsPastConfirmedBookings() async {
        let model = BookingHistoryViewModel(dependencies: dependencies(), user: me, now: { now })
        await model.load()
        #expect(model.bookings.map(\.id) == ["booking-4", "booking-5", "booking-6", "booking-7"])
        #expect(model.summary == "4 gigs · 2 venues")
        #expect(model.requester(for: model.bookings[0])?.id == "venue-broadberry")
    }

    // MARK: services

    @Test func serviceFormCreatesAndEdits() async throws {
        let database = MockDatabaseRepository(services: [])
        let form = ServiceFormViewModel(dependencies: dependencies(database: database), service: nil, ownerId: me.id, makeId: { "svc" })
        #expect(form.validationMessage == "add a title")
        form.title = "dj set"
        form.description = "two hours"
        form.rate = Decimal(string: "150.5")
        form.rateType = .hourly
        let created = try #require(await form.save())
        #expect(created.rate == 15_050)
        #expect(try await database.getUserServices(me.id) == [created])

        let edit = ServiceFormViewModel(dependencies: dependencies(database: database), service: created, ownerId: me.id)
        #expect(edit.isEditing)
        #expect(edit.rate == Decimal(string: "150.5"))
        edit.title = "long dj set"
        _ = await edit.save()
        #expect(try await database.getServiceById(me.id, "svc")?.title == "long dj set")
    }

    @Test func serviceListOwnershipAndDelete() async throws {
        let database = MockDatabaseRepository()
        let mine = ServiceListViewModel(dependencies: dependencies(database: database), userId: me.id, currentUserId: me.id)
        await mine.load()
        #expect(mine.isOwner)
        #expect(mine.services.count == 3)
        await mine.delete(mine.services[0])
        #expect(mine.services.count == 2)
        #expect(try await database.getUserServices(me.id).count == 2)

        let theirs = ServiceListViewModel(dependencies: dependencies(database: database), userId: "performer-mara", currentUserId: me.id)
        await theirs.load()
        #expect(!theirs.isOwner)
        #expect(theirs.user?.id == "performer-mara")
    }

    @Test func serviceDetailDeletes() async throws {
        let database = MockDatabaseRepository()
        let model = ServiceDetailViewModel(dependencies: dependencies(database: database), service: Samples.services[0], serviceUser: nil, currentUserId: me.id)
        await model.load()
        #expect(model.isOwner)
        #expect(model.serviceUser?.id == me.id)
        #expect(await model.delete())
        #expect(try await database.getServiceById(me.id, Samples.services[0].id)?.deleted == true)
    }

    // MARK: routing

    @Test func mockLaunchRoutesResolve() {
        for name in ["bookings", "booking", "booking-pending", "booking-sent", "booking-past", "booking-confirmation", "create-booking",
                     "add-past-booking", "request-to-perform", "request-sent", "services", "services-book", "service", "service-book",
                     "create-service", "edit-service", "history"] {
            let path = Route.mockLaunchPath(name, currentUser: me)
            #expect(path?.count == 1, "\(name)")
            #expect(path?.first?.owner == 3, "\(name)")
        }
        #expect(Route.mockLaunchPath("nope", currentUser: me) == nil)
        #expect(LaunchOptions.from(["TAPPED_MOCK": "1", "TAPPED_MOCK_ROUTE": "bookings"]).route == "bookings")
        #expect(LaunchOptions.from(["TAPPED_MOCK_ROUTE": "bookings"]).route == nil)
    }

    @Test func flowStepsUnwind() {
        #expect(Route.bookingConfirmation(Samples.bookings[0]).isBookingFlowStep)
        #expect(Route.serviceSelection(userId: "u", requesteeStripeConnectedAccountId: nil).isBookingFlowStep)
        #expect(!Route.bookings(userId: "u").isBookingFlowStep)
        #expect(Route.requestToPerform(venues: [], collaborators: []).isRequestToPerformFlowStep)
        #expect(!Route.settings.isRequestToPerformFlowStep)
    }
}
