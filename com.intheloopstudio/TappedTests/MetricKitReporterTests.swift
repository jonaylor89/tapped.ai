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

    @Test func summaryFlattensToSpanAttributes() {
        let start = Date(timeIntervalSince1970: 0)
        let summary = AppMetricsSummary(
            appVersion: "2.0.0",
            periodStart: start,
            periodEnd: start.addingTimeInterval(24 * 3600),
            launchTimeToFirstDrawMs: 812.345,
            hangTimeMs: 250,
            peakMemoryMB: 180.04
        )
        #expect(summary.span == TelemetrySpan(
            name: MetricKitReporter.metricsSpan,
            start: start,
            end: start.addingTimeInterval(24 * 3600),
            attributes: [
                "app.version": "2.0.0",
                "metrickit.period_hours": 24.0,
                "metrickit.launch.time_to_first_draw_ms": 812.3,
                "metrickit.responsiveness.hang_time_ms": 250.0,
                "metrickit.memory.peak_mb": 180.0,
            ]
        ))
    }

    @Test func hangSpanLastsAsLongAsTheHang() {
        let reportedAt = Date(timeIntervalSince1970: 100)
        let hang = AppHangSummary(durationMs: 1234.5, appVersion: "2.0.0", reportedAt: reportedAt)
        #expect(hang.span == TelemetrySpan(
            name: MetricKitReporter.hangSpan,
            start: reportedAt.addingTimeInterval(-1.2345),
            end: reportedAt,
            attributes: ["metrickit.hang.duration_ms": 1235.0, "app.version": "2.0.0"]
        ))
    }

    @Test func payloadsAreExportedAsSpansNotAnalytics() async throws {
        let telemetry = MockTelemetryRepository()
        let reporter = MetricKitReporter(telemetry: telemetry)
        reporter.report([AppMetricsSummary(appVersion: "2.0.0", periodStart: .now, periodEnd: .now)])
        reporter.report(hangs: [AppHangSummary(durationMs: 400, appVersion: "2.0.0", reportedAt: .now)])
        for _ in 0..<200 where telemetry.spans.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(Set(telemetry.spans.map(\.name)) == [MetricKitReporter.metricsSpan, MetricKitReporter.hangSpan])
    }
}
