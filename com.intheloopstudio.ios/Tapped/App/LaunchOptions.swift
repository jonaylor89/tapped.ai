import Foundation
import TappedDomain
import TappedUI

/// Mock-mode-only launch environment used for deterministic screenshots and UI checks.
///
/// - `TAPPED_MOCK_SIGNED_IN=1`   start signed in (handled by `Dependencies.resolve`)
/// - `TAPPED_MOCK_SCREEN=splash|login|signup|forgot`  hold the auth gate on a screen
/// - `TAPPED_MOCK_DETENT=collapsed|medium|large`  initial Discover sheet detent
/// - `TAPPED_MOCK_ROUTE=paywall|messages|channel|admin|videocall`  push a route on top of Discover once signed in
struct LaunchOptions: Equatable {
    enum Screen: String {
        case splash, login, signup, forgot
    }

    var screen: Screen?
    var detent: MapsSheetDetent?
    var initialRoute: Route?

    static let none = LaunchOptions()

    static var current: LaunchOptions {
        #if DEBUG
        from(ProcessInfo.processInfo.environment)
        #else
        .none
        #endif
    }

    static func from(_ environment: [String: String]) -> LaunchOptions {
        guard environment["TAPPED_MOCK"] == "1" else { return .none }
        let detent: MapsSheetDetent? = switch environment["TAPPED_MOCK_DETENT"] {
        case "collapsed": .collapsed
        case "medium": .medium
        case "large": .large
        default: nil
        }
        let route: Route? = switch environment["TAPPED_MOCK_ROUTE"] {
        case "paywall": .paywall
        case "messages": .messagingChannelList
        case "channel": .streamChannel(channelId: Samples.conversations[0].id)
        case "admin": .admin
        case "videocall": .videoCall
        default: nil
        }
        return LaunchOptions(
            screen: environment["TAPPED_MOCK_SCREEN"].flatMap(Screen.init(rawValue:)),
            detent: detent,
            initialRoute: route
        )
    }
}
