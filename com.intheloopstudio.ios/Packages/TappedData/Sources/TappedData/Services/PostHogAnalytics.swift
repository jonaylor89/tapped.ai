import Foundation
@preconcurrency import PostHog

public struct PostHogAnalytics: AnalyticsRepository {
    public init() {}

    /// Call once at launch (from `AppDelegate`).
    public static func configure(apiKey: String, host: String) {
        guard !apiKey.isEmpty else { return }
        let config = PostHogConfig(apiKey: apiKey, host: host)
        config.captureScreenViews = false
        config.captureApplicationLifecycleEvents = true
        PostHogSDK.shared.setup(config)
    }

    public func identify(userId: String, properties: [String: AnalyticsValue]) async {
        PostHogSDK.shared.identify(userId, userProperties: properties.mapValues(\.anyValue))
    }

    public func track(_ event: String, properties: [String: AnalyticsValue]) async {
        PostHogSDK.shared.capture(event, properties: properties.mapValues(\.anyValue))
    }

    public func screen(_ name: String, properties: [String: AnalyticsValue]) async {
        PostHogSDK.shared.screen(name, properties: properties.mapValues(\.anyValue))
    }

    public func reset() async {
        PostHogSDK.shared.reset()
    }
}
