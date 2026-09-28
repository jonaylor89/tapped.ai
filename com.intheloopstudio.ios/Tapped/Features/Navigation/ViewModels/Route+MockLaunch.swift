import TappedData
import TappedDomain

extension Route {
    /// `TAPPED_MOCK_ROUTE` values for session-4 screens (screenshots only).
    static func mockLaunchPath(_ name: String) -> [Route]? {
        let opportunity = Samples.opportunities[0]
        return switch name {
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
}
