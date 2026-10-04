import Foundation
import TappedDomain

public actor MockLiveActivityRepository: LiveActivityRepository {
    public private(set) var activities: [String: (gig: GigNight, phase: GigNightPhase)] = [:]
    public private(set) var ended: [String] = []
    public var isEnabled: Bool

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    public func areActivitiesEnabled() async -> Bool { isEnabled }

    public func runningGigNights() async -> [String: GigNightPhase] {
        activities.mapValues(\.phase)
    }

    public func start(_ gig: GigNight, phase: GigNightPhase) async throws {
        guard isEnabled else { throw LiveActivityError.disabled }
        activities[gig.bookingId] = (gig, phase)
    }

    public func update(_ gig: GigNight, phase: GigNightPhase) async {
        guard activities[gig.bookingId] != nil else { return }
        activities[gig.bookingId] = (gig, phase)
    }

    public func end(bookingId: String) async {
        guard activities.removeValue(forKey: bookingId) != nil else { return }
        ended.append(bookingId)
    }

    public nonisolated func pushToStartTokens() -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }
}

public enum LiveActivityError: Error, Equatable {
    case disabled
}
