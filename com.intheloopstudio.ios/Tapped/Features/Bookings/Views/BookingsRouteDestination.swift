import SwiftUI
import TappedData
import TappedDomain

/// Session-3 destinations (bookings, booking flows, services). Resolved from `RouteDestination`.
struct BookingsRouteDestination: View {
    let route: Route
    @Environment(\.dependencies) private var dependencies
    @Environment(AppSession.self) private var session

    var body: some View {
        if let user = session.currentUser {
            destination(currentUser: user)
        } else {
            PlaceholderScreen(title: route.title, owner: route.owner)
        }
    }

    @ViewBuilder
    private func destination(currentUser: UserModel) -> some View {
        switch route {
        case let .bookings(userId):
            BookingsView(dependencies: dependencies, userId: userId, currentUser: currentUser)
        case let .booking(booking):
            BookingDetailView(dependencies: dependencies, booking: booking, currentUser: currentUser)
        case let .bookingConfirmation(booking):
            BookingConfirmationView(booking: booking)
        case let .createBooking(requesteeId, service, _):
            CreateBookingView(dependencies: dependencies, currentUser: currentUser, requesteeId: requesteeId, service: service)
        case .addPastBooking:
            AddPastBookingView(dependencies: dependencies, currentUser: currentUser)
        case let .requestToPerform(venues, collaborators):
            RequestToPerformView(dependencies: dependencies, currentUser: currentUser, venues: venues, collaborators: collaborators)
        case let .requestToPerformConfirmation(venues):
            RequestToPerformConfirmationView(venues: venues)
        case let .serviceSelection(userId, _):
            ServiceSelectionView(dependencies: dependencies, userId: userId, currentUser: currentUser)
        case let .service(service, serviceUser):
            ServiceView(dependencies: dependencies, service: service, serviceUser: serviceUser, currentUser: currentUser)
        case let .createService(service):
            CreateServiceView(dependencies: dependencies, service: service, ownerId: currentUser.id)
        case let .bookingHistory(user):
            BookingHistoryView(dependencies: dependencies, user: user, currentUser: currentUser)
        default:
            PlaceholderScreen(title: route.title, owner: route.owner)
        }
    }
}

extension Route {
    /// Steps of the create-booking flow that "done" on the confirmation unwinds.
    var isBookingFlowStep: Bool {
        switch self {
        case .bookingConfirmation, .createBooking, .serviceSelection: true
        default: false
        }
    }

    /// Steps of the request-to-perform flow that "done" on the confirmation unwinds.
    var isRequestToPerformFlowStep: Bool {
        switch self {
        case .requestToPerformConfirmation, .requestToPerform, .addCollaborators: true
        default: false
        }
    }

    /// Bookings/services `TAPPED_MOCK_ROUTE` names (see `Route.mockLaunchPath`).
    static func bookingsMockLaunchPath(_ name: String, currentUser: UserModel) -> [Route]? {
        let mara = Samples.performers.first { $0.id == "performer-mara" }
        switch name {
        case "bookings": return [.bookings(userId: currentUser.id)]
        case "booking": return [.booking(Samples.bookings[0])]
        case "booking-pending": return [.booking(Samples.bookings[1])]
        case "booking-sent": return [.booking(Samples.bookings[2])]
        case "booking-past": return [.booking(Samples.bookings[3])]
        case "booking-confirmation": return [.bookingConfirmation(Samples.bookings[2])]
        case "create-booking":
            return [.createBooking(requesteeId: "performer-mara", service: Samples.services.first { $0.userId == "performer-mara" }, requesteeStripeConnectedAccountId: nil)]
        case "add-past-booking": return [.addPastBooking]
        case "request-to-perform":
            return [.requestToPerform(venues: Array(Samples.venues.prefix(2)), collaborators: mara.map { [$0] } ?? [])]
        case "request-sent": return [.requestToPerformConfirmation(venues: Array(Samples.venues.prefix(2)))]
        case "services": return [.serviceSelection(userId: currentUser.id, requesteeStripeConnectedAccountId: nil)]
        case "services-book": return [.serviceSelection(userId: "performer-mara", requesteeStripeConnectedAccountId: nil)]
        case "service": return [.service(Samples.services[0], serviceUser: currentUser)]
        case "service-book": return [.service(Samples.services[3], serviceUser: mara)]
        case "create-service": return [.createService(service: nil)]
        case "edit-service": return [.createService(service: Samples.services[0])]
        case "history": return [.bookingHistory(currentUser)]
        default: return nil
        }
    }
}
