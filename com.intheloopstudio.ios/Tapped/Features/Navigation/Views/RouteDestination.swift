import SwiftUI
import TappedData
import TappedDomain

/// Resolves a `Route` to its screen. Follow-up sessions replace their `PlaceholderScreen` case here.
struct RouteDestination: View {
    let route: Route
    @Environment(\.dependencies) private var dependencies
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(ShellViewModel.self) private var shell: ShellViewModel?

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
             .requestToPerformConfirmation, .serviceSelection, .service, .createService, .bookingHistory:
            BookingsRouteDestination(route: route)
        default:
            PlaceholderScreen(title: route.title, owner: route.owner)
        }
    }
}

extension View {
    /// Registers `Route` destinations on the enclosing `NavigationStack`.
    func tappedRouteDestinations() -> some View {
        navigationDestination(for: Route.self) { RouteDestination(route: $0) }
    }
}
