import Foundation
import TappedDomain

/// In-memory database seeded from `Samples`. Mirrors the implemented subset of `FirestoreDatabaseRepository`;
/// other methods throw `NotImplemented` just like the live implementation.
public actor MockDatabaseRepository: DatabaseRepository {
    public private(set) var users: [String: UserModel]
    public private(set) var opportunities: [String: Opportunity]
    public private(set) var bookings: [String: Booking]
    public var featuredPerformerIds: [String]
    public var featuredOpportunityIds: [String]
    public private(set) var premiumWaitlist: Set<String> = []

    public init(
        users: [UserModel] = Samples.performers + Samples.venues,
        opportunities: [Opportunity] = Samples.opportunities,
        bookings: [Booking] = Samples.bookings,
        featuredPerformerIds: [String] = Samples.performers.map(\.id),
        featuredOpportunityIds: [String] = Samples.opportunities.map(\.id)
    ) {
        self.users = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
        self.opportunities = Dictionary(uniqueKeysWithValues: opportunities.map { ($0.id, $0) })
        self.bookings = Dictionary(uniqueKeysWithValues: bookings.map { ($0.id, $0) })
        self.featuredPerformerIds = featuredPerformerIds
        self.featuredOpportunityIds = featuredOpportunityIds
    }

    public func userEmailExists(_ email: String) async throws -> Bool { users.values.contains { $0.email == email } }
    public func createUser(_ user: UserModel) async throws { users[user.id] = user }
    public func getUserByUsername(_ username: String?) async throws -> UserModel? {
        users.values.first { $0.username.username == username }
    }
    public func getUserById(_ userId: String) async throws -> UserModel? { users[userId] }
    public func updateUserData(_ user: UserModel) async throws { users[user.id] = user }
    public func checkUsernameAvailability(_ username: String, userId: String) async throws -> Bool {
        if ["anonymous", "*deleted*"].contains(username) { return false }
        return !users.values.contains { $0.username.username == username && $0.id != userId }
    }
    public func getBookingLeaders() async throws -> [UserModel] { featuredPerformerIds.compactMap { users[$0] } }
    public func getBookerLeaders() async throws -> [UserModel] { users.values.filter(\.isVenue).sorted { $0.id < $1.id } }
    public func getFeaturedPerformers() async throws -> [UserModel] { featuredPerformerIds.compactMap { users[$0] } }
    public func getFeaturedOpportunities() async throws -> [Opportunity] {
        featuredOpportunityIds.compactMap { opportunities[$0] }.sorted { $0.startTime > $1.startTime }
    }
    public func getActivities(_ userId: String, limit: Int, lastActivityId: String?) async throws -> [Activity] { [] }
    public nonisolated func activitiesObserver(_ userId: String, limit: Int) -> AsyncThrowingStream<[Activity], any Error> {
        AsyncThrowingStream { $0.yield([]) }
    }
    public func isVerified(_ userId: String) async throws -> Bool { false }
    public func getBookingById(_ bookRequestId: String) async throws -> Booking? { bookings[bookRequestId] }
    public func getBookingsByRequester(_ userId: String, limit: Int, lastBookingRequestId: String?, status: BookingStatus?) async throws -> [Booking] {
        filterBookings { $0.requesterId == userId }(status, limit)
    }
    public nonisolated func getBookingsByRequesterObserver(_ userId: String, limit: Int, status: BookingStatus?) -> AsyncThrowingStream<[Booking], any Error> {
        stream { try await $0.getBookingsByRequester(userId, limit: limit, lastBookingRequestId: nil, status: status) }
    }
    public func getBookingsByRequestee(_ userId: String, limit: Int, lastBookingRequestId: String?, status: BookingStatus?) async throws -> [Booking] {
        filterBookings { $0.requesteeId == userId }(status, limit)
    }
    public nonisolated func getBookingsByRequesteeObserver(_ userId: String, limit: Int, status: BookingStatus?) -> AsyncThrowingStream<[Booking], any Error> {
        stream { try await $0.getBookingsByRequestee(userId, limit: limit, lastBookingRequestId: nil, status: status) }
    }
    public func getOpportunityById(_ opportunityId: String) async throws -> Opportunity? { opportunities[opportunityId] }
    public func getOpportunitiesByUserId(_ userId: String, limit: Int, lastOpportunityId: String?) async throws -> [Opportunity] {
        Array(opportunities.values.filter { $0.userId == userId && !$0.deleted }.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }
    public func isUserAppliedForOpportunity(opportunityId: String, userId: String) async throws -> Bool { false }
    public func getPerformerReviewsByPerformerId(_ performerId: String, limit: Int, lastReviewId: String?) async throws -> [PerformerReview] { [] }
    public nonisolated func getPerformerReviewsByPerformerIdObserver(_ performerId: String, limit: Int) -> AsyncThrowingStream<[PerformerReview], any Error> {
        AsyncThrowingStream { $0.yield([]) }
    }
    public func getBookerReviewsByBookerId(_ bookerId: String, limit: Int, lastReviewId: String?) async throws -> [BookerReview] { [] }
    public nonisolated func getBookerReviewsByBookerIdObserver(_ bookerId: String, limit: Int) -> AsyncThrowingStream<[BookerReview], any Error> {
        AsyncThrowingStream { $0.yield([]) }
    }
    public func isOnPremiumWailist(_ userId: String) async throws -> Bool { premiumWaitlist.contains(userId) }
    public func joinPremiumWaitlist(_ userId: String) async throws { premiumWaitlist.insert(userId) }
    public func publishLatestAppVersion(_ currentUserId: String) async throws -> String {
        let version = AppVersion.current().firestoreValue
        users[currentUserId]?.latestAppVersion = version
        return version
    }
    public func hasUserSentContactRequest(user: UserModel, venue: UserModel) async throws -> Bool { false }
    public func getContactedVenues(_ userId: String) async throws -> [UserModel] { [] }

    // MARK: - not implemented (same surface as FirestoreDatabaseRepository)

    public func deleteUser(_ userId: String) async throws { throw NotImplemented() }
    public func searchUsersByLocation(lat: Double, lng: Double, radiusInMeters: Int, limit: Int, lastUserId: String?) async throws -> [UserModel] { throw NotImplemented() }
    public func classifyPerformer(_ userId: String) async throws -> PerformerCategory? { throw NotImplemented() }
    public func addActivity(currentUserId: String, visitedUserId: String, type: ActivityType) async throws { throw NotImplemented() }
    public func markActivityAsRead(_ activity: Activity) async throws { throw NotImplemented() }
    public func createBooking(_ booking: Booking) async throws { throw NotImplemented() }
    public func getBookingsByEventId(_ eventId: String) async throws -> [Booking] { throw NotImplemented() }
    public func getBookingsByRequesterRequestee(_ requesterId: String, _ requesteeId: String, limit: Int, lastBookingRequestId: String?, status: BookingStatus?) async throws -> [Booking] { throw NotImplemented() }
    public func updateBooking(_ booking: Booking) async throws { throw NotImplemented() }
    public func createService(_ service: Service) async throws { throw NotImplemented() }
    public func updateService(_ service: Service) async throws { throw NotImplemented() }
    public func getServiceById(_ userId: String, _ serviceId: String) async throws -> Service? { throw NotImplemented() }
    public func getUserServices(_ userId: String) async throws -> [Service] { throw NotImplemented() }
    public func deleteService(_ userId: String, _ serviceId: String) async throws { throw NotImplemented() }
    public func getOpportunities(limit: Int, lastOpportunityId: String?) async throws -> [Opportunity] { throw NotImplemented() }
    public func getOpportunityFeedByUserId(_ userId: String, limit: Int, lastOpportunityId: String?) async throws -> [Opportunity] { throw NotImplemented() }
    public func getInterestedUsers(_ opportunity: Opportunity) async throws -> [UserModel] { throw NotImplemented() }
    public func applyForOpportunity(opportunity: Opportunity, userId: String, userComment: String) async throws { throw NotImplemented() }
    public func dislikeOpportunity(opportunity: Opportunity, userId: String) async throws { throw NotImplemented() }
    public func getAppliedOpportunitiesByUserId(_ userId: String, limit: Int, lastOpportunityId: String?) async throws -> [Opportunity] { throw NotImplemented() }
    public func getUserOpportunityQuota(_ userId: String) async throws -> Int { throw NotImplemented() }
    public nonisolated func getUserOpportunityQuotaObserver(_ userId: String) -> AsyncThrowingStream<Int, any Error> {
        AsyncThrowingStream { $0.finish(throwing: NotImplemented()) }
    }
    public func decrementUserOpportunityQuota(_ userId: String) async throws { throw NotImplemented() }
    public func createOpportunity(_ opportunity: Opportunity) async throws { throw NotImplemented() }
    public func copyOpportunityToFeeds(_ opportunity: Opportunity) async throws { throw NotImplemented() }
    public func deleteOpportunity(_ opportunityId: String) async throws { throw NotImplemented() }
    public func blockUser(currentUserId: String, blockedUserId: String) async throws { throw NotImplemented() }
    public func unblockUser(currentUserId: String, blockedUserId: String) async throws { throw NotImplemented() }
    public func isBlocked(currentUserId: String, blockedUserId: String) async throws -> Bool { throw NotImplemented() }
    public func reportUser(reported: UserModel, reporter: UserModel) async throws { throw NotImplemented() }
    public func createPerformerReview(_ review: PerformerReview) async throws { throw NotImplemented() }
    public func getPerformerReviewById(revieweeId: String, reviewId: String) async throws -> PerformerReview? { throw NotImplemented() }
    public func createBookerReview(_ review: BookerReview) async throws { throw NotImplemented() }
    public func getBookerReviewById(revieweeId: String, reviewId: String) async throws -> BookerReview? { throw NotImplemented() }
    public func sendFeedback(_ userId: String, feedback: UserFeedback, imageUrl: String) async throws { throw NotImplemented() }

    // MARK: - helpers

    private func filterBookings(_ predicate: @escaping (Booking) -> Bool) -> (BookingStatus?, Int) -> [Booking] {
        let all = bookings.values
        return { status, limit in
            Array(all.filter { predicate($0) && (status == nil || $0.status == status) }.sorted { $0.startTime > $1.startTime }.prefix(limit))
        }
    }

    private nonisolated func stream<T: Sendable>(_ load: @escaping @Sendable (MockDatabaseRepository) async throws -> [T]) -> AsyncThrowingStream<[T], any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(try await load(self))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
