import Foundation
import os
import TappedData

/// Cold-launch milestones as `OSSignposter` intervals and events (Instruments ▸ Points of Interest, or
/// `XCTOSSignpostMetric` in UI tests). Each one is recorded at most once per process. Once telemetry is attached and
/// the launch interval has ended, the same timings are exported as one `launch` span (see `LaunchTrace`).
@MainActor
enum LaunchSignposts {
    static let subsystem = "com.intheloopstudio"
    static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)

    enum Interval: Hashable, CaseIterable {
        /// `didFinishLaunching` → shell's first frame.
        case launch
        /// Cached Remote Config activated and the maintenance / minimum-version gates checked.
        case remoteConfig
        /// Auth restored and the first phase (signed out, onboarding, shell) chosen.
        case auth
        /// `users/{uid}` read for the signed-in user.
        case userDoc
    }

    enum Milestone: Hashable, CaseIterable {
        case didFinishLaunching
        /// The background Remote Config fetch finished (it no longer blocks launch).
        case remoteConfigFetched
        case shellVisible
        /// The Gigs sheet header has its first map search results.
        case firstGigsResults
        /// The gig feed deck shows its first card.
        case firstFeedCard
    }

    private static var open: [Interval: (state: OSSignpostIntervalState, start: Date)] = [:]
    private static var closed: [Interval: DateInterval] = [:]
    private static var reached: [Milestone: Date] = [:]
    private static var telemetry: (any TelemetryRepository)?
    private static var exported = false

    static func begin(_ interval: Interval) {
        guard open[interval] == nil, closed[interval] == nil else { return }
        let id = signposter.makeSignpostID()
        let state = switch interval {
        case .launch: signposter.beginInterval("Launch", id: id)
        case .remoteConfig: signposter.beginInterval("Remote Config", id: id)
        case .auth: signposter.beginInterval("Auth", id: id)
        case .userDoc: signposter.beginInterval("User Doc", id: id)
        }
        open[interval] = (state, .now)
    }

    static func end(_ interval: Interval) {
        guard let (state, start) = open.removeValue(forKey: interval) else { return }
        let timing = DateInterval(start: start, end: max(start, .now))
        closed[interval] = timing
        switch interval {
        case .launch: signposter.endInterval("Launch", state)
        case .remoteConfig: signposter.endInterval("Remote Config", state)
        case .auth: signposter.endInterval("Auth", state)
        case .userDoc: signposter.endInterval("User Doc", state)
        }
        if exported {
            send([LaunchTrace.span(interval, timing)])
        } else {
            export()
        }
    }

    static func mark(_ milestone: Milestone) {
        guard reached[milestone] == nil else { return }
        let time = Date.now
        reached[milestone] = time
        switch milestone {
        case .didFinishLaunching: signposter.emitEvent("didFinishLaunching")
        case .remoteConfigFetched: signposter.emitEvent("Remote Config Fetched")
        case .shellVisible: signposter.emitEvent("Shell Visible")
        case .firstGigsResults: signposter.emitEvent("First Gigs Results")
        case .firstFeedCard: signposter.emitEvent("First Feed Card")
        }
        if exported, let launch = closed[.launch] {
            send([LaunchTrace.span(milestone, at: time, launchStart: launch.start)])
        }
    }

    /// Hands over the telemetry exporter (started after the first frame); flushes the launch span if it's ready.
    static func attach(_ telemetry: any TelemetryRepository) {
        self.telemetry = telemetry
        export()
    }

    private static func export() {
        guard telemetry != nil, !exported, let launch = closed[.launch] else { return }
        exported = true
        send([LaunchTrace.launchSpan(launch, intervals: closed, milestones: reached)])
    }

    private static func send(_ spans: [TelemetrySpan]) {
        guard let telemetry else { return }
        Task { await telemetry.record(spans) }
    }
}

/// Builds the exported launch spans from the recorded timings.
enum LaunchTrace {
    /// `launch` (didFinishLaunching → shell visible) with the other intervals as children, milestones up to the
    /// shell's first frame as events, and later milestones as `launch.<milestone>` children timed from launch start.
    static func launchSpan(
        _ launch: DateInterval,
        intervals: [LaunchSignposts.Interval: DateInterval],
        milestones: [LaunchSignposts.Milestone: Date]
    ) -> TelemetrySpan {
        let children = LaunchSignposts.Interval.allCases.compactMap { interval in
            interval == .launch ? nil : intervals[interval].map { span(interval, $0) }
        }
        let ordered = LaunchSignposts.Milestone.allCases.compactMap { milestone in
            milestones[milestone].map { (milestone, $0) }
        }
        let events = ordered.filter { $0.1 <= launch.end }.map { TelemetrySpan.Event(name: $0.0.name, time: $0.1) }
        let late = ordered.filter { $0.1 > launch.end }.map { span($0.0, at: $0.1, launchStart: launch.start) }
        return TelemetrySpan(
            name: LaunchSignposts.Interval.launch.spanName,
            start: launch.start,
            end: launch.end,
            attributes: ["launch.duration_ms": .double(durationMs(launch.duration))],
            events: events,
            children: children + late
        )
    }

    static func span(_ interval: LaunchSignposts.Interval, _ timing: DateInterval) -> TelemetrySpan {
        TelemetrySpan(name: interval.spanName, start: timing.start, end: timing.end)
    }

    /// Time from launch start to a milestone, e.g. `launch.first_feed_card`.
    static func span(_ milestone: LaunchSignposts.Milestone, at time: Date, launchStart: Date) -> TelemetrySpan {
        TelemetrySpan(
            name: "launch.\(milestone.name)",
            start: launchStart,
            end: max(launchStart, time),
            attributes: ["launch.time_to_ms": .double(durationMs(time.timeIntervalSince(launchStart)))]
        )
    }

    private static func durationMs(_ seconds: TimeInterval) -> Double {
        (seconds * 1000).rounded()
    }
}

extension LaunchSignposts.Interval {
    var spanName: String {
        switch self {
        case .launch: "launch"
        case .remoteConfig: "launch.remote_config"
        case .auth: "launch.auth"
        case .userDoc: "launch.user_doc"
        }
    }
}

extension LaunchSignposts.Milestone {
    var name: String {
        switch self {
        case .didFinishLaunching: "did_finish_launching"
        case .remoteConfigFetched: "remote_config_fetched"
        case .shellVisible: "shell_visible"
        case .firstGigsResults: "first_gigs_results"
        case .firstFeedCard: "first_feed_card"
        }
    }
}
