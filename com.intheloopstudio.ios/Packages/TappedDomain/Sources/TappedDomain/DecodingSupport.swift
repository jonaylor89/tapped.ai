import Foundation

extension KeyedDecodingContainer {
    /// Mirrors freezed's `@Default(...)`: missing *or* null keys fall back to `defaultValue`.
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: T) throws -> T {
        try decodeIfPresent(type, forKey: key) ?? defaultValue
    }

    /// Like `decodeIfPresent` but tolerates values of the wrong shape (returns nil).
    /// Firestore/Typesense documents written by older clients are not always well-typed.
    func decodeLossy<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// Decodes a list that Typesense may flatten to a scalar when it has one element.
    func decodeList<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> [T] {
        if let list = try? decodeIfPresent([T].self, forKey: key) { return list }
        if let single = try? decodeIfPresent(T.self, forKey: key) { return [single] }
        return []
    }
}

public enum TappedCoding {
    /// A `JSONDecoder` that understands every date encoding the backend produces:
    /// Firestore REST/admin JSON (`{"_seconds":…, "_nanoseconds":…}` or `{"seconds":…}`),
    /// epoch milliseconds / seconds (Typesense), and ISO-8601 strings.
    ///
    /// Firestore SDK reads go through `Firestore.Decoder`, which maps `Timestamp` → `Date` natively.
    public static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(decodeDate)
        return decoder
    }

    public static func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private struct TimestampKeys: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    @Sendable
    static func decodeDate(_ decoder: any Decoder) throws -> Date {
        if let container = try? decoder.singleValueContainer() {
            if let number = try? container.decode(Double.self) {
                return date(fromEpoch: number)
            }
            if let string = try? container.decode(String.self) {
                if let date = iso8601(string) { return date }
                if let number = Double(string) { return date(fromEpoch: number) }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "unrecognised date string \(string)")
            }
        }
        let keyed = try decoder.container(keyedBy: TimestampKeys.self)
        for (secondsKey, nanosKey) in [("_seconds", "_nanoseconds"), ("seconds", "nanoseconds")] {
            if let seconds = try keyed.decodeIfPresent(Double.self, forKey: .init(stringValue: secondsKey)) {
                let nanos = try keyed.decodeIfPresent(Double.self, forKey: .init(stringValue: nanosKey)) ?? 0
                return Date(timeIntervalSince1970: seconds + nanos / 1_000_000_000)
            }
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unrecognised timestamp"))
    }

    /// Values above 10^11 are treated as milliseconds (year 5138 in seconds).
    static func date(fromEpoch value: Double) -> Date {
        value > 100_000_000_000 ? Date(timeIntervalSince1970: value / 1000) : Date(timeIntervalSince1970: value)
    }

    static func iso8601(_ string: String) -> Date? {
        if let date = try? Date(string, strategy: .iso8601) { return date }
        return try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
