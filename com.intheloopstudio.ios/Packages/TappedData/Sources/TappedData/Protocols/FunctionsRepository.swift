import Foundation

/// Firebase callable Cloud Functions the Flutter app invokes through `FirebaseFunctions.instance` (default region).
public protocol FunctionsRepository: Sendable {
    /// `OpportunityBloc`: emails the venues after a performer applies to their opportunities.
    func notifyVenueOfInterestedOpportunities(opportunityIds: [String], userId: String, note: String) async throws
}
