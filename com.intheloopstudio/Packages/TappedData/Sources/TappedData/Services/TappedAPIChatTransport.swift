import FirebaseAuth
import Foundation
import TappedDomain

// Wire types for `/app/v1/conversations` (services/api.tapped.ai/src/domain/direct_messages).
// IDs are lowercase UUID strings. Messages carry a gap-free per-conversation `seq`.

public struct ChatMemberDTO: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var username: String
    public var imageUrl: String?
    public var deleted: Bool

    public init(id: String, name: String, username: String = "", imageUrl: String? = nil, deleted: Bool = false) {
        self.id = id
        self.name = name
        self.username = username
        self.imageUrl = imageUrl
        self.deleted = deleted
    }
}

public struct ChatAttachmentDTO: Codable, Sendable, Hashable {
    public var type: String
    public var url: String

    public init(type: String, url: String) {
        self.type = type
        self.url = url
    }
}

public struct ChatMessageDTO: Codable, Sendable, Hashable {
    public var id: String
    public var conversationId: String
    public var seq: Int64
    public var authorId: String
    public var text: String
    public var attachments: [ChatAttachmentDTO]
    public var createdAt: Date

    public init(id: String, conversationId: String, seq: Int64, authorId: String, text: String,
                attachments: [ChatAttachmentDTO] = [], createdAt: Date) {
        self.id = id
        self.conversationId = conversationId
        self.seq = seq
        self.authorId = authorId
        self.text = text
        self.attachments = attachments
        self.createdAt = createdAt
    }
}

public struct ChatConversationDTO: Codable, Sendable, Hashable {
    public var id: String
    public var members: [ChatMemberDTO]
    public var frozen: Bool
    public var createdAt: Date
    public var lastSeq: Int64
    public var lastReadSeq: Int64
    public var unreadCount: Int
    public var lastMessage: ChatMessageDTO?
    public var lastMessageAt: Date?

    public init(id: String, members: [ChatMemberDTO], frozen: Bool = false, createdAt: Date, lastSeq: Int64 = 0,
                lastReadSeq: Int64 = 0, unreadCount: Int = 0, lastMessage: ChatMessageDTO? = nil, lastMessageAt: Date? = nil) {
        self.id = id
        self.members = members
        self.frozen = frozen
        self.createdAt = createdAt
        self.lastSeq = lastSeq
        self.lastReadSeq = lastReadSeq
        self.unreadCount = unreadCount
        self.lastMessage = lastMessage
        self.lastMessageAt = lastMessageAt
    }
}

public struct ChatInboxPage: Codable, Sendable, Hashable {
    public var conversations: [ChatConversationDTO]
    public var nextCursor: String?
    public var unreadTotal: Int

    public init(conversations: [ChatConversationDTO], nextCursor: String? = nil, unreadTotal: Int) {
        self.conversations = conversations
        self.nextCursor = nextCursor
        self.unreadTotal = unreadTotal
    }
}

public struct ChatMessagePage: Codable, Sendable, Hashable {
    /// Ascending `seq`.
    public var messages: [ChatMessageDTO]
    public var hasMore: Bool

    public init(messages: [ChatMessageDTO], hasMore: Bool) {
        self.messages = messages
        self.hasMore = hasMore
    }
}

public struct ChatReadResult: Codable, Sendable, Hashable {
    public var lastReadSeq: Int64
    public var unreadTotal: Int

    public init(lastReadSeq: Int64, unreadTotal: Int) {
        self.lastReadSeq = lastReadSeq
        self.unreadTotal = unreadTotal
    }
}

/// One server-sent event from `GET /app/v1/conversations/events`.
public enum ChatEvent: Sendable, Equatable {
    /// Sent on connect: anything may have changed while disconnected, so resync.
    case ready(unreadTotal: Int)
    /// `frozen` is the conversation's current state (a venue's email reply unfreezes it).
    case message(ChatMessageDTO, unreadCount: Int, lastReadSeq: Int64, unreadTotal: Int, frozen: Bool?)
    case read(conversationId: String, lastReadSeq: Int64, unreadCount: Int, unreadTotal: Int)
    /// The server may have dropped events (listener reconnect): refetch.
    case resync

    private struct Wire: Decodable {
        var type: String
        var conversationId: String?
        var message: ChatMessageDTO?
        var unreadCount: Int?
        var lastReadSeq: Int64?
        var unreadTotal: Int?
        var frozen: Bool?
    }

    /// `nil` for event types this build does not know (newer servers may add some).
    static func decode(_ data: Data) throws -> ChatEvent? {
        let wire = try TappedCoding.jsonDecoder().decode(Wire.self, from: data)
        switch wire.type {
        case "ready":
            return .ready(unreadTotal: wire.unreadTotal ?? 0)
        case "message":
            guard let message = wire.message else { return nil }
            return .message(message, unreadCount: wire.unreadCount ?? 0, lastReadSeq: wire.lastReadSeq ?? 0,
                            unreadTotal: wire.unreadTotal ?? 0, frozen: wire.frozen)
        case "read":
            guard let id = wire.conversationId else { return nil }
            return .read(conversationId: id, lastReadSeq: wire.lastReadSeq ?? 0, unreadCount: wire.unreadCount ?? 0,
                         unreadTotal: wire.unreadTotal ?? 0)
        case "resync":
            return .resync
        default:
            return nil
        }
    }
}

