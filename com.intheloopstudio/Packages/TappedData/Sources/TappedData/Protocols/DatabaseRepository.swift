import Foundation
import TappedDomain

/// `lib/data/database_repository.dart`, method by method.
///
/// Conventions:
/// - Dart `Future<Option<T>>` → `async throws -> T?`
/// - Dart `Stream<T>` (Firestore listener) → `AsyncThrowingStream<[T], any Error>` that yields the full
///   current result set for every snapshot (not per-document diffs like the Dart version).
/// - Dart default arguments live in the `extension DatabaseRepository` below.
public protocol DatabaseRepository: Sendable {
    func publishLatestAppVersion(_ currentUserId: String) async throws -> String

    // MARK: users
    func userEmailExists(_ email: String) async throws -> Bool
    func createUser(_ user: UserModel) async throws
    func deleteUser(_ userId: String) async throws
    func getUserByUsername(_ username: String?) async throws -> UserModel?
    func getUserById(_ userId: String) async throws -> UserModel?
    func updateUserData(_ user: UserModel) async throws
    func classifyPerformer(_ userId: String) async throws -> PerformerCategory?
    func checkUsernameAvailability(_ username: String, userId: String) async throws -> Bool
    func getBookingLeaders() async throws -> [UserModel]
    func getBookerLeaders() async throws -> [UserModel]
    func getFeaturedPerformers() async throws -> [UserModel]
    func getFeaturedOpportunities() async throws -> [Opportunity]

    // MARK: activities
    func getActivities(_ userId: String, limit: Int, lastActivityId: String?) async throws -> [Activity]
    func activitiesObserver(_ userId: String, limit: Int) -> AsyncThrowingStream<[Activity], any Error>
    func addActivity(currentUserId: String, visitedUserId: String, type: ActivityType) async throws
    func markActivityAsRead(_ activity: Activity) async throws

    // MARK: badges
    func isVerified(_ userId: String) async throws -> Bool

    // MARK: bookings
    func createBooking(_ booking: Booking) async throws
    func getBookingById(_ bookRequestId: String) async throws -> Booking?
    func getBookingsByEventId(_ eventId: String) async throws -> [Booking]
    func getBookingsByRequesterRequestee(_ requesterId: String, _ requesteeId: String, limit: Int, lastBookingRequestId: String?, status: BookingStatus?) async throws -> [Booking]
    func getBookingsByRequester(_ userId: String, limit: Int, lastBookingRequestId: String?, status: BookingStatus?) async throws -> [Booking]
    func getBookingsByRequesterObserver(_ userId: String, limit: Int, status: BookingStatus?) -> AsyncThrowingStream<[Booking], any Error>
    func getBookingsByRequestee(_ userId: String, limit: Int, lastBookingRequestId: String?, status: BookingStatus?) async throws -> [Booking]
    func getBookingsByRequesteeObserver(_ userId: String, limit: Int, status: BookingStatus?) -> AsyncThrowingStream<[Booking], any Error>
    func updateBooking(_ booking: Booking) async throws

    // MARK: services
    func createService(_ service: Service) async throws
    func updateService(_ service: Service) async throws
    func getServiceById(_ userId: String, _ serviceId: String) async throws -> Service?
    func getUserServices(_ userId: String) async throws -> [Service]
    func deleteService(_ userId: String, _ serviceId: String) async throws

    // MARK: opportunities
    func getOpportunityById(_ opportunityId: String) async throws -> Opportunity?
    func getOpportunities(limit: Int, lastOpportunityId: String?) async throws -> [Opportunity]
    func getOpportunitiesByUserId(_ userId: String, limit: Int, lastOpportunityId: String?) async throws -> [Opportunity]
    func getOpportunityFeedByUserId(_ userId: String, limit: Int, lastOpportunityId: String?) async throws -> [Opportunity]
    func isUserAppliedForOpportunity(opportunityId: String, userId: String) async throws -> Bool
    func getInterestedUsers(_ opportunity: Opportunity) async throws -> [UserModel]
    func applyForOpportunity(opportunity: Opportunity, userId: String, userComment: String) async throws
    func dislikeOpportunity(opportunity: Opportunity, userId: String) async throws
    func getAppliedOpportunitiesByUserId(_ userId: String, limit: Int, lastOpportunityId: String?) async throws -> [Opportunity]
    func getUserOpportunityQuota(_ userId: String) async throws -> Int
    func getUserOpportunityQuotaObserver(_ userId: String) -> AsyncThrowingStream<Int, any Error>
    func decrementUserOpportunityQuota(_ userId: String) async throws
    func createOpportunity(_ opportunity: Opportunity) async throws
    func copyOpportunityToFeeds(_ opportunity: Opportunity) async throws
    func deleteOpportunity(_ opportunityId: String) async throws

