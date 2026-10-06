import Foundation
import TappedDomain

/// In-memory chat seeded from `Samples.conversations`.
public actor MockChatRepository: ChatRepository {
    public private(set) var connectedUserId: String?
    /// Every `markRead` call, including ones that found nothing unread.
    public private(set) var markReadCalls = 0
    private var conversations: [String: Conversation]
    private var messages: [String: [ConversationMessage]]
    private let users: [UserModel]

    private var unreadContinuations: [UUID: AsyncStream<Int>.Continuation] = [:]
    private var conversationContinuations: [UUID: AsyncThrowingStream<[Conversation], any Error>.Continuation] = [:]
    private var messageContinuations: [UUID: (id: String, continuation: AsyncThrowingStream<[ConversationMessage], any Error>.Continuation)] = [:]

    public init(
        conversations: [Conversation] = Samples.conversations,
        messages: [String: [ConversationMessage]] = Samples.conversationMessages,
        users: [UserModel] = Samples.performers + Samples.venues
    ) {
        self.conversations = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        self.messages = messages
        self.users = users
    }

    public func connectUser(_ user: UserModel) async throws {
        connectedUserId = user.id
        broadcast()
    }

    public func disconnect() async {
        connectedUserId = nil
    }

    public nonisolated func unreadCountUpdates() -> AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.registerUnread(id, continuation) }
            continuation.onTermination = { _ in Task { await self.unregister(id) } }
        }
    }

    public nonisolated func conversationsObserver() -> AsyncThrowingStream<[Conversation], any Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            Task { await self.registerConversations(id, continuation) }
            continuation.onTermination = { _ in Task { await self.unregister(id) } }
        }
    }

    public nonisolated func messagesObserver(conversationId: String) -> AsyncThrowingStream<[ConversationMessage], any Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            Task { await self.registerMessages(id, conversationId, continuation) }
            continuation.onTermination = { _ in Task { await self.unregister(id) } }
        }
    }

    public func loadOlderMessages(conversationId: String) async throws {}

    public func conversation(id: String) async throws -> Conversation? { conversations[id] }

    public func createDirectConversation(with userId: String) async throws -> String {
        guard let me = connectedUserId else { throw ChatError.notConnected }
        let id = Samples.directConversationId(me, userId)
        if conversations[id] == nil {
            let other = users.first { $0.id == userId }
            conversations[id] = Conversation(
                id: id,
                name: other?.displayName ?? userId,
                imageURL: other?.profilePicture.flatMap(URL.init(string:)),
                memberIds: [me, userId]
            )
            messages[id] = []
            broadcast()
        }
        return id
    }

    public func sendMessage(_ text: String, conversationId: String) async throws {
        guard let me = connectedUserId else { throw ChatError.notConnected }
        guard conversations[conversationId] != nil else { throw ChatError.invalidConversationId }
        let author = users.first { $0.id == me }
        let message = ConversationMessage(
            id: UUID().uuidString,
            text: text,
            authorId: me,
            authorName: author?.displayName ?? me,
            createdAt: .now,
            isFromCurrentUser: true
        )
        messages[conversationId, default: []].append(message)
        conversations[conversationId]?.lastMessageText = text
        conversations[conversationId]?.lastMessageAt = message.createdAt
        broadcast()
    }

    public func markRead(conversationId: String) async throws {
        markReadCalls += 1
        guard conversations[conversationId]?.unreadCount != 0 else { return }
        conversations[conversationId]?.unreadCount = 0
        broadcast()
    }

    /// Simulates a message arriving from another member.
    public func receive(_ message: ConversationMessage, in conversationId: String) {
        messages[conversationId, default: []].append(message)
        conversations[conversationId]?.unreadCount += 1
        conversations[conversationId]?.lastMessageText = message.text
        conversations[conversationId]?.lastMessageAt = message.createdAt
        broadcast()
    }

    // MARK: - observers

    private var sortedConversations: [Conversation] {
        conversations.values.sorted { ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast) }
    }

    private var totalUnread: Int { conversations.values.reduce(0) { $0 + $1.unreadCount } }

    private func registerUnread(_ id: UUID, _ continuation: AsyncStream<Int>.Continuation) {
        unreadContinuations[id] = continuation
        continuation.yield(totalUnread)
    }

    private func registerConversations(_ id: UUID, _ continuation: AsyncThrowingStream<[Conversation], any Error>.Continuation) {
        conversationContinuations[id] = continuation
        continuation.yield(sortedConversations)
    }

    private func registerMessages(_ id: UUID, _ conversationId: String, _ continuation: AsyncThrowingStream<[ConversationMessage], any Error>.Continuation) {
        messageContinuations[id] = (conversationId, continuation)
        continuation.yield(messages[conversationId] ?? [])
    }

    private func unregister(_ id: UUID) {
        unreadContinuations[id] = nil
        conversationContinuations[id] = nil
        messageContinuations[id] = nil
    }

    private func broadcast() {
        let unread = totalUnread
        let sorted = sortedConversations
        for continuation in unreadContinuations.values { continuation.yield(unread) }
        for continuation in conversationContinuations.values { continuation.yield(sorted) }
        for entry in messageContinuations.values { entry.continuation.yield(messages[entry.id] ?? []) }
    }
}