/// Network access for `TappedChatRepository`; faked in tests.
public protocol ChatTransport: Sendable {
    func inbox(cursor: String?, limit: Int) async throws -> ChatInboxPage
    func conversation(id: String) async throws -> ChatConversationDTO?
    func openDirect(userId: String) async throws -> ChatConversationDTO
    func messages(conversationId: String, before: Int64?, after: Int64?, limit: Int) async throws -> ChatMessagePage
    /// Idempotent per `messageId`: resending returns the stored message.
    func send(conversationId: String, messageId: String, text: String) async throws -> ChatMessageDTO
    func markRead(conversationId: String, throughSeq: Int64?) async throws -> ChatReadResult
    /// One connection's events; finishes when the server closes it (the caller reconnects).
    func events() -> AsyncThrowingStream<ChatEvent, any Error>
}

/// Incremental `text/event-stream` parser (WHATWG): `data:` lines join with `\n` and dispatch on a
/// blank line; comments (`:` keep-alives) and other fields are ignored.
struct ServerSentEventParser {
    private var line: [UInt8] = []
    private var data: [String] = []
    private var lastWasCR = false

    /// Feeds one byte; returns a completed event's data, if this byte completed one.
    mutating func consume(_ byte: UInt8) -> String? {
        if byte == UInt8(ascii: "\n"), lastWasCR {
            lastWasCR = false
            return nil
        }
        lastWasCR = byte == UInt8(ascii: "\r")
        guard byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") else {
            line.append(byte)
            return nil
        }
        defer { line.removeAll(keepingCapacity: true) }
        if line.isEmpty {
            defer { data.removeAll() }
            return data.isEmpty ? nil : data.joined(separator: "\n")
        }
        let text = String(decoding: line, as: UTF8.self)
        if text.hasPrefix(":") { return nil }
        let (field, value) = text.firstIndex(of: ":").map { index in
            let value = text[text.index(after: index)...]
            return (String(text[..<index]), String(value.hasPrefix(" ") ? value.dropFirst() : value))
        } ?? (text, "")
        if field == "data" { data.append(value) }
        return nil
    }
}

public enum ChatTransportError: Error, Equatable {
    case unexpectedStatus(Int)
}

/// `/app/v1/conversations` over the Firebase-authenticated Tapped API.
public struct TappedAPIChatTransport: ChatTransport {
    private let client: TappedAPIDataClient
    private let baseURL: URL
    private let session: URLSession
    private let idToken: TappedAPIDataClient.IDTokenProvider

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        idToken: @escaping TappedAPIDataClient.IDTokenProvider = { try await Auth.auth().currentUser?.getIDToken() }
    ) {
        client = TappedAPIDataClient(baseURL: baseURL, session: session, idToken: idToken)
        self.baseURL = baseURL
        self.session = session
        self.idToken = idToken
    }

    private func decode<T: Decodable>(_ data: Data?) throws -> T {
        guard let data else { throw TappedAPIError.invalidResponse }
        return try TappedCoding.jsonDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: [String], _ body: some Encodable) async throws -> T {
        try decode(try await client.request(path, method: "POST", body: JSONEncoder().encode(body)))
    }

    public func inbox(cursor: String?, limit: Int) async throws -> ChatInboxPage {
        var query = ["limit": String(limit)]
        query["cursor"] = cursor
        return try decode(try await client.request(["conversations"], query: query))
    }

    public func conversation(id: String) async throws -> ChatConversationDTO? {
        try await client.read(["conversations", id])
    }

    public func openDirect(userId: String) async throws -> ChatConversationDTO {
        try await post(["conversations", "direct"], ["userId": userId])
    }

    public func messages(conversationId: String, before: Int64?, after: Int64?, limit: Int) async throws -> ChatMessagePage {
        var query = ["limit": String(limit)]
        query["before"] = before.map(String.init)
        query["after"] = after.map(String.init)
        return try decode(try await client.request(["conversations", conversationId, "messages"], query: query))
    }

    public func send(conversationId: String, messageId: String, text: String) async throws -> ChatMessageDTO {
        try await post(["conversations", conversationId, "messages"], ["id": messageId, "text": text])
    }

    public func markRead(conversationId: String, throughSeq: Int64?) async throws -> ChatReadResult {
        struct Body: Encodable { var throughSeq: Int64? }
        return try await post(["conversations", conversationId, "read"], Body(throughSeq: throughSeq))
    }

    public func events() -> AsyncThrowingStream<ChatEvent, any Error> {
        let session = session, baseURL = baseURL, idToken = idToken
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let token = try await idToken(), !token.isEmpty else { throw TappedAPIError.notSignedIn }
                    var request = URLRequest(url: baseURL.appending(path: "app/v1/conversations/events"))
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
                    // Idle timeout: the server sends a keep-alive every 20 s.
                    request.timeoutInterval = 60
                    let (bytes, response) = try await session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else { throw ChatTransportError.unexpectedStatus(status) }
                    var parser = ServerSentEventParser()
                    for try await byte in bytes {
                        guard let data = parser.consume(byte) else { continue }
                        if let event = try? ChatEvent.decode(Data(data.utf8)) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
