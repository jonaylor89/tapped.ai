import SwiftUI
import TappedData

/// Resolves a `Route` to its screen. Follow-up sessions replace their `PlaceholderScreen` case here.
struct RouteDestination: View {
    let route: Route
    @Environment(\.dependencies) private var dependencies

    var body: some View {
        switch route {
        case .login:
            LoginView(dependencies: dependencies)
        case .signUp:
            SignupView(dependencies: dependencies)
        case .forgotPassword:
            ForgotPasswordView(dependencies: dependencies)
        case .paywall:
            PaywallView(dependencies: dependencies)
        case .messagingChannelList:
            ChannelListView(dependencies: dependencies)
        case let .streamChannel(channelId):
            ChannelView(dependencies: dependencies, conversationId: channelId)
        case .videoCall:
            VideoCallView()
        case .admin:
            AdminView(dependencies: dependencies)
        default:
            PlaceholderScreen(title: route.title, owner: route.owner)
        }
    }
}

extension View {
    /// Registers `Route` destinations on the enclosing `NavigationStack`.
    func tappedRouteDestinations() -> some View {
        navigationDestination(for: Route.self) { RouteDestination(route: $0).trackingScreen($0.title) }
    }

    /// PostHog `screen` event when the view first appears.
    func trackingScreen(_ name: String) -> some View {
        modifier(ScreenTrackingModifier(name: name))
    }
}

private struct ScreenTrackingModifier: ViewModifier {
    let name: String
    @Environment(\.dependencies) private var dependencies

    func body(content: Content) -> some View {
        content.task { await dependencies.analytics.screen(name) }
    }
}
