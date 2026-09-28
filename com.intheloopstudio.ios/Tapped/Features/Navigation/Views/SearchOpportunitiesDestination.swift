import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Session-4 destinations: search, advanced search, gig search, location form, opportunities, feed, reviews.
struct SearchOpportunitiesDestination: View {
    let route: Route
    @Environment(\.dependencies) private var dependencies
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    var body: some View {
        if let user = session.currentUser {
            destination(currentUser: user)
        } else {
            ErrorView("sign in to continue")
        }
    }

    /// Mock-launch extra state, only for the screen `TAPPED_MOCK_ROUTE` pushed.
    private var launchDetail: String? {
        session.launchOptions.routes.last == route ? session.launchOptions.routeDetail : nil
    }

    @ViewBuilder
    private func destination(currentUser: UserModel) -> some View {
        switch route {
        case .search:
            SearchView(dependencies: dependencies, currentUser: currentUser, initialQuery: launchDetail ?? "")
        case .advancedSearch:
            AdvancedSearchView(dependencies: dependencies, showsResults: launchDetail != nil)
        case .gigSearch:
            GigSearchView(dependencies: dependencies, currentUser: currentUser, isPremium: session.isPremium, showsResults: launchDetail != nil)
        case let .locationForm(initialPlace):
            LocationFormView(dependencies: dependencies, initialPlace: initialPlace) { _ in router.pop() }
        case let .opportunity(opportunityId, opportunity):
            OpportunityView(
                dependencies: dependencies, currentUser: currentUser, isPremium: session.isPremium, claims: session.claims,
                opportunityId: opportunityId, opportunity: opportunity, showsApplySheet: launchDetail != nil
            )
        case let .opportunities(opportunities):
            OpportunitiesListView(dependencies: dependencies, currentUser: currentUser, isPremium: session.isPremium, opportunities: opportunities)
        case .opportunityFeed:
            OpportunityFeedView(dependencies: dependencies, currentUser: currentUser, isPremium: session.isPremium)
        case let .interestedUsers(opportunity):
            InterestedUsersView(dependencies: dependencies, opportunity: opportunity)
        case let .reviews(userId):
            UserReviewsView(dependencies: dependencies, currentUser: currentUser, userId: userId, isWriting: launchDetail != nil)
        default:
            PlaceholderScreen(title: route.title, owner: route.owner)
        }
    }
}

#Preview {
    let dependencies = Dependencies.mock(signedIn: true)
    let session = AppSession(dependencies: dependencies)
    NavigationStack {
        SearchOpportunitiesDestination(route: .search)
            .tappedRouteDestinations()
    }
    .environment(\.dependencies, dependencies)
    .environment(session)
    .environment(Router())
    .task { await session.run() }
}
