import Foundation

/// `label.dart`. Stored as `performerInfo.label` (a plain string, default `Independent`).
public struct Label: RawRepresentable, Codable, Sendable, Hashable, Identifiable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
    public var id: String { rawValue }

    public static let independent: Label = "Independent"

    public static let all: [Label] = [
        "Independent", "Death Row Records", "Blank Kanvaz", "Playmakr Entertainment", "Universal Music Group",
        "Sony Music Entertainment", "Warner Music Group", "EMI Group", "BMG", "Atlantic Records",
        "Interscope Geffen A&M", "Island Records", "Republic Records", "Columbia Records", "RCA Records",
        "Capitol Music Group", "Def Jam Recordings", "Epic Records", "Virgin Records", "Other",
    ]
}
