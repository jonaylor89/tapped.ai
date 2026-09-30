import Foundation
import TappedDomain
import Testing
@testable import TappedData

@Suite("Mock opportunities + reviews")
struct MockOpportunityReviewTests {
    let userId = Samples.performer.id
    let opportunity = Samples.opportunities[0]

    @Test func applyingRecordsInterestAndTouchesTheFeed() async throws {
        let database = MockDatabaseRepository()
        let feed = try await database.getOpportunityFeedByUserId(userId, limit: 20, lastOpportunityId: nil)
        #expect(feed.contains { $0.id == opportunity.id })
        #expect(try await !database.isUserAppliedForOpportunity(opportunityId: opportunity.id, userId: userId))

        try await database.applyForOpportunity(opportunity: opportunity, userId: userId, userComment: "hi")
        #expect(try await database.isUserAppliedForOpportunity(opportunityId: opportunity.id, userId: userId))
        #expect(try await database.getInterestedUsers(opportunity).contains { $0.id == userId })
        #expect(try await database.getAppliedOpportunitiesByUserId(userId, limit: 20, lastOpportunityId: nil).map(\.id) == [opportunity.id])
        let after = try await database.getOpportunityFeedByUserId(userId, limit: 20, lastOpportunityId: nil)
        #expect(!after.contains { $0.id == opportunity.id })
    }

    @Test func dislikingHidesFromTheFeedWithoutApplying() async throws {
        let database = MockDatabaseRepository()
        try await database.dislikeOpportunity(opportunity: opportunity, userId: userId)
        #expect(try await !database.isUserAppliedForOpportunity(opportunityId: opportunity.id, userId: userId))
        #expect(try await !database.getOpportunityFeedByUserId(userId, limit: 20, lastOpportunityId: nil).contains { $0.id == opportunity.id })
    }

    @Test func feedPagesAfterTheLastId() async throws {
        let database = MockDatabaseRepository()
        let all = try await database.getOpportunityFeedByUserId(userId, limit: 20, lastOpportunityId: nil)
        #expect(all.map(\.startTime) == all.map(\.startTime).sorted(by: >))
        let first = try await database.getOpportunityFeedByUserId(userId, limit: 2, lastOpportunityId: nil)
        let second = try await database.getOpportunityFeedByUserId(userId, limit: 2, lastOpportunityId: first.last?.id)
        #expect((first + second).map(\.id) == Array(all.prefix(4)).map(\.id))
    }

    @Test func quotaDecrementsAndStreams() async throws {
        let database = MockDatabaseRepository(defaultOpportunityQuota: 2)
        var iterator = database.getUserOpportunityQuotaObserver(userId).makeAsyncIterator()
        #expect(try await iterator.next() == 2)
        try await database.decrementUserOpportunityQuota(userId)
        #expect(try await iterator.next() == 1)
        try await database.decrementUserOpportunityQuota(userId)
        #expect(try await database.getUserOpportunityQuota(userId) == 0)
    }

    @Test func reviewsRoundTrip() async throws {
        let database = MockDatabaseRepository()
        let seeded = try await database.getPerformerReviewsByPerformerId(userId, limit: 20, lastReviewId: nil)
        #expect(seeded.count == Samples.performerReviews.filter { $0.fields.performerId == userId }.count)
        let review = PerformerReview(fields: ReviewFields(
            id: "new", bookerId: "venue-hardywood", performerId: userId, timestamp: Samples.referenceDate.addingTimeInterval(60), overallRating: 5, overallReview: "great", type: .booker
        ))
        try await database.createPerformerReview(review)
        #expect(try await database.getPerformerReviewById(revieweeId: userId, reviewId: "new")?.fields.type == .performer)
        #expect(try await database.getPerformerReviewsByPerformerId(userId, limit: 1, lastReviewId: nil).first?.id == "new")

        let bookerReview = BookerReview(fields: ReviewFields(
            id: "b", bookerId: "venue-camel", performerId: userId, timestamp: .now, overallRating: 3, overallReview: "ok", type: .performer
        ))
        try await database.createBookerReview(bookerReview)
        #expect(try await database.getBookerReviewById(revieweeId: "venue-camel", reviewId: "b") == bookerReview)
    }

    @Test func mockSearchHonoursRadius() async throws {
        let search = MockSearchRepository()
        let rva = try await search.queryUsers("", filters: .venues(), lat: Location.rva.lat, lng: Location.rva.lng, radius: 50_000, limit: 50)
        #expect(!rva.isEmpty)
        let nyc = try await search.queryUsers("", filters: .venues(), lat: Location.nyc.lat, lng: Location.nyc.lng, radius: 50_000, limit: 50)
        #expect(nyc.allSatisfy { !rva.map(\.id).contains($0.id) })
        #expect(MockSearchRepository.meters(from: (0, 0), to: (0, 1)) > 111_000)
    }
}
