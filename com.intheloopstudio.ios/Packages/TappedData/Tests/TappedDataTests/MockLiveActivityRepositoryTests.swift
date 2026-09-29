import Foundation
import TappedDomain
import Testing
@testable import TappedData

@Suite("MockLiveActivityRepository")
struct MockLiveActivityRepositoryTests {
    let gig = GigNight(bookingId: "b1", venueName: "The Camel", startTime: .now, endTime: .now.addingTimeInterval(3600))

    @Test func startUpdateEnd() async throws {
        let repository = MockLiveActivityRepository()
        try await repository.start(gig, phase: .upcoming)
        #expect(await repository.runningGigNights() == ["b1": .upcoming])
        await repository.update(gig, phase: .review)
        #expect(await repository.runningGigNights() == ["b1": .review])
        await repository.end(bookingId: "b1")
        #expect(await repository.runningGigNights().isEmpty)
        #expect(await repository.ended == ["b1"])
        var tokens = 0
        for await _ in repository.pushToStartTokens() { tokens += 1 }
        #expect(tokens == 0)
    }

    @Test func disabledActivitiesThrow() async {
        let repository = MockLiveActivityRepository(isEnabled: false)
        await #expect(throws: LiveActivityError.disabled) { try await repository.start(gig, phase: .upcoming) }
    }
}
