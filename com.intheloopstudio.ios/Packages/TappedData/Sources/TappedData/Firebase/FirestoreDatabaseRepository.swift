import Foundation
@preconcurrency import FirebaseFirestore
import TappedDomain

/// `lib/data/prod/firestore_database_impl.dart`.
///
/// Implemented: the subset Discover and the profile header need. Everything else throws `NotImplemented`
/// and is marked `TODO(session-N)` with the owning follow-up session (see README "Screen ownership").
public struct FirestoreDatabaseRepository: DatabaseRepository {
    /// Flutter `tccUserId`: featured gigs always include this account's opportunities.
    static let tccUserId = "yfjw9oCMwPVzAxgENxGxecPcNym1"
    static let verifiedBadgeId = "0aa46576-1fbe-4312-8b69-e2fef3269083"

    public init() {}

    private var db: Firestore { Firestore.firestore() }
    private var users: CollectionReference { db.collection("users") }
    private var activities: CollectionReference { db.collection("activities") }
    private var bookings: CollectionReference { db.collection("bookings") }
    private var leaders: CollectionReference { db.collection("leaderboard") }
    private var reviews: CollectionReference { db.collection("reviews") }
    private var opportunities: CollectionReference { db.collection("opportunities") }
    private var premiumWaitlist: CollectionReference { db.collection("premiumWaitlist") }
    private var contactVenues: CollectionReference { db.collection("contactVenues") }

    // MARK: - implemented

    public func userEmailExists(_ email: String) async throws -> Bool {
        try await !users.whereField("email", isEqualTo: email).limit(to: 1).getDocuments().isEmpty
    }

    public func createUser(_ user: UserModel) async throws {
        try users.document(user.id).setData(from: user, merge: true)
    }

    public func getUserByUsername(_ username: String?) async throws -> UserModel? {
        guard let username else { return nil }
        let snapshot = try await users.whereField("username", isEqualTo: username).limit(to: 1).getDocuments()
        return try snapshot.documents.first?.decoded(UserModel.self)
    }

    public func getUserById(_ userId: String) async throws -> UserModel? {
        let snapshot = try await users.document(userId).getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.decoded(UserModel.self)
    }

    public func updateUserData(_ user: UserModel) async throws {
        try users.document(user.id).setData(from: user, merge: true)
    }

    public func checkUsernameAvailability(_ username: String, userId: String) async throws -> Bool {
        if ["anonymous", "*deleted*"].contains(username) { return false }
        let snapshot = try await users.whereField("username", isEqualTo: username).getDocuments()
        if let first = snapshot.documents.first, first.documentID != userId { return false }
        return true
    }

    public func getBookingLeaders() async throws -> [UserModel] { try await leadersByField("bookingLeaders") }
    public func getBookerLeaders() async throws -> [UserModel] { try await leadersByField("bookerLeaders") }
    public func getFeaturedPerformers() async throws -> [UserModel] { try await leadersByField("featuredPerformers") }

    public func getFeaturedOpportunities() async throws -> [Opportunity] {
        let snapshot = try await leaders.document("leaders").getDocument()
        let ids = snapshot.get("featuredOpportunities") as? [String] ?? []
        let featured = try await ids.concurrentCompactMap { try await self.getOpportunityById($0) }
        let tcc = try await getOpportunitiesByUserId(Self.tccUserId)
        return (featured + tcc).sorted { $0.startTime > $1.startTime }
    }

    public func activitiesObserver(_ userId: String, limit: Int) -> AsyncThrowingStream<[Activity], any Error> {
        activities
            .whereField("toUserId", isEqualTo: userId)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .snapshots(as: Activity.self)
    }

    public func getActivities(_ userId: String, limit: Int, lastActivityId: String?) async throws -> [Activity] {
        var query = activities
            .whereField("toUserId", isEqualTo: userId)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
        if let lastActivityId {
            query = query.start(afterDocument: try await activities.document(lastActivityId).getDocument())
        }
        return try await query.getDocuments().documents.compactMap { try? $0.decoded(Activity.self) }
    }

    public func isVerified(_ userId: String) async throws -> Bool { false }

    public func getBookingById(_ bookRequestId: String) async throws -> Booking? {
        let snapshot = try await bookings.document(bookRequestId).getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.decoded(Booking.self)
    }

