import Foundation

/// `username.dart` — always trimmed + lowercased. Encoded as a bare string.
public struct Username: Codable, Sendable, Hashable, Identifiable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let username: String

    public init(_ input: String) {
        username = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public init(stringLiteral value: String) { self.init(value) }

    public init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(username)
    }

    public var id: String { username }
    public var description: String { username }
    public static let empty = Username("")
}
