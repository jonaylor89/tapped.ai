import Foundation

/// Performance telemetry: OpenTelemetry spans exported to PostHog. Product events stay on `AnalyticsRepository`.
public protocol TelemetryRepository: Sendable {
    /// Exports already-finished spans (children nest under their parent).
    func record(_ spans: [TelemetrySpan]) async
}

/// A finished span, built after the fact so callers never hold SDK objects.
public struct TelemetrySpan: Sendable, Equatable {
    public struct Event: Sendable, Equatable {
        public var name: String
        public var time: Date
        public var attributes: [String: AnalyticsValue]

        public init(name: String, time: Date, attributes: [String: AnalyticsValue] = [:]) {
            self.name = name
            self.time = time
            self.attributes = attributes
        }
    }

    public var name: String
    public var start: Date
    public var end: Date
    public var attributes: [String: AnalyticsValue]
    public var events: [Event]
    public var children: [TelemetrySpan]

    public init(
        name: String,
        start: Date,
        end: Date,
        attributes: [String: AnalyticsValue] = [:],
        events: [Event] = [],
        children: [TelemetrySpan] = []
    ) {
        self.name = name
        self.start = start
        self.end = end
        self.attributes = attributes
        self.events = events
        self.children = children
    }
}
