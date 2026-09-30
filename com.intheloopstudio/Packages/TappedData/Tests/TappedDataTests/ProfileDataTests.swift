import Foundation
import TappedDomain
import Testing
@testable import TappedData

@Suite("Profile + activity mock data")
struct ProfileDataTests {
    let me = Samples.performer.id

    @Test func activitiesPaginateNewestFirst() async throws {
        let database = MockDatabaseRepository()
        let first = try await database.getActivities(me, limit: 20, lastActivityId: nil)
        #expect(first.count == 20)
        #expect(first.first?.id == "activity-request")
        #expect(zip(first, first.dropFirst()).allSatisfy { $0.common.timestamp >= $1.common.timestamp })
        let second = try await database.getActivities(me, limit: 20, lastActivityId: first.last?.id)
        #expect(second.count == Samples.activities.count - 20)
        #expect(Set(first.map(\.id)).isDisjoint(with: second.map(\.id)))
        #expect(try await database.getActivities("nobody", limit: 20, lastActivityId: nil).isEmpty)
    }

    @Test func markingReadUpdatesObservers() async throws {
        let database = MockDatabaseRepository()
        var iterator = database.activitiesObserver(me, limit: 100).makeAsyncIterator()
        let initial = try #require(try await iterator.next())
        let unread = initial.filter { !$0.common.markedRead }
        #expect(unread.count == 3)

        try await database.markActivityAsRead(unread[0])
        let updated = try #require(try await iterator.next())
        #expect(updated.filter { !$0.common.markedRead }.count == 2)
        #expect(await database.activities[unread[0].id]?.common.markedRead == true)
    }

    @Test func addFollowActivity() async throws {
        let database = MockDatabaseRepository(activities: [])
        try await database.addActivity(currentUserId: "a", visitedUserId: me, type: .follow)
        let activities = try await database.getActivities(me)
        #expect(activities.count == 1)
        guard case let .follow(follow) = activities.first else { Issue.record("expected follow"); return }
        #expect(follow.fromUserId == "a")
        #expect(!follow.common.markedRead)
    }

    @Test func addActivitySupportsEveryType() async throws {
        let database = MockDatabaseRepository(activities: [])
        for type in ActivityType.allCases {
            try await database.addActivity(currentUserId: "a", visitedUserId: me, type: type)
        }
        let activities = try await database.getActivities(me)
        #expect(Set(activities.map(\.type)) == Set(ActivityType.allCases))
        #expect(activities.allSatisfy { $0.common.toUserId == me })
    }

    @Test func servicesSoftDelete() async throws {
        let database = MockDatabaseRepository()
        let services = try await database.getUserServices(me)
        #expect(services.map(\.id) == Samples.services.filter { $0.userId == me }.map(\.id))
        try await database.deleteService(me, services[0].id)
        #expect(try await database.getUserServices(me).map(\.id) == services.dropFirst().map(\.id))
        #expect(try await database.getServiceById(me, services[0].id)?.deleted == true)
        #expect(try await database.getServiceById("someone-else", services[1].id) == nil)
    }

    @Test func blockUnblockAndReport() async throws {
        let database = MockDatabaseRepository()
        #expect(try await !database.isBlocked(currentUserId: me, blockedUserId: "venue-camel"))
        try await database.blockUser(currentUserId: me, blockedUserId: "venue-camel")
        #expect(try await database.isBlocked(currentUserId: me, blockedUserId: "venue-camel"))
        #expect(try await !database.isBlocked(currentUserId: "venue-camel", blockedUserId: me))
        try await database.unblockUser(currentUserId: me, blockedUserId: "venue-camel")
        #expect(try await !database.isBlocked(currentUserId: me, blockedUserId: "venue-camel"))

        try await database.reportUser(reported: Samples.venues[0], reporter: Samples.performer)
        let reports = await database.reports
        #expect(reports.count == 1)
        #expect(reports.first?.reported == "venue-camel")
    }

    @Test func reviewsAreFilteredAndSorted() async throws {
        let database = MockDatabaseRepository()
        let performer = try await database.getPerformerReviewsByPerformerId(me, limit: 10, lastReviewId: nil)
        #expect(performer.map(\.id) == ["review-camel-nova", "review-canal-nova", "review-vagabond-nova"])
        let next = try await database.getPerformerReviewsByPerformerId(me, limit: 10, lastReviewId: performer[0].id)
        #expect(next.map(\.id) == ["review-canal-nova", "review-vagabond-nova"])
        #expect(try await database.getBookerReviewsByBookerId("venue-camel", limit: 1, lastReviewId: nil).count == 1)
    }

    @Test func mockStorageWritesUploads() async throws {
        let storage = MockStorageRepository()
        let url = try await storage.uploadProfilePicture(userId: me, imageData: Data([0xFF, 0xD8, 0xFF]))
        #expect(url.isFileURL)
        #expect(url.lastPathComponent.hasPrefix("userProfile_\(me)_"))
        #expect(try Data(contentsOf: url) == Data([0xFF, 0xD8, 0xFF]))
    }

    @Test func activityRoundTripsThroughCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for activity in Samples.activities.prefix(6) {
            let decoded = try decoder.decode(Activity.self, from: try encoder.encode(activity))
            #expect(decoded == activity)
        }
    }
}