    public func getBookingsByRequester(_ userId: String, limit: Int, lastBookingRequestId: String?, status: BookingStatus?) async throws -> [Booking] {
        try await bookingsQuery(field: "requesterId", userId: userId, limit: limit, after: lastBookingRequestId, status: status)
    }

    public func getBookingsByRequesterObserver(_ userId: String, limit: Int, status: BookingStatus?) -> AsyncThrowingStream<[Booking], any Error> {
        bookingsBaseQuery(field: "requesterId", userId: userId, limit: limit, status: status).snapshots(as: Booking.self)
    }

    public func getBookingsByRequestee(_ userId: String, limit: Int, lastBookingRequestId: String?, status: BookingStatus?) async throws -> [Booking] {
        try await bookingsQuery(field: "requesteeId", userId: userId, limit: limit, after: lastBookingRequestId, status: status)
    }

    public func getBookingsByRequesteeObserver(_ userId: String, limit: Int, status: BookingStatus?) -> AsyncThrowingStream<[Booking], any Error> {
        bookingsBaseQuery(field: "requesteeId", userId: userId, limit: limit, status: status).snapshots(as: Booking.self)
    }

    public func getOpportunityById(_ opportunityId: String) async throws -> Opportunity? {
        let snapshot = try await opportunities.document(opportunityId).getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.decoded(Opportunity.self)
    }

    public func getOpportunitiesByUserId(_ userId: String, limit: Int, lastOpportunityId: String?) async throws -> [Opportunity] {
        var query = opportunities
            .whereField("userId", isEqualTo: userId)
            .whereField("deleted", isEqualTo: false)
            .whereField("startTime", isGreaterThanOrEqualTo: Timestamp(date: .now))
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
        if let lastOpportunityId {
            query = query.start(afterDocument: try await opportunities.document(lastOpportunityId).getDocument())
        }
        return try await query.getDocuments().documents.compactMap { try? $0.decoded(Opportunity.self) }
    }

    public func isUserAppliedForOpportunity(opportunityId: String, userId: String) async throws -> Bool {
        try await opportunities.document(opportunityId).collection("interestedUsers").document(userId).getDocument().exists
    }

    public func getPerformerReviewsByPerformerId(_ performerId: String, limit: Int, lastReviewId: String?) async throws -> [PerformerReview] {
        try await reviewsQuery(revieweeId: performerId, subcollection: "performerReviews", limit: limit, after: lastReviewId)
    }

    public func getPerformerReviewsByPerformerIdObserver(_ performerId: String, limit: Int) -> AsyncThrowingStream<[PerformerReview], any Error> {
        reviews.document(performerId).collection("performerReviews")
            .order(by: "timestamp", descending: true).limit(to: limit)
            .snapshots(as: PerformerReview.self)
    }

    public func getBookerReviewsByBookerId(_ bookerId: String, limit: Int, lastReviewId: String?) async throws -> [BookerReview] {
        try await reviewsQuery(revieweeId: bookerId, subcollection: "bookerReviews", limit: limit, after: lastReviewId)
    }

    public func getBookerReviewsByBookerIdObserver(_ bookerId: String, limit: Int) -> AsyncThrowingStream<[BookerReview], any Error> {
        reviews.document(bookerId).collection("bookerReviews")
            .order(by: "timestamp", descending: true).limit(to: limit)
            .snapshots(as: BookerReview.self)
    }

    public func isOnPremiumWailist(_ userId: String) async throws -> Bool {
        try await premiumWaitlist.document(userId).getDocument().exists
    }

    public func joinPremiumWaitlist(_ userId: String) async throws {
        try await premiumWaitlist.document(userId).setData(["timestamp": Timestamp(date: .now)])
    }

    /// Dart writes `PackageInfo` `version+buildNumber`.
    public func publishLatestAppVersion(_ currentUserId: String) async throws -> String {
        let version = AppVersion.current().firestoreValue
        try await users.document(currentUserId).setData(["latestAppVersion": version], merge: true)
        return version
    }

    public func hasUserSentContactRequest(user: UserModel, venue: UserModel) async throws -> Bool {
        try await contactVenues.document(user.id).collection("venuesContacted").document(venue.id).getDocument().exists
    }

