import Foundation
import MetricKit
import TappedData

/// Exports MetricKit's daily launch / hang / memory metrics and hang diagnostics as OpenTelemetry spans.
final class MetricKitReporter: NSObject, MXMetricManagerSubscriber, Sendable {
    static let metricsSpan = "metrickit.metrics"
    static let hangSpan = "metrickit.hang"

    private let telemetry: any TelemetryRepository

    init(telemetry: any TelemetryRepository) {
        self.telemetry = telemetry
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        report(payloads.map(AppMetricsSummary.init))
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let hangs = payloads.flatMap { payload in
            (payload.hangDiagnostics ?? []).map {
                AppHangSummary(
                    durationMs: $0.hangDuration.converted(to: .milliseconds).value,
                    appVersion: $0.applicationVersion,
                    reportedAt: payload.timeStampEnd
                )
            }
        }
        report(hangs: hangs)
    }

    func report(_ summaries: [AppMetricsSummary]) {
        send(summaries.map(\.span))
    }

    func report(hangs: [AppHangSummary]) {
        send(hangs.map(\.span))
    }

    private func send(_ spans: [TelemetrySpan]) {
        guard !spans.isEmpty else { return }
        let telemetry = telemetry
        Task { await telemetry.record(spans) }
    }
}

/// One MetricKit metric payload (usually a day), flattened to span attributes over the payload's period. Histograms
/// are reduced to their bucket-weighted mean since span attributes are scalars.
struct AppMetricsSummary: Sendable, Equatable {
    var appVersion: String
    var periodStart: Date
    var periodEnd: Date
    var launchTimeToFirstDrawMs: Double?
    var launchOptimizedTimeToFirstDrawMs: Double?
    var resumeTimeMs: Double?
    var hangTimeMs: Double?
    var peakMemoryMB: Double?
    var averageSuspendedMemoryMB: Double?

    var attributes: [String: AnalyticsValue] {
        var attributes: [String: AnalyticsValue] = [
            "app.version": .string(appVersion),
            "metrickit.period_hours": .double((periodEnd.timeIntervalSince(periodStart) / 3600).rounded()),
        ]
        let metrics: [(String, Double?)] = [
            ("metrickit.launch.time_to_first_draw_ms", launchTimeToFirstDrawMs),
            ("metrickit.launch.optimized_time_to_first_draw_ms", launchOptimizedTimeToFirstDrawMs),
            ("metrickit.launch.resume_time_ms", resumeTimeMs),
            ("metrickit.responsiveness.hang_time_ms", hangTimeMs),
            ("metrickit.memory.peak_mb", peakMemoryMB),
            ("metrickit.memory.average_suspended_mb", averageSuspendedMemoryMB),
        ]
        for case let (key, value?) in metrics {
            attributes[key] = .double((value * 10).rounded() / 10)
        }
        return attributes
    }

    var span: TelemetrySpan {
        TelemetrySpan(
            name: MetricKitReporter.metricsSpan,
            start: periodStart,
            end: max(periodStart, periodEnd),
            attributes: attributes
        )
    }
}

extension AppMetricsSummary {
    init(_ payload: MXMetricPayload) {
        self.init(
            appVersion: payload.latestApplicationVersion,
            periodStart: payload.timeStampBegin,
            periodEnd: payload.timeStampEnd,
            launchTimeToFirstDrawMs: payload.applicationLaunchMetrics.flatMap { Self.meanMs($0.histogrammedTimeToFirstDraw) },
            launchOptimizedTimeToFirstDrawMs: payload.applicationLaunchMetrics.flatMap { Self.meanMs($0.histogrammedOptimizedTimeToFirstDraw) },
            resumeTimeMs: payload.applicationLaunchMetrics.flatMap { Self.meanMs($0.histogrammedApplicationResumeTime) },
            hangTimeMs: payload.applicationResponsivenessMetrics.flatMap { Self.meanMs($0.histogrammedApplicationHangTime) },
            peakMemoryMB: payload.memoryMetrics?.peakMemoryUsage.converted(to: .megabytes).value,
            averageSuspendedMemoryMB: payload.memoryMetrics?.averageSuspendedMemory.averageMeasurement.converted(to: .megabytes).value
        )
    }

    private static func meanMs(_ histogram: MXHistogram<UnitDuration>) -> Double? {
        var buckets: [(midpointMs: Double, count: Int)] = []
        for case let bucket as MXHistogramBucket<UnitDuration> in histogram.bucketEnumerator {
            let start = bucket.bucketStart.converted(to: .milliseconds).value
            let end = bucket.bucketEnd.converted(to: .milliseconds).value
            buckets.append(((start + end) / 2, bucket.bucketCount))
        }
        return weightedMean(buckets)
    }

    static func weightedMean(_ buckets: [(midpointMs: Double, count: Int)]) -> Double? {
        let total = buckets.reduce(0) { $0 + $1.count }
        guard total > 0 else { return nil }
        return buckets.reduce(0) { $0 + $1.midpointMs * Double($1.count) } / Double(total)
    }
}

/// MetricKit only reports a hang's duration, so the span ends when its diagnostic payload was delivered.
struct AppHangSummary: Sendable, Equatable {
    var durationMs: Double
    var appVersion: String
    var reportedAt: Date

    var attributes: [String: AnalyticsValue] {
        ["metrickit.hang.duration_ms": .double(durationMs.rounded()), "app.version": .string(appVersion)]
    }

    var span: TelemetrySpan {
        TelemetrySpan(
            name: MetricKitReporter.hangSpan,
            start: reportedAt.addingTimeInterval(-durationMs / 1000),
            end: reportedAt,
            attributes: attributes
        )
    }
}
