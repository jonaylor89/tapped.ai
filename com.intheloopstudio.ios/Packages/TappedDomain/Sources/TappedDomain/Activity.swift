import Foundation

/// `activity.dart` — `activities/{id}`. The Dart sealed class becomes an enum of payload structs,
/// discriminated by the Firestore `type` field.
public enum Activity: Codable, Sendable, Hashable, Identifiable {
    case follow(Follow)
    case bookingRequest(BookingRequest)
    case bookingUpdate(BookingUpdate)
    case bookingReminder(BookingReminder)
    case searchAppearance(SearchAppearance)

    public struct Common: Codable, Sendable, Hashable {
        public var id: String
        public var toUserId: String
        public var timestamp: Date
        public var markedRead: Bool

        public init(id: String, toUserId: String, timestamp: Date, markedRead: Bool = false) {
            self.id = id
            self.toUserId = toUserId
            self.timestamp = timestamp
            self.markedRead = markedRead
        }
    }

    public struct Follow: Sendable, Hashable {
        public var common: Common
        public var fromUserId: String
        public init(common: Common, fromUserId: String) {
            self.common = common
            self.fromUserId = fromUserId
        }
    }

    public struct BookingRequest: Sendable, Hashable {
        public var common: Common
        public var fromUserId: String
        public var bookingId: String
        public init(common: Common, fromUserId: String, bookingId: String) {
            self.common = common
            self.fromUserId = fromUserId
            self.bookingId = bookingId
        }
    }

    public struct BookingUpdate: Sendable, Hashable {
        public var common: Common
        public var fromUserId: String
        public var bookingId: String
        public var status: BookingStatus?
        public init(common: Common, fromUserId: String, bookingId: String, status: BookingStatus?) {
            self.common = common
            self.fromUserId = fromUserId
            self.bookingId = bookingId
            self.status = status
        }
    }

    public struct BookingReminder: Sendable, Hashable {
        public var common: Common
        public var fromUserId: String
        public var bookingId: String
        public init(common: Common, fromUserId: String, bookingId: String) {
            self.common = common
            self.fromUserId = fromUserId
            self.bookingId = bookingId
        }
    }

    public struct SearchAppearance: Sendable, Hashable {
        public var common: Common
        public var count: Int
        public init(common: Common, count: Int) {
            self.common = common
            self.count = count
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, toUserId, timestamp, markedRead, type, fromUserId, bookingId, status, count
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let common = Common(
            id: try c.decode(String.self, forKey: .id),
            toUserId: try c.decode(String.self, forKey: .toUserId),
            timestamp: c.decodeLossy(Date.self, forKey: .timestamp) ?? .now,
            markedRead: try c.decode(Bool.self, forKey: .markedRead, default: false)
        )
        let type = try c.decode(ActivityType.self, forKey: .type)
        switch type {
        case .follow:
            self = .follow(.init(common: common, fromUserId: try c.decode(String.self, forKey: .fromUserId)))
        case .bookingRequest:
            self = .bookingRequest(.init(
                common: common,
                fromUserId: try c.decode(String.self, forKey: .fromUserId),
                bookingId: try c.decode(String.self, forKey: .bookingId)
            ))
        case .bookingUpdate:
            self = .bookingUpdate(.init(
                common: common,
                fromUserId: try c.decode(String.self, forKey: .fromUserId),
                bookingId: try c.decode(String.self, forKey: .bookingId),
                status: c.decodeLossy(BookingStatus.self, forKey: .status)
            ))
        case .bookingReminder:
            self = .bookingReminder(.init(
                common: common,
                fromUserId: try c.decode(String.self, forKey: .fromUserId),
                bookingId: try c.decode(String.self, forKey: .bookingId)
            ))
        case .searchAppearance:
            self = .searchAppearance(.init(common: common, count: try c.decode(Int.self, forKey: .count)))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(common.id, forKey: .id)
        try c.encode(common.toUserId, forKey: .toUserId)
        try c.encode(common.timestamp, forKey: .timestamp)
        try c.encode(common.markedRead, forKey: .markedRead)
        try c.encode(type, forKey: .type)
        switch self {
        case let .follow(value):
            try c.encode(value.fromUserId, forKey: .fromUserId)
        case let .bookingRequest(value):
            try c.encode(value.fromUserId, forKey: .fromUserId)
            try c.encode(value.bookingId, forKey: .bookingId)
        case let .bookingUpdate(value):
            try c.encode(value.fromUserId, forKey: .fromUserId)
            try c.encode(value.bookingId, forKey: .bookingId)
            try c.encodeIfPresent(value.status, forKey: .status)
        case let .bookingReminder(value):
            try c.encode(value.fromUserId, forKey: .fromUserId)
            try c.encode(value.bookingId, forKey: .bookingId)
        case let .searchAppearance(value):
            try c.encode(value.count, forKey: .count)
        }
    }

    public var common: Common {
        switch self {
        case let .follow(v): v.common
        case let .bookingRequest(v): v.common
        case let .bookingUpdate(v): v.common
        case let .bookingReminder(v): v.common
        case let .searchAppearance(v): v.common
        }
    }

    public var id: String { common.id }

    public var type: ActivityType {
        switch self {
        case .follow: .follow
        case .bookingRequest: .bookingRequest
        case .bookingUpdate: .bookingUpdate
        case .bookingReminder: .bookingReminder
        case .searchAppearance: .searchAppearance
        }
    }

    /// `Activity.copyAsRead()`
    public func copyAsRead() -> Activity {
        var read = common
        read.markedRead = true
        switch self {
        case var .follow(v): v.common = read; return .follow(v)
        case var .bookingRequest(v): v.common = read; return .bookingRequest(v)
        case var .bookingUpdate(v): v.common = read; return .bookingUpdate(v)
        case var .bookingReminder(v): v.common = read; return .bookingReminder(v)
        case var .searchAppearance(v): v.common = read; return .searchAppearance(v)
        }
    }
}

public enum ActivityType: String, Codable, Sendable, CaseIterable, Hashable {
    case follow
    case bookingRequest
    case bookingUpdate
    case bookingReminder
    case searchAppearance
}
