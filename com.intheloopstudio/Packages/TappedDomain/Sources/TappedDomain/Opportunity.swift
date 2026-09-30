import Foundation

/// `opportunity.dart` — `opportunities/{id}`.
public struct Opportunity: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var userId: String
    public var location: Location
    public var timestamp: Date
    public var startTime: Date
    public var endTime: Date
    public var deadline: Date?
    public var title: String
    public var description: String
    public var flierUrl: String?
    public var isPaid: Bool
    public var touched: OpportunityInteraction?
    public var deleted: Bool
    public var genres: [String]
    public var venueId: String?
    public var referenceEventId: String?

    public init(
        id: String,
        userId: String,
        location: Location,
        timestamp: Date,
        startTime: Date,
        endTime: Date,
        deadline: Date? = nil,
        title: String = "",
        description: String = "",
        flierUrl: String? = nil,
        isPaid: Bool = false,
        touched: OpportunityInteraction? = nil,
        deleted: Bool = false,
        genres: [String] = [],
        venueId: String? = nil,
        referenceEventId: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.location = location
        self.timestamp = timestamp
        self.startTime = startTime
        self.endTime = endTime
        self.deadline = deadline
        self.title = title
        self.description = description
        self.flierUrl = flierUrl
        self.isPaid = isPaid
        self.touched = touched
        self.deleted = deleted
        self.genres = genres
        self.venueId = venueId
        self.referenceEventId = referenceEventId
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        userId = try c.decode(String.self, forKey: .userId)
        location = try c.decode(Location.self, forKey: .location)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        startTime = try c.decode(Date.self, forKey: .startTime)
        endTime = try c.decode(Date.self, forKey: .endTime)
        deadline = c.decodeLossy(Date.self, forKey: .deadline)
        title = try c.decode(String.self, forKey: .title, default: "")
        description = try c.decode(String.self, forKey: .description, default: "")
        flierUrl = c.decodeLossy(String.self, forKey: .flierUrl)
        isPaid = try c.decode(Bool.self, forKey: .isPaid, default: false)
        touched = c.decodeLossy(OpportunityInteraction.self, forKey: .touched)
        deleted = try c.decode(Bool.self, forKey: .deleted, default: false)
        genres = try c.decodeList(String.self, forKey: .genres)
        venueId = c.decodeLossy(String.self, forKey: .venueId)
        referenceEventId = c.decodeLossy(String.self, forKey: .referenceEventId)
    }
}

public enum OpportunityInteraction: String, Codable, Sendable, CaseIterable, Hashable {
    case like
    case dislike
}
