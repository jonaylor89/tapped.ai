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
    /// `opportunities/{id}/interestedUsers/{userId}.userComment`.
    public private(set) var interestedUsers: [String: [String: String]]
    /// `opportunityFeeds/{userId}/opportunities/{id}.touched`.
    public private(set) var feedInteractions: [String: [String: OpportunityInteraction]]
    /// `credits/{userId}.opportunityQuota`; users without an entry get `defaultOpportunityQuota`.
    public private(set) var opportunityQuotas: [String: Int]
    public var defaultOpportunityQuota: Int
    public private(set) var performerReviews: [PerformerReview]
    public private(set) var bookerReviews: [BookerReview]
    private var quotaContinuations: [UUID: (userId: String, continuation: AsyncThrowingStream<Int, any Error>.Continuation)] = [:]

    public init(
        users: [UserModel] = Samples.performers + Samples.venues,
        opportunities: [Opportunity] = Samples.opportunities,
        bookings: [Booking] = Samples.bookings,
        featuredPerformerIds: [String] = Samples.performers.map(\.id),
        featuredOpportunityIds: [String] = Samples.opportunities.map(\.id),
        applicants: [String: [String]] = Samples.applicants,
        performerReviews: [PerformerReview] = Samples.performerReviews,
        bookerReviews: [BookerReview] = Samples.bookerReviews,
        defaultOpportunityQuota: Int = 3
    ) {
        self.users = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
        self.opportunities = Dictionary(uniqueKeysWithValues: opportunities.map { ($0.id, $0) })
        self.bookings = Dictionary(uniqueKeysWithValues: bookings.map { ($0.id, $0) })
        self.featuredPerformerIds = featuredPerformerIds
        self.featuredOpportunityIds = featuredOpportunityIds
        interestedUsers = applicants.mapValues { ids in Dictionary(uniqueKeysWithValues: ids.map { ($0, "") }) }
        feedInteractions = [:]
        opportunityQuotas = [:]
        self.defaultOpportunityQuota = defaultOpportunityQuota
        self.performerReviews = performerReviews
        self.bookerReviews = bookerReviews
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
    public func isUserAppliedForOpportunity(opportunityId: String, userId: String) async throws -> Bool {
        interestedUsers[opportunityId]?[userId] != nil
    }
    public func getPerformerReviewsByPerformerId(_ performerId: String, limit: Int, lastReviewId: String?) async throws -> [PerformerReview] {
        page(performerReviews.filter { $0.fields.performerId == performerId }.sorted { $0.fields.timestamp > $1.fields.timestamp }, limit: limit, after: lastReviewId)
    }
    public nonisolated func getPerformerReviewsByPerformerIdObserver(_ performerId: String, limit: Int) -> AsyncThrowingStream<[PerformerReview], any Error> {
        stream { try await $0.getPerformerReviewsByPerformerId(performerId, limit: limit, lastReviewId: nil) }
    }
    public func getBookerReviewsByBookerId(_ bookerId: String, limit: Int, lastReviewId: String?) async throws -> [BookerReview] {
        page(bookerReviews.filter { $0.fields.bookerId == bookerId }.sorted { $0.fields.timestamp > $1.fields.timestamp }, limit: limit, after: lastReviewId)
    }
    public nonisolated func getBookerReviewsByBookerIdObserver(_ bookerId: String, limit: Int) -> AsyncThrowingStream<[BookerReview], any Error> {
        stream { try await $0.getBookerReviewsByBookerId(bookerId, limit: limit, lastReviewId: nil) }
    }

    // MARK: - opportunities

    public func getOpportunities(limit: Int, lastOpportunityId: String?) async throws -> [Opportunity] {
        page(opportunities.values.sorted { ($0.timestamp, $0.id) > ($1.timestamp, $1.id) }, limit: limit, after: lastOpportunityId)
    }
    /// Every non-deleted opportunity the user hasn't touched or posted. Unlike Firestore there's no
    /// `startTime >= now` filter, so fixed-date samples stay visible.
    public func getOpportunityFeedByUserId(_ userId: String, limit: Int, lastOpportunityId: String?) async throws -> [Opportunity] {
        let touched = feedInteractions[userId] ?? [:]
        let feed = opportunities.values
            .filter { !$0.deleted && $0.userId != userId && touched[$0.id] == nil }
            .sorted { ($0.startTime, $0.id) > ($1.startTime, $1.id) }
        return page(feed, limit: limit, after: lastOpportunityId)
    }
    public func getInterestedUsers(_ opportunity: Opportunity) async throws -> [UserModel] {
        (interestedUsers[opportunity.id] ?? [:]).keys.sorted().compactMap { users[$0] }
    }
    public func applyForOpportunity(opportunity: Opportunity, userId: String, userComment: String) async throws {
        interestedUsers[opportunity.id, default: [:]][userId] = userComment
        feedInteractions[userId, default: [:]][opportunity.id] = .like
    }
    public func dislikeOpportunity(opportunity: Opportunity, userId: String) async throws {
        feedInteractions[userId, default: [:]][opportunity.id] = .dislike
    }
    public func getAppliedOpportunitiesByUserId(_ userId: String, limit: Int, lastOpportunityId: String?) async throws -> [Opportunity] {
        let liked = (feedInteractions[userId] ?? [:]).filter { $0.value == .like }.keys
        return page(liked.compactMap { opportunities[$0] }.sorted { ($0.startTime, $0.id) > ($1.startTime, $1.id) }, limit: limit, after: lastOpportunityId)
    }
    public func getUserOpportunityQuota(_ userId: String) async throws -> Int {
        opportunityQuotas[userId] ?? defaultOpportunityQuota
    }
    public nonisolated func getUserOpportunityQuotaObserver(_ userId: String) -> AsyncThrowingStream<Int, any Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            Task { await self.registerQuotaObserver(id, userId: userId, continuation: continuation) }
            continuation.onTermination = { _ in Task { await self.removeQuotaObserver(id) } }
        }
    }
    public func decrementUserOpportunityQuota(_ userId: String) async throws {
        let quota = (opportunityQuotas[userId] ?? defaultOpportunityQuota) - 1
        opportunityQuotas[userId] = quota
        for observer in quotaContinuations.values where observer.userId == userId {
            observer.continuation.yield(quota)
        }
    }
    public func setOpportunityQuota(_ quota: Int, for userId: String) {
        opportunityQuotas[userId] = quota
    }

    // MARK: - reviews

    public func createPerformerReview(_ review: PerformerReview) async throws { performerReviews.append(review) }
    public func getPerformerReviewById(revieweeId: String, reviewId: String) async throws -> PerformerReview? {
        performerReviews.first { $0.id == reviewId && $0.fields.performerId == revieweeId }
    }
    public func createBookerReview(_ review: BookerReview) async throws { bookerReviews.append(review) }
    public func getBookerReviewById(revieweeId: String, reviewId: String) async throws -> BookerReview? {
        bookerReviews.first { $0.id == reviewId && $0.fields.bookerId == revieweeId }
    }
    public func isOnPremiumWailist(_ userId: String) async throws -> Bool { false }
    public func hasUserSentContactRequest(user: UserModel, venue: UserModel) async throws -> Bool { false }
    public func getContactedVenues(_ userId: String) async throws -> [UserModel] { [] }

    // MARK: - not implemented (same surface as FirestoreDatabaseRepository)

    public func publishLatestAppVersion(_ currentUserId: String) async throws -> String { throw NotImplemented() }
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
    public func createOpportunity(_ opportunity: Opportunity) async throws { throw NotImplemented() }
    public func copyOpportunityToFeeds(_ opportunity: Opportunity) async throws { throw NotImplemented() }
    public func deleteOpportunity(_ opportunityId: String) async throws { throw NotImplemented() }
    public func blockUser(currentUserId: String, blockedUserId: String) async throws { throw NotImplemented() }
    public func unblockUser(currentUserId: String, blockedUserId: String) async throws { throw NotImplemented() }
    public func isBlocked(currentUserId: String, blockedUserId: String) async throws -> Bool { throw NotImplemented() }
    public func reportUser(reported: UserModel, reporter: UserModel) async throws { throw NotImplemented() }
    public func joinPremiumWaitlist(_ userId: String) async throws { throw NotImplemented() }
    public func sendFeedback(_ userId: String, feedback: UserFeedback, imageUrl: String) async throws { throw NotImplemented() }

    // MARK: - helpers

    private func page<T: Identifiable>(_ items: [T], limit: Int, after lastId: T.ID?) -> [T] {
        var slice = items[...]
        if let lastId, let index = items.firstIndex(where: { $0.id == lastId }) {
            slice = items[(index + 1)...]
        }
        return Array(slice.prefix(limit))
    }

    private func registerQuotaObserver(_ id: UUID, userId: String, continuation: AsyncThrowingStream<Int, any Error>.Continuation) {
        quotaContinuations[id] = (userId, continuation)
        continuation.yield(opportunityQuotas[userId] ?? defaultOpportunityQuota)
    }

    private func removeQuotaObserver(_ id: UUID) {
        quotaContinuations[id] = nil
    }

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
