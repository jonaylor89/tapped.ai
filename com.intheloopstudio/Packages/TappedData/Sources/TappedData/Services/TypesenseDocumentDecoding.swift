import Foundation
import TappedDomain

/// `GET /collections/{c}/documents/search`, decoded in one `JSONDecoder` pass. Hits that don't decode are dropped
/// instead of failing the whole page.
struct TypesenseSearchResponse<Document: Decodable>: Decodable {
    let documents: [Document]

    private enum CodingKeys: String, CodingKey { case hits }

    private struct Hit: Decodable {
        let document: Document?

        private enum CodingKeys: String, CodingKey { case document }

        init(from decoder: any Decoder) throws {
            document = try? decoder.container(keyedBy: CodingKeys.self).decode(Document.self, forKey: .document)
        }
    }

    init(from decoder: any Decoder) throws {
        let hits = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent([Hit].self, forKey: .hits) ?? []
        documents = hits.compactMap(\.document)
    }
}

/// A hit reduced to its id (`include_fields=id`), for collections that are hydrated from Firestore.
struct TypesenseIDDocument: Decodable {
    let id: String
}

/// Decodes `Model` from a Typesense document. The users collection is indexed with flattened keys
/// (`"venueInfo.capacity": 250`, `"location": [lat, lng]` beside `"location.placeId"`), so nested models are read
/// from dotted keys when there is no nested object. Nested objects still decode as-is.
struct TypesenseDocument<Model: Decodable>: Decodable {
    let model: Model

    init(from decoder: any Decoder) throws {
        let root = try decoder.container(keyedBy: AnyCodingKey.self)
        model = try Model(from: FlattenedKeysDecoder(root: root, prefix: "", codingPath: decoder.codingPath))
    }
}

struct AnyCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// A `Decoder` for the keys of `root` that start with `prefix`.
private struct FlattenedKeysDecoder: Decoder {
    let root: KeyedDecodingContainer<AnyCodingKey>
    let prefix: String
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(FlattenedKeyedContainer<Key>(root: root, prefix: prefix, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch([Any].self, .init(codingPath: codingPath, debugDescription: "flattened object, not a list"))
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        throw DecodingError.typeMismatch(Any.self, .init(codingPath: codingPath, debugDescription: "flattened object, not a value"))
    }
}

private struct FlattenedKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let root: KeyedDecodingContainer<AnyCodingKey>
    let prefix: String
    let codingPath: [any CodingKey]

    var allKeys: [Key] {
        var seen = Set<String>()
        return root.allKeys.compactMap { key in
            guard key.stringValue.hasPrefix(prefix) else { return nil }
            let head = String(key.stringValue.dropFirst(prefix.count).prefix { $0 != "." })
            guard !head.isEmpty, seen.insert(head).inserted else { return nil }
            return Key(stringValue: head)
        }
    }

    private func flat(_ key: Key) -> AnyCodingKey { AnyCodingKey(prefix + key.stringValue) }
    private func childPrefix(_ key: Key) -> String { prefix + key.stringValue + "." }
    private func hasChildren(_ key: Key) -> Bool {
        let childPrefix = childPrefix(key)
        return root.allKeys.contains { $0.stringValue.hasPrefix(childPrefix) }
    }
    private func childDecoder(_ key: Key) -> FlattenedKeysDecoder {
        FlattenedKeysDecoder(root: root, prefix: childPrefix(key), codingPath: codingPath + [key])
    }

    func contains(_ key: Key) -> Bool { root.contains(flat(key)) || hasChildren(key) }

    func decodeNil(forKey key: Key) throws -> Bool {
        if root.contains(flat(key)) { return try root.decodeNil(forKey: flat(key)) }
        return !hasChildren(key)
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let flatKey = flat(key)
        if hasChildren(key) {
            if root.contains(flatKey), let value = try? root.decode(T.self, forKey: flatKey) { return value }
            return try T(from: childDecoder(key))
        }
        if T.self == Location.self, let point = try? root.decode([Double].self, forKey: flatKey), point.count == 2 {
            // A bare geopoint; the place id sits beside it (Flutter `_convertTypesenseDocumentToUserModel`).
            let placeId = (try? root.decodeIfPresent(String.self, forKey: AnyCodingKey(prefix + "placeId"))) ?? nil
            if let location = Location(placeId: placeId ?? "", lat: point[0], lng: point[1]) as? T { return location }
        }
        return try root.decode(T.self, forKey: flatKey)
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try root.decode(type, forKey: flat(key)) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try root.decode(type, forKey: flat(key)) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try root.decode(type, forKey: flat(key)) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try root.decode(type, forKey: flat(key)) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try root.decode(type, forKey: flat(key)) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try root.decode(type, forKey: flat(key)) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try root.decode(type, forKey: flat(key)) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try root.decode(type, forKey: flat(key)) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try root.decode(type, forKey: flat(key)) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try root.decode(type, forKey: flat(key)) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try root.decode(type, forKey: flat(key)) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try root.decode(type, forKey: flat(key)) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try root.decode(type, forKey: flat(key)) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try root.decode(type, forKey: flat(key)) }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        if hasChildren(key) { return try childDecoder(key).container(keyedBy: type) }
        return try root.nestedContainer(keyedBy: type, forKey: flat(key))
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        try root.nestedUnkeyedContainer(forKey: flat(key))
    }

    func superDecoder() throws -> any Decoder {
        FlattenedKeysDecoder(root: root, prefix: prefix, codingPath: codingPath)
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        if hasChildren(key) { return childDecoder(key) }
        return try root.superDecoder(forKey: flat(key))
    }
}
