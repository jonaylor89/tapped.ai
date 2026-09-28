import Foundation
import TappedData
import TappedDomain

/// Typed mirror of `lib/domains/navigation_bloc/tapped_route.dart`.
///
/// Rules:
/// - One case per Dart `TappedRoute` subclass, same order, same parameter names.
/// - Associated values must be `Hashable` data (Dart `Option<T>` → `T?`). Dart callback parameters
///   (`onSubmit`, `onSelected`, `onApply`, …) are not representable in a value-typed path; the owning
///   session should replace them with a view model result or an `@Observable` shared store.
/// - Destinations are resolved in `RouteDestination`.
enum Route: Hashable {
    case profile(userId: String, user: UserModel?)
    case settings
    case createBooking(requesteeId: String, service: Service?, requesteeStripeConnectedAccountId: String?)
    case booking(Booking)
    case bookingConfirmation(Booking)
    case bookings(userId: String)
    case discovery
    case advancedSearch
    case serviceSelection(userId: String, requesteeStripeConnectedAccountId: String?)
    case createService(service: Service?)
    case locationForm(initialPlace: PlaceData?)
    case reviews(userId: String)
    case activities
    case login
    case forgotPassword
    case signUp
    case onboarding
    case streamChannel(channelId: String)
    case messagingChannelList
    case service(Service, serviceUser: UserModel?)
    case videoCall
    case interestedUsers(Opportunity)
    case opportunity(opportunityId: String, opportunity: Opportunity?)
    case paywall
    case admin
    case search
    case gigSearch
    case requestToPerform(venues: [UserModel], collaborators: [UserModel])
    case requestToPerformConfirmation(venues: [UserModel])
    case addPastBooking
    case image(url: URL)
    case shareProfile(userId: String, user: UserModel?)
    case bookingHistory(UserModel)
    case addCollaborators(maxCollaborators: Int = 5, initialCollaborators: [UserModel] = [])
    case tasks
    /// Native-only: `OpportunitiesResultsView` / `OpportunityFeedView` are pushed without a Dart `TappedRoute`.
    case opportunities([Opportunity])
    case opportunityFeed

    /// Dart `routeName`, lowercased for display.
    var title: String {
        switch self {
        case .profile: "profile"
        case .settings: "settings"
        case .createBooking: "create booking"
        case .booking: "booking"
        case .bookingConfirmation: "booking confirmation"
        case .bookings: "bookings"
        case .discovery: "discover"
        case .advancedSearch: "advanced search"
        case .serviceSelection: "services"
        case .createService: "create service"
        case .locationForm: "location"
        case .reviews: "reviews"
        case .activities: "activity"
        case .login: "login"
        case .forgotPassword: "forgot password"
        case .signUp: "sign up"
        case .onboarding: "onboarding"
        case .streamChannel: "messages"
        case .messagingChannelList: "messages"
        case .service: "service"
        case .videoCall: "video call"
        case .interestedUsers: "interested users"
        case .opportunity: "gig"
        case .paywall: "tapped premium"
        case .admin: "add gig"
        case .search: "search"
        case .gigSearch: "search a city"
        case .requestToPerform: "request to perform"
        case .requestToPerformConfirmation: "request sent"
        case .addPastBooking: "add past booking"
        case .image: "image"
        case .shareProfile: "share profile"
        case .bookingHistory: "booking history"
        case .addCollaborators: "add collaborators"
        case .tasks: "tasks"
        case .opportunities: "opportunities"
        case .opportunityFeed: "gig feed"
        }
    }

    /// Feature session that built the destination (README "Features"). `nil` = the skeleton.
    var owner: Int? {
        switch self {
        case .discovery, .login, .signUp, .forgotPassword: nil
        case .profile, .settings, .shareProfile, .tasks, .activities, .image: 2
        case .bookings, .booking, .bookingConfirmation, .createBooking, .requestToPerform, .requestToPerformConfirmation,
             .serviceSelection, .service, .createService, .bookingHistory, .addPastBooking, .addCollaborators: 3
        case .search, .advancedSearch, .gigSearch, .opportunity, .interestedUsers, .reviews, .locationForm,
             .opportunities, .opportunityFeed: 4
        case .onboarding: 5
        case .paywall, .streamChannel, .messagingChannelList, .videoCall, .admin: 6
        }
    }
}
