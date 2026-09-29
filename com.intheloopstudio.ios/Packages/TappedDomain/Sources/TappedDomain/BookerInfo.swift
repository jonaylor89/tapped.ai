import Foundation

/// `booker_info.dart`
public struct BookerInfo: Codable, Sendable, Hashable {
    public var rating: Double?
    public var reviewCount: Int

    public init(rating: Double? = nil, reviewCount: Int = 0) {
        self.rating = rating
        self.reviewCount = reviewCount
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rating = c.decodeLossy(Double.self, forKey: .rating)
        reviewCount = try c.decode(Int.self, forKey: .reviewCount, default: 0)
    }

    public static let empty = BookerInfo()
}
