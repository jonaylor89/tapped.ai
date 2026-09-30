import Observation
import SwiftUI

/// `NavigationStack` path model for the signed-in shell. Replaces Flutter's `NavigationBloc`.
@Observable
@MainActor
final class Router {
    var path: [Route] = []

    init(path: [Route] = []) {
        self.path = path
    }

    var isAtRoot: Bool { path.isEmpty }

    func push(_ route: Route) {
        path.append(route)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path.removeAll()
    }
}
