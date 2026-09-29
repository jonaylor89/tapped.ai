import Foundation

/// `review.dart` — `reviews/{revieweeId}/{bookerReviews|performerReviews}/{id}`.
public enum Review: Codable, Sendable, Hashable, Identifiable {
    case booker(BookerReview)
    case performer(PerformerReview)

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: ReviewFields.CodingKeys.self)
        switch try c.decode(ReviewType.self, forKey: .type) {
        case .booker: self = .booker(try BookerReview(from: decoder))
        case .performer: self = .performer(try PerformerReview(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case let .booker(review): try review.encode(to: encoder)
        case let .performer(review): try review.encode(to: encoder)
        }
    }

    public var fields: ReviewFields {
        switch self {
        case let .booker(review): review.fields
        case let .performer(review): review.fields
        }
    }

    public var id: String { fields.id }
    public var type: ReviewType { fields.type }
}

public enum ReviewType: String, Codable, Sendable, CaseIterable, Hashable {
    case booker
    case performer
}

public struct ReviewFields: Codable, Sendable, Hashable {
    public var id: String
    public var bookerId: String
    public var performerId: String
    public var bookingId: String?
    public var timestamp: Date
    public var overallRating: Int
    public var overallReview: String
    public var type: ReviewType

    public init(
        id: String,
        bookerId: String,
        performerId: String,
        bookingId: String? = nil,
        timestamp: Date,
        overallRating: Int,
        overallReview: String,
        type: ReviewType
    ) {
        self.id = id
        self.bookerId = bookerId
        self.performerId = performerId
        self.bookingId = bookingId
        self.timestamp = timestamp
        self.overallRating = overallRating
        self.overallReview = overallReview
        self.type = type
    }

    enum CodingKeys: String, CodingKey {
        case id, bookerId, performerId, bookingId, timestamp, overallRating, overallReview, type
    }
}

/// A review *of a booker*, written by a performer.
public struct BookerReview: Codable, Sendable, Hashable, Identifiable {
    public var fields: ReviewFields
    public var id: String { fields.id }

    public init(fields: ReviewFields) {
        var fields = fields
        fields.type = .booker
        self.fields = fields
    }

    public init(from decoder: any Decoder) throws {
        self.init(fields: try ReviewFields(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws { try fields.encode(to: encoder) }
}

/// A review *of a performer*, written by a booker.
public struct PerformerReview: Codable, Sendable, Hashable, Identifiable {
    public var fields: ReviewFields
    public var id: String { fields.id }

    /// Note: the Dart `PerformerReview.fromDoc` hard-codes `type: ReviewType.booker` (a bug).
    /// Native code writes the correct `performer` discriminator.
    public init(fields: ReviewFields) {
        var fields = fields
        fields.type = .performer
        self.fields = fields
    }

    public init(from decoder: any Decoder) throws {
        self.init(fields: try ReviewFields(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws { try fields.encode(to: encoder) }
}
