import ActivityKit
import Foundation
import TappedDomain

/// "Gig Night" Live Activity, shared by the app (starts/updates it) and `TappedWidgets` (renders it).
struct GigNightAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var phase: GigNightPhase
    }

    var gig: GigNight
}

extension GigNightAttributes.ContentState {
    /// ActivityKit only re-renders at `staleDate` without the app, so derive the phase from the clock once stale.
    func displayPhase(for gig: GigNight, isStale: Bool, now: Date = .now) -> GigNightPhase {
        guard isStale else { return phase }
        let live = gig.phase(at: now)
        return live == .over ? .review : live
    }
}
