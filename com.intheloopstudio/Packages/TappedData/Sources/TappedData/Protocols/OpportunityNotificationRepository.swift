import Foundation

/// Notifies eligible, unclaimed venues after the authenticated performer applies to opportunities.
/// The API derives the performer identity from the Firebase ID token.
public protocol OpportunityNotificationRepository: Sendable {
    func notifyVenueOfInterestedOpportunities(opportunityIds: [String], note: String) async throws
}
