import Foundation

/// `service.dart` — `services/{userId}/userServices/{id}`.
public struct Service: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var userId: String
    public var title: String
    public var description: String
    /// Cents.
    public var rate: Int
    public var rateType: RateType
    public var count: Int
    public var deleted: Bool

    public init(
        id: String,
        userId: String,
        title: String = "",
        description: String = "",
        rate: Int = 0,
        rateType: RateType = .fixed,
        count: Int = 0,
        deleted: Bool = false
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.description = description
        self.rate = rate
        self.rateType = rateType
        self.count = count
        self.deleted = deleted
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        userId = try c.decode(String.self, forKey: .userId)
        title = try c.decode(String.self, forKey: .title, default: "")
        description = try c.decode(String.self, forKey: .description, default: "")
        rate = try c.decode(Int.self, forKey: .rate, default: 0)
        rateType = c.decodeLossy(RateType.self, forKey: .rateType) ?? .fixed
        count = try c.decode(Int.self, forKey: .count, default: 0)
        deleted = try c.decode(Bool.self, forKey: .deleted, default: false)
    }

    /// `ServiceX.performerCost`
    public func performerCost(start: Date, end: Date) -> Int {
        guard rateType == .hourly else { return rate }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        return Int(Double(minutes) * Double(rate) / 60)
    }
}

public enum RateType: String, Codable, Sendable, CaseIterable, Hashable {
    case hourly
    case fixed
}
