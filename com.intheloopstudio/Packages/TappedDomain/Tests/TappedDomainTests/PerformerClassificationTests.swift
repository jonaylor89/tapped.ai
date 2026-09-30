import Foundation
import Testing
@testable import TappedDomain

@Suite("PerformerClassification (categroize.dart)")
struct PerformerClassificationTests {
    let now = Samples.referenceDate
    let day: TimeInterval = 24 * 60 * 60

    private func gig(_ capacity: Int, daysAgo: Double = 0) -> PerformerClassification.VenueCapacity {
        .init(capacity: capacity, startTime: now.addingTimeInterval(-daysAgo * day))
    }

    private func categorize(audience: Int = 0, _ capacities: [PerformerClassification.VenueCapacity]) -> PerformerCategory {
        PerformerClassification.categorizeWithWeightedDate(audience: audience, capacities: capacities, now: now)
    }

    @Test func noGigsIsUndiscoveredRegardlessOfAudience() {
        #expect(categorize(audience: 10_000_000, []) == .undiscovered)
    }

    @Test(arguments: [
        (99, PerformerCategory.undiscovered),
        (100, .emerging),
        (499, .emerging),
        (500, .hometownHero),
        (999, .hometownHero),
        (1000, .mainstream),
        (4999, .mainstream),
        (5000, .legendary),
    ])
    func tierThresholds(capacity: Int, expected: PerformerCategory) {
        #expect(categorize([gig(capacity)]) == expected)
    }

    @Test func audienceIsScaledBy500() {
        // 50 capacity + 25_000 / 500 = 100
        #expect(categorize(audience: 24_999, [gig(50)]) == .undiscovered)
        #expect(categorize(audience: 25_000, [gig(50)]) == .emerging)
    }

    @Test func recentGigsWeighMore() {
        // Weights 1 (5 days ago) and 1/4 (95 days ago): (200 + 2000 / 4) / 1.25 = 560, (2000 + 200 / 4) / 1.25 = 1640.
        #expect(categorize([gig(200, daysAgo: 5), gig(2000, daysAgo: 95)]) == .hometownHero)
        #expect(categorize([gig(2000, daysAgo: 5), gig(200, daysAgo: 95)]) == .mainstream)
    }

    @Test func monthsAreFlooredThirtyDayBuckets() {
        // 29 days ago still weighs 1, 30 days ago weighs 1/2: (1000 * 1 + 0 * 1) / 2 = 500 vs (1000 * 0.5) / 1.5 ≈ 333.
        #expect(categorize([gig(1000, daysAgo: 29), gig(0, daysAgo: 0)]) == .hometownHero)
        #expect(categorize([gig(1000, daysAgo: 30), gig(0, daysAgo: 0)]) == .emerging)
    }

    @Test func futureGigsCountAsNow() {
        // A future gig is clamped to now (weight 1): (600 * 1 + 0 * 1) / 2 = 300.
        #expect(categorize([gig(600, daysAgo: -400), gig(0, daysAgo: 0)]) == .emerging)
    }
}