    // MARK: blocking
    func blockUser(currentUserId: String, blockedUserId: String) async throws
    func unblockUser(currentUserId: String, blockedUserId: String) async throws
    func isBlocked(currentUserId: String, blockedUserId: String) async throws -> Bool
    func reportUser(reported: UserModel, reporter: UserModel) async throws

    // MARK: performer reviews
    func createPerformerReview(_ review: PerformerReview) async throws
    func getPerformerReviewById(revieweeId: String, reviewId: String) async throws -> PerformerReview?
    func getPerformerReviewsByPerformerId(_ performerId: String, limit: Int, lastReviewId: String?) async throws -> [PerformerReview]
    func getPerformerReviewsByPerformerIdObserver(_ performerId: String, limit: Int) -> AsyncThrowingStream<[PerformerReview], any Error>

    // MARK: booker reviews
    func createBookerReview(_ review: BookerReview) async throws
    func getBookerReviewById(revieweeId: String, reviewId: String) async throws -> BookerReview?
    func getBookerReviewsByBookerId(_ bookerId: String, limit: Int, lastReviewId: String?) async throws -> [BookerReview]
    func getBookerReviewsByBookerIdObserver(_ bookerId: String, limit: Int) -> AsyncThrowingStream<[BookerReview], any Error>

    // MARK: premium / feedback / contact
    func joinPremiumWaitlist(_ userId: String) async throws
    /// Name (including the Dart typo) kept so grep across both codebases lines up.
    func isOnPremiumWailist(_ userId: String) async throws -> Bool
    func hasUserSentContactRequest(user: UserModel, venue: UserModel) async throws -> Bool
    func getContactedVenues(_ userId: String) async throws -> [UserModel]
}

/// Dart default arguments.
public extension DatabaseRepository {
    func getActivities(_ userId: String) async throws -> [Activity] {
        try await getActivities(userId, limit: 100, lastActivityId: nil)
    }

    func activitiesObserver(_ userId: String) -> AsyncThrowingStream<[Activity], any Error> {
        activitiesObserver(userId, limit: 100)
    }

    func getBookingsByRequester(_ userId: String, status: BookingStatus? = nil) async throws -> [Booking] {
        try await getBookingsByRequester(userId, limit: 20, lastBookingRequestId: nil, status: status)
    }

    func getBookingsByRequestee(_ userId: String, status: BookingStatus? = nil) async throws -> [Booking] {
        try await getBookingsByRequestee(userId, limit: 20, lastBookingRequestId: nil, status: status)
    }

    func getBookingsByRequesterObserver(_ userId: String) -> AsyncThrowingStream<[Booking], any Error> {
        getBookingsByRequesterObserver(userId, limit: 20, status: nil)
    }

    func getBookingsByRequesteeObserver(_ userId: String) -> AsyncThrowingStream<[Booking], any Error> {
        getBookingsByRequesteeObserver(userId, limit: 20, status: nil)
    }

    func getOpportunities() async throws -> [Opportunity] {
        try await getOpportunities(limit: 20, lastOpportunityId: nil)
    }

    func getOpportunitiesByUserId(_ userId: String) async throws -> [Opportunity] {
        try await getOpportunitiesByUserId(userId, limit: 20, lastOpportunityId: nil)
    }

    func getOpportunityFeedByUserId(_ userId: String) async throws -> [Opportunity] {
        try await getOpportunityFeedByUserId(userId, limit: 20, lastOpportunityId: nil)
    }

    func getAppliedOpportunitiesByUserId(_ userId: String) async throws -> [Opportunity] {
        try await getAppliedOpportunitiesByUserId(userId, limit: 20, lastOpportunityId: nil)
    }

    func getPerformerReviewsByPerformerId(_ performerId: String) async throws -> [PerformerReview] {
        try await getPerformerReviewsByPerformerId(performerId, limit: 20, lastReviewId: nil)
    }

    func getBookerReviewsByBookerId(_ bookerId: String) async throws -> [BookerReview] {
        try await getBookerReviewsByBookerId(bookerId, limit: 20, lastReviewId: nil)
    }
}

extension DatabaseRepository {
    /// Dart `classifyPerformer`: the user's audience plus the capacities of the venues that booked them (bookings
    /// without a requester, or whose requester has no venue capacity, are skipped). `nil` when the user doesn't exist.
    func computePerformerCategory(_ userId: String, now: Date = .now) async throws -> PerformerCategory? {
        guard let user = try await getUserById(userId) else { return nil }
        let bookings = try await getBookingsByRequestee(userId)
        let capacities = try await bookings.concurrentCompactMap { booking -> PerformerClassification.VenueCapacity? in
            guard let requesterId = booking.requesterId,
                  let capacity = try await self.getUserById(requesterId)?.venueInfo?.capacity,
                  capacity != 0
            else { return nil }
            return .init(capacity: capacity, startTime: booking.startTime)
        }
        return PerformerClassification.categorizeWithWeightedDate(
            audience: user.socialFollowing.audienceSize,
            capacities: capacities,
            now: now
        )
    }
}
