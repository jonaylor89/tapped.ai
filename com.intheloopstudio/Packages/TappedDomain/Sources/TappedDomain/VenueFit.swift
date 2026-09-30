import Foundation

/// `lib/ui/discover/components/venue_fit_utils.dart`: a venue fits a performer when its capacity is within the
/// performer category's suggested max and it books at least one of the performer's genres (case-insensitive).
public struct VenueFit: Sendable, Hashable {
    public var capacityFits: Bool
    /// Venue genres (as stored on the venue) that the performer also plays.
    public var sharedGenres: [String]

    public var isGoodFit: Bool { capacityFits && !sharedGenres.isEmpty }

    public init(venue: UserModel, performer: PerformerInfo?) {
        guard let performer, let venueInfo = venue.venueInfo, let capacity = venueInfo.capacity else {
            capacityFits = false
            sharedGenres = []
            return
        }
        let performerGenres = Set(performer.genres.map { $0.lowercased() })
        capacityFits = performer.category.suggestedMaxCapacity >= capacity
        sharedGenres = venueInfo.genres.filter { performerGenres.contains($0.lowercased()) }
    }

    /// `sortVenuesByFit`: good fits first, otherwise stable.
    public static func sorted(_ venues: [UserModel], for performer: PerformerInfo?) -> [UserModel] {
        venues.enumerated()
            .map { (offset: $0.offset, venue: $0.element, fit: VenueFit(venue: $0.element, performer: performer).isGoodFit) }
            .sorted { $0.fit == $1.fit ? $0.offset < $1.offset : $0.fit }
            .map(\.venue)
    }
}
