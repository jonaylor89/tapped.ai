import Foundation
import Observation
import TappedData
import TappedDomain

/// `lib/ui/booking/booking_view.dart`: status, parties, when/where, respond/cancel, review prompt.
/// The deprecated Stripe payment section is intentionally not ported.
@Observable
@MainActor
final class BookingDetailViewModel {
    private(set) var booking: Booking
    let currentUser: UserModel
    private(set) var requester: UserModel?
    private(set) var requestee: UserModel?
    private(set) var place: PlaceData?
    private(set) var service: Service?
    private(set) var isUpdating = false
    private(set) var hasReviewed = false
    private(set) var isSubmittingReview = false
    var errorMessage: String?
    var reviewRating = 0
    var reviewText = ""

    private let database: any DatabaseRepository
    private let places: any PlacesRepository
    private let analytics: any AnalyticsRepository
    private let now: () -> Date

    init(dependencies: Dependencies, booking: Booking, currentUser: UserModel, now: @escaping () -> Date = { .now }) {
        database = dependencies.database
        places = dependencies.places
        analytics = dependencies.analytics
        self.booking = booking
        self.currentUser = currentUser
        self.now = now
    }

    var isRequestee: Bool { booking.requesteeId == currentUser.id }
    var isRequester: Bool { booking.requesterId == currentUser.id }
    var isExpired: Bool { booking.isExpired(now: now()) }

    /// Pending requests aimed at the current user can be accepted or denied.
    var canRespond: Bool { isRequestee && booking.isPending && !isExpired && booking.requesterId != nil }
    /// Either party can cancel a live booking; the requestee denies instead while it's pending.
    var canCancel: Bool { booking.involves(currentUser.id) && !booking.isCanceled && !isExpired && !canRespond }
    var canReview: Bool { booking.isConfirmed && isExpired && booking.requesterId != nil && booking.involves(currentUser.id) && !hasReviewed }

    var statusMessage: String {
        switch booking.status {
        case .pending where isExpired: "this request expired"
        case .pending where canRespond: "respond to this request"
        case .pending: "waiting for the performer to respond"
        case .confirmed where isExpired: "this gig has wrapped"
        case .confirmed: "you're booked"
        case .canceled: "this booking was canceled"
        }
    }

    /// Deterministic so the prompt can tell whether the current user already reviewed this booking.
    var reviewId: String { "\(booking.id)-\(currentUser.id)" }
    var reviewee: UserModel? { isRequester ? requestee : requester }

    func load() async {
        let database = database
        let places = places
        async let requester = booking.requesterId.asyncFlatMap { try? await database.getUserById($0) }
        async let requestee = try? await database.getUserById(booking.requesteeId)
        async let place = booking.location.asyncFlatMap { try? await places.getPlaceById($0.placeId) }
        async let service = booking.serviceId.asyncFlatMap { [booking] in try? await database.getServiceById(booking.requesteeId, $0) }
        async let reviewed = hasExistingReview()
        self.requester = await requester
        self.requestee = await requestee
        self.place = await place
        self.service = await service
        hasReviewed = await reviewed
    }

    func confirm() async { await update(to: .confirmed, event: "booking_confirmed") }
    func deny() async { await update(to: .canceled, event: "booking_denied") }
    func cancel() async { await update(to: .canceled, event: "booking_canceled") }

    func submitReview() async -> Bool {
        guard reviewRating > 0, let requesterId = booking.requesterId, !isSubmittingReview else { return false }
        isSubmittingReview = true
        defer { isSubmittingReview = false }
        let fields = ReviewFields(
            id: reviewId,
            bookerId: requesterId,
            performerId: booking.requesteeId,
            bookingId: booking.id,
            timestamp: now(),
            overallRating: reviewRating,
            overallReview: reviewText.trimmingCharacters(in: .whitespacesAndNewlines),
            type: isRequester ? .performer : .booker
        )
        do {
            if isRequester {
                try await database.createPerformerReview(PerformerReview(fields: fields))
            } else {
                try await database.createBookerReview(BookerReview(fields: fields))
            }
            hasReviewed = true
            await analytics.track("review_created", properties: ["type": .string(fields.type.rawValue), "rating": .int(reviewRating)])
            return true
        } catch {
            errorMessage = "couldn't post your review"
            return false
        }
    }

    private func hasExistingReview() async -> Bool {
        guard let requesterId = booking.requesterId else { return false }
        if isRequester {
            return (try? await database.getPerformerReviewById(revieweeId: booking.requesteeId, reviewId: reviewId)) != nil
        }
        return (try? await database.getBookerReviewById(revieweeId: requesterId, reviewId: reviewId)) != nil
    }

    private func update(to status: BookingStatus, event: String) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        var updated = booking
        updated.status = status
        do {
            try await database.updateBooking(updated)
            booking = updated
            await analytics.track(event, properties: ["booking_id": .string(booking.id)])
        } catch {
            errorMessage = "couldn't update the booking"
        }
    }
}

extension Optional where Wrapped: Sendable {
    func asyncFlatMap<T>(_ transform: (Wrapped) async -> T?) async -> T? {
        guard let self else { return nil }
        return await transform(self)
    }
}
