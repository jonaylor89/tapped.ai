import Foundation

/// `performer_info.dart`
public struct PerformerInfo: Codable, Sendable, Hashable {
    public var pressKitUrl: String?
    public var genres: [String]
    public var subgenres: [String]
    public var rating: Double?
    public var reviewCount: Int
    public var bookingCount: Int
    public var label: String
    public var bookingAgency: String?
    public var category: PerformerCategory
    public var averageTicketPrice: Int?
    public var averageAttendance: Int?
    public var bookingEmail: String?
    public var chartmetricId: String?

    public init(
        pressKitUrl: String? = nil,
        genres: [String] = [],
        subgenres: [String] = [],
        rating: Double? = 5,
        reviewCount: Int = 0,
        bookingCount: Int = 0,
        label: String = "Independent",
        bookingAgency: String? = nil,
        category: PerformerCategory = .undiscovered,
        averageTicketPrice: Int? = nil,
        averageAttendance: Int? = nil,
        bookingEmail: String? = nil,
        chartmetricId: String? = nil
    ) {
        self.pressKitUrl = pressKitUrl
        self.genres = genres
        self.subgenres = subgenres
        self.rating = rating
        self.reviewCount = reviewCount
        self.bookingCount = bookingCount
        self.label = label
        self.bookingAgency = bookingAgency
        self.category = category
        self.averageTicketPrice = averageTicketPrice
        self.averageAttendance = averageAttendance
        self.bookingEmail = bookingEmail
        self.chartmetricId = chartmetricId
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pressKitUrl = c.decodeLossy(String.self, forKey: .pressKitUrl)
        genres = try c.decodeList(String.self, forKey: .genres)
        subgenres = try c.decodeList(String.self, forKey: .subgenres)
        // Dart: `@Default(Option.of(5))` — a missing key means 5, an explicit null means none.
        rating = c.contains(.rating) ? c.decodeLossy(Double.self, forKey: .rating) : 5
        reviewCount = try c.decode(Int.self, forKey: .reviewCount, default: 0)
        bookingCount = try c.decode(Int.self, forKey: .bookingCount, default: 0)
        label = try c.decode(String.self, forKey: .label, default: "Independent")
        bookingAgency = c.decodeLossy(String.self, forKey: .bookingAgency)
        category = c.decodeLossy(PerformerCategory.self, forKey: .category) ?? .undiscovered
        averageTicketPrice = c.decodeLossy(Int.self, forKey: .averageTicketPrice)
        averageAttendance = c.decodeLossy(Int.self, forKey: .averageAttendance)
        bookingEmail = c.decodeLossy(String.self, forKey: .bookingEmail)
        chartmetricId = c.decodeLossy(String.self, forKey: .chartmetricId)
    }
}

public enum PerformerCategory: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case undiscovered
    case emerging
    case hometownHero
    case mainstream
    case legendary

    public var id: String { rawValue }

    public var formattedName: String {
        switch self {
        case .undiscovered: "Undiscovered"
        case .emerging: "Emerging"
        case .hometownHero: "Hometown Hero"
        case .mainstream: "Mainstream"
        case .legendary: "Legendary"
        }
    }

    public var suggestedMaxCapacity: Int {
        switch self {
        case .undiscovered: 300
        case .emerging: 700
        case .hometownHero: 1500
        case .mainstream: 100_000
        case .legendary: 1_000_000
        }
    }

    /// Cents.
    public var ticketPriceRange: ClosedRange<Int> {
        switch self {
        case .undiscovered: 0...1000
        case .emerging: 1000...2000
        case .hometownHero: 2000...4000
        case .mainstream: 4000...7500
        case .legendary: 7500...100_000
        }
    }
}
