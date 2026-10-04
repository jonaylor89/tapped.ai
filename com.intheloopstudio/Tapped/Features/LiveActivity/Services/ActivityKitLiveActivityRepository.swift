import ActivityKit
import Foundation
import TappedData
import TappedDomain

/// ActivityKit-backed `LiveActivityRepository`; `MockLiveActivityRepository` is its in-memory twin.
struct ActivityKitLiveActivityRepository: LiveActivityRepository {
    func areActivitiesEnabled() async -> Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func runningGigNights() async -> [String: GigNightPhase] {
        Dictionary(
            Self.running.map { ($0.attributes.gig.bookingId, $0.content.state.phase) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func start(_ gig: GigNight, phase: GigNightPhase) async throws {
        _ = try ActivityKit.Activity.request(attributes: GigNightAttributes(gig: gig), content: Self.content(gig, phase), pushType: nil)
    }

    func update(_ gig: GigNight, phase: GigNightPhase) async {
        for activity in Self.running where activity.attributes.gig.bookingId == gig.bookingId {
            await activity.update(Self.content(gig, phase))
        }
    }

    func end(bookingId: String) async {
        for activity in Self.running where activity.attributes.gig.bookingId == bookingId {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func pushToStartTokens() -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                for await token in ActivityKit.Activity<GigNightAttributes>.pushToStartTokenUpdates {
                    continuation.yield(token.map { String(format: "%02x", $0) }.joined())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static var running: [ActivityKit.Activity<GigNightAttributes>] {
        ActivityKit.Activity<GigNightAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    private static func content(_ gig: GigNight, _ phase: GigNightPhase) -> ActivityContent<GigNightAttributes.ContentState> {
        ActivityContent(
            state: GigNightAttributes.ContentState(phase: phase),
            staleDate: gig.staleDate(for: phase),
            relevanceScore: phase == .upcoming ? 50 : 100
        )
    }
}
