import Foundation
@preconcurrency import FirebaseFunctions

public struct FirebaseFunctionsRepository: FunctionsRepository {
    static let notifyVenueOfInterestedOpportunitiesName = "notifyVenueOfInterestedOpportunities"

    public init() {}

    public func notifyVenueOfInterestedOpportunities(opportunityIds: [String], userId: String, note: String) async throws {
        _ = try await Functions.functions()
            .httpsCallable(Self.notifyVenueOfInterestedOpportunitiesName)
            .call(["opportunityIds": opportunityIds, "userId": userId, "note": note])
    }
}
