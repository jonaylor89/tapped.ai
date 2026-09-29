import Foundation
import Observation

/// One navigation stack. Each shell tab owns a `Router` (see `ShellNavigator`); screens push and pop through
/// `@Environment(Router.self)` without knowing which tab they are in.
@Observable
@MainActor
final class Router {
    var path: [Route] = []
    /// Presented as a sheet over the stack instead of pushed (`.paywall`), so the screen behind stays visible.
    var sheet: Route?
    /// Presented full screen (`.videoCall`).
    var fullScreenCover: Route?

    /// Routes that leave this stack (`.discovery`) are handed to the shell.
    @ObservationIgnored var openInShell: (@MainActor (Route) -> Void)?

    init(path: [Route] = []) {
        self.path = path
    }

    var isAtRoot: Bool { path.isEmpty }

    func push(_ route: Route) {
        switch route {
        case .paywall:
            sheet = route
        case .videoCall:
            fullScreenCover = route
        case .discovery:
            if let openInShell { openInShell(route) } else { popToRoot() }
        default:
            path.append(route)
        }
    }

    /// Dismisses a presented route first, then pops the stack.
    func pop() {
        if fullScreenCover != nil {
            fullScreenCover = nil
        } else if sheet != nil {
            sheet = nil
        } else if !path.isEmpty {
            path.removeLast()
        }
    }

    func popToRoot() {
        sheet = nil
        fullScreenCover = nil
        path.removeAll()
    }
}
