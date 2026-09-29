import Foundation

/// `venue_info.dart`
public struct VenueInfo: Codable, Sendable, Hashable {
    public var bookingEmail: String?
    public var websiteUrl: String?
    public var autoReply: String?
    public var capacity: Int?
    public var idealPerformerProfile: String?
    public var genres: [String]
    public var venuePhotos: [String]
    public var productionInfo: String?
    public var frontOfHouse: String?
    public var monitors: String?
    public var microphones: String?
    public var lights: String?
    public var type: VenueType
    public var averageTicketPrice: Int?
    public var topPerformerIds: [String]
    public var bookingsByDayOfWeek: [Int]
    public var responseRate: Double?

    public init(
        bookingEmail: String? = nil,
        websiteUrl: String? = nil,
        autoReply: String? = nil,
        capacity: Int? = nil,
        idealPerformerProfile: String? = nil,
        genres: [String] = [],
        venuePhotos: [String] = [],
        productionInfo: String? = nil,
        frontOfHouse: String? = nil,
        monitors: String? = nil,
        microphones: String? = nil,
        lights: String? = nil,
        type: VenueType = .other,
        averageTicketPrice: Int? = nil,
        topPerformerIds: [String] = [],
        bookingsByDayOfWeek: [Int] = [],
        responseRate: Double? = nil
    ) {
        self.bookingEmail = bookingEmail
        self.websiteUrl = websiteUrl
        self.autoReply = autoReply
        self.capacity = capacity
        self.idealPerformerProfile = idealPerformerProfile
        self.genres = genres
        self.venuePhotos = venuePhotos
        self.productionInfo = productionInfo
        self.frontOfHouse = frontOfHouse
        self.monitors = monitors
        self.microphones = microphones
        self.lights = lights
        self.type = type
        self.averageTicketPrice = averageTicketPrice
        self.topPerformerIds = topPerformerIds
        self.bookingsByDayOfWeek = bookingsByDayOfWeek
        self.responseRate = responseRate
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookingEmail = c.decodeLossy(String.self, forKey: .bookingEmail)
        websiteUrl = c.decodeLossy(String.self, forKey: .websiteUrl)
        autoReply = c.decodeLossy(String.self, forKey: .autoReply)
        capacity = c.decodeLossy(Int.self, forKey: .capacity)
        idealPerformerProfile = c.decodeLossy(String.self, forKey: .idealPerformerProfile)
        genres = try c.decodeList(String.self, forKey: .genres)
        venuePhotos = try c.decodeList(String.self, forKey: .venuePhotos)
        productionInfo = c.decodeLossy(String.self, forKey: .productionInfo)
        frontOfHouse = c.decodeLossy(String.self, forKey: .frontOfHouse)
        monitors = c.decodeLossy(String.self, forKey: .monitors)
        microphones = c.decodeLossy(String.self, forKey: .microphones)
        lights = c.decodeLossy(String.self, forKey: .lights)
        type = c.decodeLossy(VenueType.self, forKey: .type) ?? .other
        averageTicketPrice = c.decodeLossy(Int.self, forKey: .averageTicketPrice)
        topPerformerIds = try c.decodeList(String.self, forKey: .topPerformerIds)
        bookingsByDayOfWeek = try c.decodeList(Int.self, forKey: .bookingsByDayOfWeek)
        responseRate = c.decodeLossy(Double.self, forKey: .responseRate)
    }
}

public enum VenueType: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case concertHall
    case bar
    case club
    case restaurant
    case theater
    case arena
    case stadium
    case festival
    case artGallery
    case studio
    case brewery
    case hotel
    case other

    public var id: String { rawValue }
}