    public func getContactedVenues(_ userId: String) async throws -> [UserModel] {
        let ids = try await contactVenues.document(userId).collection("venuesContacted").getDocuments().documents.map(\.documentID)
        return try await ids.concurrentCompactMap { try await self.getUserById($0) }
    }

    // MARK: - stubs (owned by follow-up sessions)

    // TODO(session-2): settings → delete account.
    public func deleteUser(_ userId: String) async throws { throw NotImplemented() }
    // TODO(session-4): geohash search (Discover uses Typesense instead).
    public func searchUsersByLocation(lat: Double, lng: Double, radiusInMeters: Int, limit: Int, lastUserId: String?) async throws -> [UserModel] { throw NotImplemented() }
    // TODO(session-5): onboarding → performer classification Cloud Function.
    public func classifyPerformer(_ userId: String) async throws -> PerformerCategory? { throw NotImplemented() }
    // TODO(session-2): activity feed.
    public func addActivity(currentUserId: String, visitedUserId: String, type: ActivityType) async throws { throw NotImplemented() }
    // TODO(session-2): activity feed.
    public func markActivityAsRead(_ activity: Activity) async throws { throw NotImplemented() }
    // TODO(session-3): bookings.
    public func createBooking(_ booking: Booking) async throws { throw NotImplemented() }
    // TODO(session-3): bookings.
    public func getBookingsByEventId(_ eventId: String) async throws -> [Booking] { throw NotImplemented() }
    // TODO(session-3): bookings.
    public func getBookingsByRequesterRequestee(_ requesterId: String, _ requesteeId: String, limit: Int, lastBookingRequestId: String?, status: BookingStatus?) async throws -> [Booking] { throw NotImplemented() }
    // TODO(session-3): bookings.
    public func updateBooking(_ booking: Booking) async throws { throw NotImplemented() }
    // TODO(session-3): services.
    public func createService(_ service: Service) async throws { throw NotImplemented() }
    // TODO(session-3): services.
    public func updateService(_ service: Service) async throws { throw NotImplemented() }
    // TODO(session-3): services.
    public func getServiceById(_ userId: String, _ serviceId: String) async throws -> Service? { throw NotImplemented() }
    // TODO(session-3): services.
    public func getUserServices(_ userId: String) async throws -> [Service] { throw NotImplemented() }
    // TODO(session-3): services.
    public func deleteService(_ userId: String, _ serviceId: String) async throws { throw NotImplemented() }
    // TODO(session-4): opportunities feed.
    public func getOpportunities(limit: Int, lastOpportunityId: String?) async throws -> [Opportunity] { throw NotImplemented() }
    // TODO(session-4): opportunities feed.
    public func getOpportunityFeedByUserId(_ userId: String, limit: Int, lastOpportunityId: String?) async throws -> [Opportunity] { throw NotImplemented() }
    // TODO(session-4): opportunities.
    public func getInterestedUsers(_ opportunity: Opportunity) async throws -> [UserModel] { throw NotImplemented() }
    // TODO(session-4): opportunities.
    public func applyForOpportunity(opportunity: Opportunity, userId: String, userComment: String) async throws { throw NotImplemented() }
    // TODO(session-4): opportunities.
    public func dislikeOpportunity(opportunity: Opportunity, userId: String) async throws { throw NotImplemented() }
    // TODO(session-4): opportunities.
    public func getAppliedOpportunitiesByUserId(_ userId: String, limit: Int, lastOpportunityId: String?) async throws -> [Opportunity] { throw NotImplemented() }
    // TODO(session-4): opportunities quota.
    public func getUserOpportunityQuota(_ userId: String) async throws -> Int { throw NotImplemented() }
    // TODO(session-4): opportunities quota.
    public func getUserOpportunityQuotaObserver(_ userId: String) -> AsyncThrowingStream<Int, any Error> {
        AsyncThrowingStream { $0.finish(throwing: NotImplemented()) }
    }
    // TODO(session-4): opportunities quota.
    public func decrementUserOpportunityQuota(_ userId: String) async throws { throw NotImplemented() }
    // TODO(session-6): admin → add gig.
    public func createOpportunity(_ opportunity: Opportunity) async throws { throw NotImplemented() }
    // TODO(session-6): admin → add gig.
    public func copyOpportunityToFeeds(_ opportunity: Opportunity) async throws { throw NotImplemented() }
    // TODO(session-6): admin.
    public func deleteOpportunity(_ opportunityId: String) async throws { throw NotImplemented() }
    // TODO(session-2): profile → block.
    public func blockUser(currentUserId: String, blockedUserId: String) async throws { throw NotImplemented() }
    // TODO(session-2): profile → block.
    public func unblockUser(currentUserId: String, blockedUserId: String) async throws { throw NotImplemented() }
    // TODO(session-2): profile → block.
    public func isBlocked(currentUserId: String, blockedUserId: String) async throws -> Bool { throw NotImplemented() }
    // TODO(session-2): profile → report.
    public func reportUser(reported: UserModel, reporter: UserModel) async throws { throw NotImplemented() }
    // TODO(session-4): reviews.
    public func createPerformerReview(_ review: PerformerReview) async throws { throw NotImplemented() }
    // TODO(session-4): reviews.
    public func getPerformerReviewById(revieweeId: String, reviewId: String) async throws -> PerformerReview? { throw NotImplemented() }
    // TODO(session-4): reviews.
    public func createBookerReview(_ review: BookerReview) async throws { throw NotImplemented() }
    // TODO(session-4): reviews.
    public func getBookerReviewById(revieweeId: String, reviewId: String) async throws -> BookerReview? { throw NotImplemented() }
    // TODO(session-2): settings → feedback.
    public func sendFeedback(_ userId: String, feedback: UserFeedback, imageUrl: String) async throws { throw NotImplemented() }

