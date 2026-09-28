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
