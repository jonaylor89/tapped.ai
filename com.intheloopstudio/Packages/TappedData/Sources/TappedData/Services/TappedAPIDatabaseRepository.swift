import FirebaseAuth
import Foundation
import TappedDomain

/// API-only replacement for the live Firestore repository. No dual writes or legacy fallback.
public struct TappedAPIDatabaseRepository: DatabaseRepository {
    let client: TappedAPIDataClient
    public init(baseURL: URL, session: URLSession = .shared,
                idToken: @escaping TappedAPIDataClient.IDTokenProvider = {
                    try await Auth.auth().currentUser?.getIDToken()
                }) {
        client = TappedAPIDataClient(baseURL: baseURL, session: session, idToken: idToken)
    }

    private func get<T: Decodable>(_ table: String, _ id: String, query: [String: String] = [:]) async throws -> T? {
        try await client.read(["data", table, id], query: query)
    }
    private func list<T: Decodable>(_ table: String, _ query: [String: String] = [:],
                                    limit: Int = 100, after: String? = nil) async throws -> [T] {
        var query = query
        query["limit"] = String(min(max(limit, 1), 500))
        query["after"] = after
        return try await client.read(["data", table], query: query) ?? []
    }
    private func save<T: Encodable>(_ table: String, id: String, value: T, create: Bool) async throws {
        try await client.send(create ? ["data",table] : ["data",table,id], method: create ? "POST" : "PUT", value: value)
    }
    private func delete(_ table: String, _ id: String) async throws {
        _ = try await client.request(["data",table,id], method: "DELETE")
    }
    public func publishLatestAppVersion(_ currentUserId: String) async throws -> String {
        let version = AppVersion.current().firestoreValue
        try await client.send(["data","users",currentUserId], method: "PUT", value: ["latestAppVersion":version])
        return version
    }
    // Email enumeration is intentionally removed; Firebase Auth handles duplicate identities.
    public func userEmailExists(_ email: String) async throws -> Bool { false }
    private func saveUser(_ user: UserModel, create: Bool) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try JSONSerialization.jsonObject(with: encoder.encode(user)) as! [String: Any]
        let allowed: Set<String> = ["id","username","artistName","bio","occupations","profilePicture",
            "location","performerInfo","venueInfo","bookerInfo","socialFollowing","emailNotifications",
            "pushNotifications","latestAppVersion","timestamp","deleted","website","phoneNumber"]
        object = object.filter { allowed.contains($0.key) }
        _ = try await client.request(create ? ["data","users"] : ["data","users",user.id],
                                     method: create ? "POST" : "PUT", body: JSONSerialization.data(withJSONObject: object))
    }
    public func createUser(_ user: UserModel) async throws { try await saveUser(user,create:true) }
    public func updateUserData(_ user: UserModel) async throws { try await saveUser(user,create:false) }
    public func deleteUser(_ userId: String) async throws { try await delete("users",userId) }
    public func getUserById(_ userId: String) async throws -> UserModel? { try await get("users",userId) }
    public func getUserByUsername(_ username: String?) async throws -> UserModel? {
        guard let username else { return nil }
        return try await client.read(["users","username",username], authenticated:false)
    }
    public func classifyPerformer(_ userId: String) async throws -> PerformerCategory? { try await computePerformerCategory(userId) }
    public func checkUsernameAvailability(_ username: String, userId: String) async throws -> Bool {
        try await client.read(["username-availability",username]) ?? false
    }
    // Curated leaderboards/badges were not migrated; deliberately disabled.
    public func getBookingLeaders() async throws -> [UserModel] { [] }
    public func getBookerLeaders() async throws -> [UserModel] { [] }
    public func getFeaturedPerformers() async throws -> [UserModel] { [] }
    public func getFeaturedOpportunities() async throws -> [Opportunity] {
        try await getOpportunities(limit:20,lastOpportunityId:nil)
    }
    public func isVerified(_ userId: String) async throws -> Bool { false }
    public func getActivities(_ userId: String, limit: Int, lastActivityId: String?) async throws -> [Activity] {
        try await list("activities",["userId":userId],limit:limit,after:lastActivityId)
    }
    public func activitiesObserver(_ userId: String, limit: Int) -> AsyncThrowingStream<[Activity], any Error> {
        apiPolling { try await getActivities(userId,limit:limit,lastActivityId:nil) }
    }
    public func addActivity(currentUserId: String, visitedUserId: String, type: ActivityType) async throws {
        let value = Activity.follow(.init(common:.init(id:UUID().uuidString,toUserId:visitedUserId,timestamp:.now),fromUserId:currentUserId))
        guard type == .follow else { throw APIFeatureUnavailable.disabled("client-generated booking notifications") }
        try await save("activities",id:value.id,value:value,create:true)
    }
    public func markActivityAsRead(_ activity: Activity) async throws {
        try await client.send(["data","activities",activity.id],method:"PUT",value:["markedRead":true])
    }
    public func createBooking(_ booking: Booking) async throws { try await save("bookings",id:booking.id,value:booking,create:true) }
    public func updateBooking(_ booking: Booking) async throws { try await save("bookings",id:booking.id,value:booking,create:false) }
    public func getBookingById(_ bookRequestId: String) async throws -> Booking? { try await get("bookings",bookRequestId) }
    public func getBookingsByEventId(_ eventId: String) async throws -> [Booking] {
        var results: [Booking] = []
        var after: String?
        repeat {
            let page: [Booking] = try await list("bookings",["referenceEventId":eventId],limit:500,after:after)
            results += page
            after = page.count == 500 ? page.last?.id : nil
        } while after != nil
        return results
    }
    public func getBookingsByRequesterRequestee(_ requesterId: String, _ requesteeId: String, limit: Int, lastBookingRequestId: String?, status: BookingStatus?) async throws -> [Booking] {
        var q = ["requesterId":requesterId,"requesteeId":requesteeId]
        q["status"] = status?.rawValue
        return try await list("bookings",q,limit:limit,after:lastBookingRequestId)
    }
    public func getBookingsByRequester(_ userId: String, limit: Int, lastBookingRequestId: String?, status: BookingStatus?) async throws -> [Booking] {
        var q = ["requesterId":userId]; q["status"] = status?.rawValue
        return try await list("bookings",q,limit:limit,after:lastBookingRequestId)
    }
    public func getBookingsByRequestee(_ userId: String, limit: Int, lastBookingRequestId: String?, status: BookingStatus?) async throws -> [Booking] {
        var q = ["requesteeId":userId]; q["status"] = status?.rawValue
        return try await list("bookings",q,limit:limit,after:lastBookingRequestId)
    }
    public func getBookingsByRequesterObserver(_ userId: String, limit: Int, status: BookingStatus?) -> AsyncThrowingStream<[Booking], any Error> {
        apiPolling { try await getBookingsByRequester(userId,limit:limit,lastBookingRequestId:nil,status:status) }
    }
    public func getBookingsByRequesteeObserver(_ userId: String, limit: Int, status: BookingStatus?) -> AsyncThrowingStream<[Booking], any Error> {
        apiPolling { try await getBookingsByRequestee(userId,limit:limit,lastBookingRequestId:nil,status:status) }
    }
    public func createService(_ service: Service) async throws { try await save("services",id:service.id,value:service,create:true) }
    public func updateService(_ service: Service) async throws { try await save("services",id:service.id,value:service,create:false) }
    public func getServiceById(_ userId: String, _ serviceId: String) async throws -> Service? {
        let service: Service? = try await get("services",serviceId)
        return service?.userId == userId ? service : nil
    }
    public func getUserServices(_ userId: String) async throws -> [Service] { try await list("services",["userId":userId],limit:500) }
    public func deleteService(_ userId: String, _ serviceId: String) async throws { try await delete("services",serviceId) }
    public func getOpportunityById(_ opportunityId: String) async throws -> Opportunity? { try await get("opportunities",opportunityId) }
    public func getOpportunities(limit: Int, lastOpportunityId: String?) async throws -> [Opportunity] { try await list("opportunities",limit:limit,after:lastOpportunityId) }
    public func getOpportunitiesByUserId(_ userId: String, limit: Int, lastOpportunityId: String?) async throws -> [Opportunity] {
        try await list("opportunities",["userId":userId],limit:limit,after:lastOpportunityId)
    }
    public func getOpportunityFeedByUserId(_ userId: String, limit: Int, lastOpportunityId: String?) async throws -> [Opportunity] {
        try await list("opportunities",["userId":userId,"mode":"feed"],limit:limit,after:lastOpportunityId)
    }
    public func getAppliedOpportunitiesByUserId(_ userId: String, limit: Int, lastOpportunityId: String?) async throws -> [Opportunity] {
        try await list("opportunities",["userId":userId,"mode":"applied"],limit:limit,after:lastOpportunityId)
    }
    public func isUserAppliedForOpportunity(opportunityId: String, userId: String) async throws -> Bool {
        try await client.read(["opportunities",opportunityId,"interest"]) ?? false
    }
    public func getInterestedUsers(_ opportunity: Opportunity) async throws -> [UserModel] {
        try await client.read(["public","opportunities",opportunity.id,"interests"],authenticated:false) ?? []
    }
    public func applyForOpportunity(opportunity: Opportunity, userId: String, userComment: String) async throws {
        try await client.send(["opportunities",opportunity.id,"interest"],method:"PUT",value:["action":"apply","userComment":userComment])
    }
    public func dislikeOpportunity(opportunity: Opportunity, userId: String) async throws {
        try await client.send(["opportunities",opportunity.id,"interest"],method:"PUT",value:["action":"dislike"])
    }
    // Legacy credits/quota billing is disabled; API applications are not metered at this cutover.
    public func getUserOpportunityQuota(_ userId: String) async throws -> Int { Int.max }
    public func getUserOpportunityQuotaObserver(_ userId: String) -> AsyncThrowingStream<Int, any Error> {
        AsyncThrowingStream { $0.yield(Int.max); $0.finish() }
    }
    public func decrementUserOpportunityQuota(_ userId: String) async throws {}
    public func createOpportunity(_ opportunity: Opportunity) async throws { try await save("opportunities",id:opportunity.id,value:opportunity,create:true) }
    // Feeds are SQL queries now, not duplicated records per user.
    public func copyOpportunityToFeeds(_ opportunity: Opportunity) async throws {}
    public func deleteOpportunity(_ opportunityId: String) async throws { try await delete("opportunities",opportunityId) }
    // Unmigrated safety/support data never silently writes to Firestore.
    public func blockUser(currentUserId: String, blockedUserId: String) async throws { throw APIFeatureUnavailable.disabled("blocking") }
    public func unblockUser(currentUserId: String, blockedUserId: String) async throws { throw APIFeatureUnavailable.disabled("blocking") }
    public func isBlocked(currentUserId: String, blockedUserId: String) async throws -> Bool { throw APIFeatureUnavailable.disabled("blocking") }
    public func reportUser(reported: UserModel, reporter: UserModel) async throws { throw APIFeatureUnavailable.disabled("in-app reports; contact support@tapped.ai") }
    public func createPerformerReview(_ review: PerformerReview) async throws { try await save("reviews",id:review.id,value:review,create:true) }
    public func createBookerReview(_ review: BookerReview) async throws { try await save("reviews",id:review.id,value:review,create:true) }
    public func getPerformerReviewById(revieweeId: String, reviewId: String) async throws -> PerformerReview? {
        let review: PerformerReview? = try await get("reviews",reviewId,query:["reviewType":"performer","userId":revieweeId])
        return review?.fields.performerId == revieweeId ? review : nil
    }
    public func getBookerReviewById(revieweeId: String, reviewId: String) async throws -> BookerReview? {
        let review: BookerReview? = try await get("reviews",reviewId,query:["reviewType":"booker","userId":revieweeId])
        return review?.fields.bookerId == revieweeId ? review : nil
    }
    public func getPerformerReviewsByPerformerId(_ performerId: String, limit: Int, lastReviewId: String?) async throws -> [PerformerReview] {
        try await list("reviews",["userId":performerId,"reviewType":"performer"],limit:limit,after:lastReviewId)
    }
    public func getBookerReviewsByBookerId(_ bookerId: String, limit: Int, lastReviewId: String?) async throws -> [BookerReview] {
        try await list("reviews",["userId":bookerId,"reviewType":"booker"],limit:limit,after:lastReviewId)
    }
    public func getPerformerReviewsByPerformerIdObserver(_ performerId: String, limit: Int) -> AsyncThrowingStream<[PerformerReview], any Error> {
        apiPolling { try await getPerformerReviewsByPerformerId(performerId,limit:limit,lastReviewId:nil) }
    }
    public func getBookerReviewsByBookerIdObserver(_ bookerId: String, limit: Int) -> AsyncThrowingStream<[BookerReview], any Error> {
        apiPolling { try await getBookerReviewsByBookerId(bookerId,limit:limit,lastReviewId:nil) }
    }
    public func joinPremiumWaitlist(_ userId: String) async throws { throw APIFeatureUnavailable.disabled("premium waitlist") }
    public func isOnPremiumWailist(_ userId: String) async throws -> Bool { false }
    // Historical contactVenues flags were not migrated. Actual outreach is deduplicated by the API mail store.
    public func hasUserSentContactRequest(user: UserModel, venue: UserModel) async throws -> Bool { false }
    public func getContactedVenues(_ userId: String) async throws -> [UserModel] { [] }
}
