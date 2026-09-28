import TappedData
import TappedDomain

extension Route {
    /// `TAPPED_MOCK_ROUTE` names (mock mode only) for deterministic screenshots and UI checks.
    /// `profile:<userId>` opens another user's profile.
    static func mockLaunchPath(_ name: String, currentUser: UserModel = Samples.performer) -> [Route]? {
        if let route = mockLaunch(name, currentUser: currentUser) { return [route] }
        if let path = bookingsMockLaunchPath(name, currentUser: currentUser) { return path }
        let opportunity = Samples.opportunities[0]
        return switch name {
        case "paywall": [.paywall]
        case "search": [.search]
        case "advanced-search": [.advancedSearch]
        case "location-form": [.locationForm(initialPlace: MockPlacesRepository.places.first)]
        case "gig-search": [.gigSearch]
        case "opportunity": [.opportunity(opportunityId: opportunity.id, opportunity: opportunity)]
        case "opportunities": [.opportunities(Samples.opportunities)]
        case "opportunity-feed": [.opportunityFeed]
        case "interested-users": [.interestedUsers(opportunity)]
        case "reviews": [.reviews(userId: Samples.performer.id)]
        case "reviews-venue": [.reviews(userId: Samples.venues[0].id)]
        default: nil
        }
    }

    /// Single-route profile/settings names.
    static func mockLaunch(_ name: String, currentUser: UserModel) -> Route? {
        let parts = name.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first {
        case "profile": return .profile(userId: parts.count > 1 ? parts[1] : currentUser.id, user: parts.count > 1 ? nil : currentUser)
        case "settings": return .settings
        case "activities": return .activities
        case "tasks": return .tasks
        case "shareProfile": return .shareProfile(userId: currentUser.id, user: currentUser)
        default: return nil
        }
    }
}
