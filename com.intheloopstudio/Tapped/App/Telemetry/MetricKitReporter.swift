import Foundation
import MetricKit
import TappedData

/// Forwards MetricKit's daily launch / hang / memory metrics and hang diagnostics to product analytics.
final class MetricKitReporter: NSObject, MXMetricManagerSubscriber, Sendable {
    static let metricsEvent = "app_metrics"
    static let hangEvent = "app_hang"

    private let analytics: any AnalyticsRepository

    init(analytics: any AnalyticsRepository) {
        self.analytics = analytics
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
                    appVersion: $0.applicationVersion
                )
            }
        }
        report(hangs: hangs)
    }

    func report(_ summaries: [AppMetricsSummary]) {
        let analytics = analytics
        Task {
            for summary in summaries {
                await analytics.track(Self.metricsEvent, properties: summary.properties)
            }
        }
    }

    func report(hangs: [AppHangSummary]) {
        let analytics = analytics
        Task {
            for hang in hangs {
                await analytics.track(Self.hangEvent, properties: hang.properties)
            }
        }
    }
}

/// One MetricKit metric payload (usually a day), flattened to analytics properties. Histograms are reduced to their
/// bucket-weighted mean since PostHog can't take the raw buckets.
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

    var properties: [String: AnalyticsValue] {
        var properties: [String: AnalyticsValue] = [
            "app_version": .string(appVersion),
            "period_hours": .double((periodEnd.timeIntervalSince(periodStart) / 3600).rounded()),
        ]
        let metrics: [(String, Double?)] = [
            ("launch_time_to_first_draw_ms", launchTimeToFirstDrawMs),
            ("launch_optimized_time_to_first_draw_ms", launchOptimizedTimeToFirstDrawMs),
            ("resume_time_ms", resumeTimeMs),
            ("hang_time_ms", hangTimeMs),
            ("peak_memory_mb", peakMemoryMB),
            ("average_suspended_memory_mb", averageSuspendedMemoryMB),
        ]
        for case let (key, value?) in metrics {
            properties[key] = .double((value * 10).rounded() / 10)
        }
        return properties
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

struct AppHangSummary: Sendable, Equatable {
    var durationMs: Double
    var appVersion: String

    var properties: [String: AnalyticsValue] {
        ["duration_ms": .double(durationMs.rounded()), "app_version": .string(appVersion)]
    }
}
