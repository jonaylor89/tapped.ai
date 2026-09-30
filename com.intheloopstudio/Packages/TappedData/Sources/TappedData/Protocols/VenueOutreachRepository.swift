import Foundation

/// `lib/data/prod/tapped_api_client.dart`: request-to-perform emails are sent by the Tapped API,
/// which creates the venue email thread (and the `contactVenues` record) server-side.
public protocol VenueOutreachRepository: Sendable {
    /// `POST /app/v1/venue-email-threads`.
    func createVenueEmailThread(id: String, venueId: String, subject: String, textBody: String) async throws
}

public struct VenueEmailThread: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var venueId: String
    public var subject: String
    public var textBody: String

    public init(id: String, venueId: String, subject: String, textBody: String) {
        self.id = id
        self.venueId = venueId
        self.subject = subject
        self.textBody = textBody
    }

    enum CodingKeys: String, CodingKey {
        case id
        case venueId = "venue_id"
        case subject
        case textBody = "text_body"
    }
}
