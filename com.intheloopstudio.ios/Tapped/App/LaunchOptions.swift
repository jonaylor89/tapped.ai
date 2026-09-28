import Foundation
import TappedUI

/// Mock-mode-only launch environment used for deterministic screenshots and UI checks.
///
/// - `TAPPED_MOCK_SIGNED_IN=1`   start signed in (handled by `Dependencies.resolve`)
/// - `TAPPED_MOCK_SCREEN=splash|login|signup|forgot`  hold the auth gate on a screen
/// - `TAPPED_MOCK_DETENT=collapsed|medium|large`  initial Discover sheet detent
/// - `TAPPED_MOCK_ROUTE=<name>`  push a route on launch (see `Route.mockLaunchPath`)
/// - `TAPPED_MOCK_ROUTE_DETAIL=<value>`  screen-specific extra state (search query, open sheet/results)
struct LaunchOptions: Equatable {
    enum Screen: String {
        case splash, login, signup, forgot
    }

    var screen: Screen?
    var detent: MapsSheetDetent?
    var route: String?
    var routeDetail: String?

    /// Routes `route` resolves to for the mock signed-in user.
    var routes: [Route] { route.flatMap { Route.mockLaunchPath($0) } ?? [] }

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
        return LaunchOptions(
            screen: environment["TAPPED_MOCK_SCREEN"].flatMap(Screen.init(rawValue:)),
            detent: detent,
            route: environment["TAPPED_MOCK_ROUTE"],
            routeDetail: environment["TAPPED_MOCK_ROUTE_DETAIL"]
        )
    }
}
