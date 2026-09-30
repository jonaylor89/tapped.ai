import Foundation

/// `lib/utils/categroize.dart`: a performer's category from the capacity of venues they've played (recent gigs
/// weigh more) plus their social audience.
public enum PerformerClassification {
    public struct VenueCapacity: Sendable, Hashable {
        public var capacity: Int
        public var startTime: Date

        public init(capacity: Int, startTime: Date) {
            self.capacity = capacity
            self.startTime = startTime
        }
    }

    /// Dart `categorizeWithWeightedDate`: each gig weighs `1 / (floor(monthsAgo) + 1)` (30-day months, future
    /// gigs count as now); the score is the weighted average capacity plus `audience / 500`.
    public static func categorizeWithWeightedDate(
        audience: Int,
        capacities: [VenueCapacity],
        now: Date = .now
    ) -> PerformerCategory {
        guard !capacities.isEmpty else { return .undiscovered }

        var totalWeightedCapacity = 0.0
        var totalWeight = 0.0
        for venue in capacities {
            let venueDate = venue.startTime < now ? venue.startTime : now
            let days = Int(now.timeIntervalSince(venueDate) / (24 * 60 * 60))
            let months = Double(days) / 30
            let weight = 1 / (months.rounded(.down) + 1)
            totalWeightedCapacity += Double(venue.capacity) * weight
            totalWeight += weight
        }

        let combinedScore = totalWeightedCapacity / totalWeight + Double(audience) / 500
        switch combinedScore {
        case ..<100: return .undiscovered
        case ..<500: return .emerging
        case ..<1000: return .hometownHero
        case ..<5000: return .mainstream
        default: return .legendary
        }
    }
}
