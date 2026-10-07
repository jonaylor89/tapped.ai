import Foundation
import TappedData
import Testing
@testable import Tapped

@Suite("Launch trace")
struct LaunchTraceTests {
    let start = Date(timeIntervalSince1970: 1_000)

    func at(_ ms: Double) -> Date { start.addingTimeInterval(ms / 1000) }

    @Test func launchSpanNestsIntervalsAndMilestones() {
        let launch = DateInterval(start: start, end: at(700))
        let span = LaunchTrace.launchSpan(
            launch,
            intervals: [
                .launch: launch,
                .remoteConfig: DateInterval(start: at(5), end: at(40)),
                .auth: DateInterval(start: at(10), end: at(300)),
                .userDoc: DateInterval(start: at(120), end: at(290)),
            ],
            milestones: [
                .didFinishLaunching: start,
                .shellVisible: at(700),
                .remoteConfigFetched: at(900),
                .firstFeedCard: at(1_200),
            ]
        )
        #expect(span.name == "launch")
        #expect(span.start == start)
        #expect(span.end == at(700))
        #expect(span.attributes == ["launch.duration_ms": 700.0])
        #expect(span.events.map(\.name) == ["did_finish_launching", "shell_visible"])
        #expect(span.children.map(\.name) == [
            "launch.remote_config", "launch.auth", "launch.user_doc",
            "launch.remote_config_fetched", "launch.first_feed_card",
        ])
        let feedCard = span.children.last
        #expect(feedCard?.start == start)
        #expect(feedCard?.end == at(1_200))
        #expect(feedCard?.attributes == ["launch.time_to_ms": 1_200.0])
    }

    @Test func signedOutLaunchHasNoUserDocSpan() {
        let launch = DateInterval(start: start, end: at(400))
        let span = LaunchTrace.launchSpan(
            launch,
            intervals: [.launch: launch, .auth: DateInterval(start: at(10), end: at(200))],
            milestones: [:]
        )
        #expect(span.children.map(\.name) == ["launch.auth"])
        #expect(span.events.isEmpty)
    }
}
