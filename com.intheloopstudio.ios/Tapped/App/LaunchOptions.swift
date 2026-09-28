import Foundation
import TappedUI

/// Mock-mode-only launch environment used for deterministic screenshots and UI checks.
///
/// - `TAPPED_MOCK_SIGNED_IN=1`   start signed in (handled by `Dependencies.resolve`)
/// - `TAPPED_MOCK_SCREEN=splash|login|signup|forgot`  hold the auth gate on a screen
/// - `TAPPED_MOCK_DETENT=collapsed|medium|large`  initial Discover sheet detent
/// - `TAPPED_MOCK_ONBOARDING_STEP=name|occupation|genres|location|socials|avatar|complete`  open onboarding on a
///   step with sample answers filled in (combine with `TAPPED_MOCK_ONBOARDING=1`)
/// - `TAPPED_MOCK_SHEET=reauth`  present the re-authentication sheet over the shell
/// - `TAPPED_MOCK_ROUTE=paywall`  push a route on launch (e.g. the premium waitlist gate)
/// - `TAPPED_MOCK_LINK=<url>`  deliver a deep link on launch (cold start)
struct LaunchOptions: Equatable {
    enum Screen: String {
        case splash, login, signup, forgot
    }

    enum Sheet: String {
        case reauth
    }

    var screen: Screen?
    var detent: MapsSheetDetent?
    var onboardingStep: OnboardingViewModel.Step?
    var sheet: Sheet?
    var route: Route?
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
        let route: Route? = switch environment["TAPPED_MOCK_ROUTE"] {
        case "paywall": .paywall
        case "settings": .settings
        default: nil
        }
        return LaunchOptions(
            screen: environment["TAPPED_MOCK_SCREEN"].flatMap(Screen.init(rawValue:)),
            detent: detent,
            onboardingStep: environment["TAPPED_MOCK_ONBOARDING_STEP"].flatMap(OnboardingViewModel.Step.init(rawValue:)),
            sheet: environment["TAPPED_MOCK_SHEET"].flatMap(Sheet.init(rawValue:)),
            route: route,
            link: environment["TAPPED_MOCK_LINK"].flatMap(URL.init(string:))
        )
    }
}
