import Foundation

/// `contact_venue_request.dart` — `contactVenues/{userId}/venuesContacted/{venueId}`.
public struct ContactVenueRequest: Codable, Sendable, Hashable, Identifiable {
    public var venue: UserModel
    public var user: UserModel
    public var bookingEmail: String
    public var note: String
    public var timestamp: Date
    public var originalMessageId: String?
    public var latestMessageId: String?
    public var subject: String?
    public var allEmails: [String]
    public var collaborators: [UserModel]
    public var opportunityIds: [String]

    public var id: String { "\(user.id)-\(venue.id)" }

    public init(
        venue: UserModel,
        user: UserModel,
        bookingEmail: String,
        note: String,
        timestamp: Date,
        originalMessageId: String? = nil,
        latestMessageId: String? = nil,
        subject: String? = nil,
        allEmails: [String] = [],
        collaborators: [UserModel] = [],
        opportunityIds: [String] = []
    ) {
        self.venue = venue
        self.user = user
        self.bookingEmail = bookingEmail
        self.note = note
        self.timestamp = timestamp
        self.originalMessageId = originalMessageId
        self.latestMessageId = latestMessageId
        self.subject = subject
        self.allEmails = allEmails
        self.collaborators = collaborators
        self.opportunityIds = opportunityIds
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        venue = try c.decode(UserModel.self, forKey: .venue)
        user = try c.decode(UserModel.self, forKey: .user)
        bookingEmail = try c.decode(String.self, forKey: .bookingEmail)
        note = try c.decode(String.self, forKey: .note)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        originalMessageId = c.decodeLossy(String.self, forKey: .originalMessageId)
        latestMessageId = c.decodeLossy(String.self, forKey: .latestMessageId)
        subject = c.decodeLossy(String.self, forKey: .subject)
        allEmails = try c.decodeList(String.self, forKey: .allEmails)
        collaborators = try c.decode([UserModel].self, forKey: .collaborators, default: [])
        opportunityIds = try c.decodeList(String.self, forKey: .opportunityIds)
    }

    enum CodingKeys: String, CodingKey {
        case venue, user, bookingEmail, note, timestamp, originalMessageId, latestMessageId, subject, allEmails,
             collaborators, opportunityIds
    }
}
