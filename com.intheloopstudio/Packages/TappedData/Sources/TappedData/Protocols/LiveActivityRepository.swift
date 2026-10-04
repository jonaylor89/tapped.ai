import Foundation
import TappedDomain

/// Starts, updates, and ends the "Gig Night" Live Activity (ActivityKit on device, in-memory in mock mode).
public protocol LiveActivityRepository: Sendable {
    func areActivitiesEnabled() async -> Bool
    /// Running activities keyed by booking id.
    func runningGigNights() async -> [String: GigNightPhase]
    func start(_ gig: GigNight, phase: GigNightPhase) async throws
    func update(_ gig: GigNight, phase: GigNightPhase) async
    func end(bookingId: String) async
    // TODO: send push-to-start tokens to Cloud Functions so the backend can start Gig Night without the app open.
    func pushToStartTokens() -> AsyncStream<String>
}
