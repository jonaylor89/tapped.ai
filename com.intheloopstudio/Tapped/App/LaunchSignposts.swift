import os

/// Cold-launch milestones as `OSSignposter` intervals and events (Instruments ▸ Points of Interest, or
/// `XCTOSSignpostMetric` in UI tests). Each one is recorded at most once per process.
@MainActor
enum LaunchSignposts {
    static let subsystem = "com.intheloopstudio"
    static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)

    enum Interval: Hashable {
        /// `didFinishLaunching` → shell's first frame.
        case launch
        /// Cached Remote Config activated and the maintenance / minimum-version gates checked.
        case remoteConfig
        /// Auth restored and the first phase (signed out, onboarding, shell) chosen.
        case auth
        /// `users/{uid}` read for the signed-in user.
        case userDoc
    }

    enum Milestone: Hashable {
        case didFinishLaunching
        /// The background Remote Config fetch finished (it no longer blocks launch).
        case remoteConfigFetched
        case shellVisible
        /// The Gigs sheet header has its first map search results.
        case firstGigsResults
        /// The gig feed deck shows its first card.
        case firstFeedCard
    }

    private static var open: [Interval: OSSignpostIntervalState] = [:]
    private static var closed: Set<Interval> = []
    private static var reached: Set<Milestone> = []

    static func begin(_ interval: Interval) {
        guard open[interval] == nil, !closed.contains(interval) else { return }
        let id = signposter.makeSignpostID()
        open[interval] = switch interval {
        case .launch: signposter.beginInterval("Launch", id: id)
        case .remoteConfig: signposter.beginInterval("Remote Config", id: id)
        case .auth: signposter.beginInterval("Auth", id: id)
        case .userDoc: signposter.beginInterval("User Doc", id: id)
        }
    }

    static func end(_ interval: Interval) {
        guard let state = open.removeValue(forKey: interval) else { return }
        closed.insert(interval)
        switch interval {
        case .launch: signposter.endInterval("Launch", state)
        case .remoteConfig: signposter.endInterval("Remote Config", state)
        case .auth: signposter.endInterval("Auth", state)
        case .userDoc: signposter.endInterval("User Doc", state)
        }
    }

    static func mark(_ milestone: Milestone) {
        guard reached.insert(milestone).inserted else { return }
        switch milestone {
        case .didFinishLaunching: signposter.emitEvent("didFinishLaunching")
        case .remoteConfigFetched: signposter.emitEvent("Remote Config Fetched")
        case .shellVisible: signposter.emitEvent("Shell Visible")
        case .firstGigsResults: signposter.emitEvent("First Gigs Results")
        case .firstFeedCard: signposter.emitEvent("First Feed Card")
        }
    }
}