    // MARK: - helpers

    private func leadersByField(_ field: String) async throws -> [UserModel] {
        let snapshot = try await leaders.document("leaders").getDocument()
        let usernames = snapshot.get(field) as? [String] ?? []
        return try await usernames.concurrentCompactMap { try await self.getUserByUsername($0) }
    }

    private func bookingsBaseQuery(field: String, userId: String, limit: Int, status: BookingStatus?) -> Query {
        var query: Query = bookings.whereField(field, isEqualTo: userId)
        if let status { query = query.whereField("status", isEqualTo: status.rawValue) }
        return query.order(by: "startTime", descending: true).limit(to: limit)
    }

    private func bookingsQuery(field: String, userId: String, limit: Int, after lastId: String?, status: BookingStatus?) async throws -> [Booking] {
        var query = bookingsBaseQuery(field: field, userId: userId, limit: limit, status: status)
        if let lastId {
            query = query.start(afterDocument: try await bookings.document(lastId).getDocument())
        }
        return try await query.getDocuments().documents.compactMap { try? $0.decoded(Booking.self) }
    }

    private func reviewsQuery<T: Decodable>(revieweeId: String, subcollection: String, limit: Int, after lastId: String?) async throws -> [T] {
        let collection = reviews.document(revieweeId).collection(subcollection)
        var query = collection.order(by: "timestamp", descending: true).limit(to: limit)
        if let lastId {
            query = query.start(afterDocument: try await collection.document(lastId).getDocument())
        }
        return try await query.getDocuments().documents.compactMap { try? $0.decoded(T.self) }
    }
}

// MARK: - Firestore decoding helpers

extension DocumentSnapshot {
    /// Decodes the document, injecting `documentID` as `id` (Dart `fromDoc` does `data['id'] = doc.id`).
    func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        var data = self.data() ?? [:]
        data["id"] = documentID
        return try Firestore.Decoder().decode(T.self, from: data)
    }
}

extension Query {
    /// Wraps `addSnapshotListener` in an `AsyncThrowingStream` that yields the decoded result set for each snapshot
    /// and removes the listener when the consumer stops iterating.
    func snapshots<T: Decodable & Sendable>(as type: T.Type) -> AsyncThrowingStream<[T], any Error> {
        AsyncThrowingStream { continuation in
            let registration = addSnapshotListener { snapshot, error in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                guard let snapshot else { return }
                continuation.yield(snapshot.documents.compactMap { try? $0.decoded(T.self) })
            }
            let box = ListenerBox(registration)
            continuation.onTermination = { _ in box.value.remove() }
        }
    }
}
