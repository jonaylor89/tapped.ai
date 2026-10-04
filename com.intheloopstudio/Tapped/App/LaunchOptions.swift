import Foundation
import TappedDomain
import TappedUI

/// Mock-mode-only launch environment used for deterministic screenshots and UI checks.
///
/// - `TAPPED_MOCK_SIGNED_IN=1`   start signed in (handled by `Dependencies.resolve`)
/// - `TAPPED_MOCK_SCREEN=splash|login|signup|forgot`  hold the auth gate on a screen
/// - `TAPPED_MOCK_TAB=gigs|bookings|messages|profile|search`  initial shell tab
/// - `TAPPED_MOCK_DETENT=collapsed|medium|large`  initial map sheet detent (applied after the tab/route)
/// - `TAPPED_MOCK_ROUTE=<name>`  open a route on launch via `ShellNavigator.open` (see `Route.mockLaunchPath`)
/// - `TAPPED_MOCK_ROUTE_DETAIL=<value>`  screen-specific extra state (search query, open sheet/results)
/// - `TAPPED_MOCK_ONBOARDING_STEP=name|genres|location`  open onboarding on a
///   step with sample answers filled in (combine with `TAPPED_MOCK_ONBOARDING=1`)
/// - `TAPPED_MOCK_SHEET=reauth`  present the re-authentication sheet over the shell
/// - `TAPPED_MOCK_LINK=<url>`  deliver a deep link on launch (cold start)
struct LaunchOptions: Equatable {
    enum Screen: String {
        case splash, login, signup, forgot
    }

    enum Sheet: String {
        case reauth
    }

    var screen: Screen?
    var tab: ShellTab?
    var detent: MapsSheetDetent?
    var route: String?
    var routeDetail: String?

    /// Routes `route` resolves to for the mock signed-in user.
    var routes: [Route] { route.flatMap { Route.mockLaunchPath($0) } ?? [] }
    var onboardingStep: OnboardingViewModel.Step?
    var sheet: Sheet?
    var link: URL?

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
            tab: environment["TAPPED_MOCK_TAB"].flatMap(ShellTab.init(rawValue:)),
            detent: detent,
            route: environment["TAPPED_MOCK_ROUTE"],
            routeDetail: environment["TAPPED_MOCK_ROUTE_DETAIL"],
            onboardingStep: environment["TAPPED_MOCK_ONBOARDING_STEP"].flatMap(OnboardingViewModel.Step.init(rawValue:)),
            sheet: environment["TAPPED_MOCK_SHEET"].flatMap(Sheet.init(rawValue:)),
            link: environment["TAPPED_MOCK_LINK"].flatMap(URL.init(string:))
        )
    }
}
