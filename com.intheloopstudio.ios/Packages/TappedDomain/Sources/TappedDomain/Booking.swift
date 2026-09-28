import Foundation

/// `booking.dart` — `bookings/{id}`.
public struct Booking: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var requesteeId: String
    public var status: BookingStatus
    public var startTime: Date
    public var endTime: Date
    public var timestamp: Date
    public var verified: Bool
    public var requesterId: String?
    public var name: String?
    public var note: String
    /// Cents.
    public var rate: Int
    public var serviceId: String?
    public var addedByUser: Bool
    public var flierUrl: String?
    public var eventUrl: String?
    public var genres: [String]
    public var location: Location?
    public var socialMediaLinks: [String]
    public var referenceEventId: String?

    public init(
        id: String,
        requesteeId: String,
        status: BookingStatus,
        startTime: Date,
        endTime: Date,
        timestamp: Date,
        verified: Bool = false,
        requesterId: String? = nil,
        name: String? = nil,
        note: String = "",
        rate: Int = 0,
        serviceId: String? = nil,
        addedByUser: Bool = false,
        flierUrl: String? = nil,
        eventUrl: String? = nil,
        genres: [String] = [],
        location: Location? = nil,
        socialMediaLinks: [String] = [],
        referenceEventId: String? = nil
    ) {
        self.id = id
        self.requesteeId = requesteeId
        self.status = status
        self.startTime = startTime
        self.endTime = endTime
        self.timestamp = timestamp
        self.verified = verified
        self.requesterId = requesterId
        self.name = name
        self.note = note
        self.rate = rate
        self.serviceId = serviceId
        self.addedByUser = addedByUser
        self.flierUrl = flierUrl
        self.eventUrl = eventUrl
        self.genres = genres
        self.location = location
        self.socialMediaLinks = socialMediaLinks
        self.referenceEventId = referenceEventId
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        requesteeId = try c.decode(String.self, forKey: .requesteeId)
        status = try c.decode(BookingStatus.self, forKey: .status)
        startTime = try c.decode(Date.self, forKey: .startTime)
        endTime = try c.decode(Date.self, forKey: .endTime)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        verified = try c.decode(Bool.self, forKey: .verified, default: false)
        requesterId = c.decodeLossy(String.self, forKey: .requesterId)
        name = c.decodeLossy(String.self, forKey: .name)
        note = try c.decode(String.self, forKey: .note, default: "")
        rate = try c.decode(Int.self, forKey: .rate, default: 0)
        serviceId = c.decodeLossy(String.self, forKey: .serviceId)
        addedByUser = try c.decode(Bool.self, forKey: .addedByUser, default: false)
        flierUrl = c.decodeLossy(String.self, forKey: .flierUrl)
        eventUrl = c.decodeLossy(String.self, forKey: .eventUrl)
        genres = try c.decodeList(String.self, forKey: .genres)
        location = c.decodeLossy(Location.self, forKey: .location)
        socialMediaLinks = try c.decodeList(String.self, forKey: .socialMediaLinks)
        referenceEventId = c.decodeLossy(String.self, forKey: .referenceEventId)
    }
}

public enum BookingStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case pending
    case confirmed
    case canceled
}
