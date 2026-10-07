import TappedData

/// Starts OpenTelemetry (spans to PostHog) after the first frame and off the main thread, so it never delays launch.
/// No-op in mock mode or without a PostHog key (`TelemetrySettings.make`).
@MainActor
enum AppTelemetry {
    private static var isStarted = false
    private static var metricKit: MetricKitReporter?

    static func start(config: TappedConfig) {
        guard !isStarted else { return }
        isStarted = true
        Task {
            await FirstFrame.rendered()
            let telemetry = await Task.detached(priority: .utility) {
                TelemetrySettings.make(config: config, app: .current()).map { OpenTelemetryTracing(settings: $0) }
            }.value
            guard let telemetry else { return }
            LaunchSignposts.attach(telemetry)
            let reporter = MetricKitReporter(telemetry: telemetry)
            reporter.start()
            metricKit = reporter
        }
    }
}
