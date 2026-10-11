import Foundation

/// Non-Firebase runtime configuration, read from the app's Info.plist (`Tapped*` keys).
public struct TappedConfig: Sendable, Hashable {
    public var postHogAPIKey: String
    public var postHogHost: String
    /// StoreKit product IDs that grant the `premium` entitlement.
    public var premiumProductIds: [String]
    /// Dart `TAPPED_API_URL` (`TappedApiClient`).
    public var tappedAPIURL: URL
    /// Stream Chat app key (`lib/main.dart` `StreamChatClient('…')`). Public by design.
    public var streamAPIKey: String
    /// imgproxy host that serves resized Firebase Storage images (`platform/README.md`).
    public var imageProxyURL: URL

    public init(
        postHogAPIKey: String = "",
        postHogHost: String = "https://us.i.posthog.com",
        premiumProductIds: [String] = TappedConfig.defaultPremiumProductIds,
        tappedAPIURL: URL = TappedConfig.defaultTappedAPIURL,
        streamAPIKey: String = TappedConfig.defaultStreamAPIKey,
        imageProxyURL: URL = TappedConfig.defaultImageProxyURL
    ) {
        self.postHogAPIKey = postHogAPIKey
        self.postHogHost = postHogHost
        self.premiumProductIds = premiumProductIds
        self.tappedAPIURL = tappedAPIURL
        self.streamAPIKey = streamAPIKey
        self.imageProxyURL = imageProxyURL
    }

    public static let defaultTappedAPIURL = URL(string: "https://api.tapped.ai")!

    public static let defaultStreamAPIKey = "xyk6dwdsp422"

    public static let defaultImageProxyURL = URL(string: "https://img.tapped.ai")!

    /// App Store Connect's existing Tapped Premium subscription products.
    /// `StoreKit/Tapped.storekit` mirrors them for local testing.
    public static let defaultPremiumProductIds = [
        "prod_2499_1m",
        "prod_11999_1y",
    ]

    static let environmentOverrides = [
        "TappedAPIURL": "TAPPED_API_URL",
        "TappedImageProxyURL": "TAPPED_IMAGE_PROXY_URL",
        "TappedStreamAPIKey": "TAPPED_STREAM_API_KEY",
    ]

    /// Debug builds also accept `TAPPED_API_URL`, `TAPPED_IMAGE_PROXY_URL` and `TAPPED_STREAM_API_KEY`
    /// launch environment overrides, so simulator runs can target a local stack (`platform/local`).
    public static func fromBundle(
        _ bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TappedConfig {
        func string(_ key: String) -> String? {
            #if DEBUG
            if let override = Self.environmentOverrides[key].flatMap({ environment[$0] }), !override.isEmpty {
                return override
            }
            #endif
            guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
                  !value.isEmpty, !value.hasPrefix("$(") else { return nil }
            return value
        }
        let defaults = TappedConfig()
        return TappedConfig(
            postHogAPIKey: string("TappedPostHogAPIKey") ?? "",
            postHogHost: string("TappedPostHogHost") ?? defaults.postHogHost,
            premiumProductIds: (bundle.object(forInfoDictionaryKey: "TappedPremiumProductIds") as? [String]) ?? defaults.premiumProductIds,
            tappedAPIURL: string("TappedAPIURL").flatMap(URL.init(string:)) ?? defaults.tappedAPIURL,
            streamAPIKey: string("TappedStreamAPIKey") ?? defaults.streamAPIKey,
            imageProxyURL: string("TappedImageProxyURL").flatMap(URL.init(string:)) ?? defaults.imageProxyURL
        )
    }
}
