import SwiftUI
import TappedData
import TappedDomain

/// Resolves a `Route` to its screen.
struct RouteDestination: View {
    let route: Route
    @Environment(\.dependencies) private var dependencies
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(ShellViewModel.self) private var shell: ShellViewModel?
    @Environment(Router.self) private var router: Router?

    private var currentUser: UserModel? { session?.currentUser ?? shell?.currentUser }

    var body: some View {
        switch route {
        case .login:
            LoginView(dependencies: dependencies)
        case .signUp:
            SignupView(dependencies: dependencies)
        case .forgotPassword:
            ForgotPasswordView(dependencies: dependencies)
        case let .profile(userId, user):
            if let currentUser {
                ProfileView(dependencies: dependencies, currentUser: currentUser, userId: userId, user: user)
            }
        case .settings:
            if let currentUser { SettingsView(dependencies: dependencies, currentUser: currentUser) }
        case .activities:
            if let currentUser { ActivityView(dependencies: dependencies, currentUser: currentUser) }
        case let .image(url):
            ImageViewerView(url: url)
        case let .shareProfile(userId, user):
            ShareProfileView(dependencies: dependencies, userId: userId, user: user)
        case .tasks:
            if let currentUser { TasksView(dependencies: dependencies, currentUser: currentUser) }
        case .bookings, .booking, .bookingConfirmation, .createBooking, .addPastBooking, .requestToPerform,
             .requestToPerformConfirmation, .serviceSelection, .service, .createService, .bookingHistory, .addCollaborators:
            BookingsRouteDestination(route: route)
        case .search, .advancedSearch, .gigSearch, .locationForm, .opportunity, .opportunities, .opportunityFeed,
             .interestedUsers, .reviews:
            SearchOpportunitiesDestination(route: route)
        case .onboarding:
            OnboardingView(dependencies: dependencies)
        case .paywall:
            PaywallGate { PaywallView(dependencies: dependencies) }
        case .messagingChannelList:
            ChannelListView(dependencies: dependencies)
        case let .streamChannel(channelId):
            ChannelView(dependencies: dependencies, conversationId: channelId)
        case .videoCall:
            VideoCallView()
        case .admin:
            AdminView(dependencies: dependencies)
        case .discovery:
            // Discover is the shell root, so "navigate to discovery" unwinds the stack.
            Color.clear.task { router?.popToRoot() }
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
