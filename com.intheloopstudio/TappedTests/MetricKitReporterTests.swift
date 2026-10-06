import Foundation
import TappedData
import Testing
@testable import Tapped

@Suite("MetricKit reporter")
struct MetricKitReporterTests {
    @Test func histogramsReduceToTheirWeightedMean() {
        #expect(AppMetricsSummary.weightedMean([]) == nil)
        #expect(AppMetricsSummary.weightedMean([(midpointMs: 100, count: 0)]) == nil)
        #expect(AppMetricsSummary.weightedMean([(midpointMs: 100, count: 3), (midpointMs: 500, count: 1)]) == 200)
    }

    @Test func summaryFlattensToAnalyticsProperties() {
        let start = Date(timeIntervalSince1970: 0)
        let summary = AppMetricsSummary(
            appVersion: "2.0.0",
            periodStart: start,
            periodEnd: start.addingTimeInterval(24 * 3600),
            launchTimeToFirstDrawMs: 812.345,
            hangTimeMs: 250,
            peakMemoryMB: 180.04
        )
        #expect(summary.properties == [
            "app_version": "2.0.0",
            "period_hours": 24.0,
            "launch_time_to_first_draw_ms": 812.3,
            "hang_time_ms": 250.0,
            "peak_memory_mb": 180.0,
        ])
        #expect(AppHangSummary(durationMs: 1234.5, appVersion: "2.0.0").properties == ["duration_ms": 1235.0, "app_version": "2.0.0"])
    }

    @Test func payloadsAreForwardedToAnalytics() async throws {
        let analytics = MockAnalytics()
        let reporter = MetricKitReporter(analytics: analytics)
        reporter.report([AppMetricsSummary(appVersion: "2.0.0", periodStart: .now, periodEnd: .now)])
        reporter.report(hangs: [AppHangSummary(durationMs: 400, appVersion: "2.0.0")])
        for _ in 0..<200 where await analytics.events.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(Set(await analytics.events) == [MetricKitReporter.metricsEvent, MetricKitReporter.hangEvent])
    }
}
