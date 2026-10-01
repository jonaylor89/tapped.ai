import Foundation
@preconcurrency import StreamChat
import TappedDomain

/// `lib/data/prod/stream_impl.dart` on the Stream Chat Swift SDK state layer.
/// Tokens come from the Firebase-authenticated Tapped API endpoint.
@MainActor
public final class StreamChatRepository: ChatRepository {
    public typealias TokenProvider = @Sendable () async throws -> String

    private let client: ChatClient
    private let tokenProvider: TokenProvider
    private var connectedUser: ConnectedUser?
    private var unreadTask: Task<Void, Never>?
    private var unreadCount = 0
    private var unreadContinuations: [UUID: AsyncStream<Int>.Continuation] = [:]
    private var chats: [String: Chat] = [:]

    public nonisolated init(apiKey: String, tokenProvider: @escaping TokenProvider) {
        client = ChatClient(config: ChatClientConfig(apiKeyString: apiKey))
        self.tokenProvider = tokenProvider
    }

    public func connectUser(_ user: UserModel) async throws {
        if client.currentUserId == user.id, connectedUser != nil { return }
        if client.currentUserId != nil { await client.disconnect() }
        let fetchToken = tokenProvider
        let connected = try await client.connectUser(
            userInfo: UserInfo(id: user.id, name: user.displayName, imageURL: user.profilePicture.flatMap(URL.init(string:))),
            tokenProvider: { completion in
                Task {
                    do {
                        completion(.success(try Token(rawValue: try await fetchToken())))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        )
        connectedUser = connected
        unreadTask?.cancel()
        unreadTask = Task { [weak self] in
            for await chatUser in connected.state.$user.values {
                self?.publishUnread(chatUser.unreadCount.messages)
            }
        }
    }

    public func disconnect() async {
        unreadTask?.cancel()
        unreadTask = nil
        connectedUser = nil
        chats = [:]
        publishUnread(0)
        await client.logout()
    }

    public nonisolated func unreadCountUpdates() -> AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            Task { @MainActor in self.registerUnread(id, continuation) }
            continuation.onTermination = { _ in Task { @MainActor in self.unreadContinuations[id] = nil } }
        }
    }

    public nonisolated func conversationsObserver() -> AsyncThrowingStream<[Conversation], any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    guard let userId = self.client.currentUserId else { throw ChatError.notConnected }
                    let query = ChannelListQuery(
                        filter: .containMembers(userIds: [userId]),
                        sort: [Sorting(key: .lastMessageAt, isAscending: false)],
                        pageSize: 20
                    )
                    let list = self.client.makeChannelList(with: query)
                    try await list.get()
                    for await channels in list.state.$channels.values {
                        continuation.yield(channels.map { Self.conversation(from: $0, currentUserId: userId) })
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public nonisolated func messagesObserver(conversationId: String) -> AsyncThrowingStream<[ConversationMessage], any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    let chat = try await self.watchedChat(conversationId)
                    for await messages in chat.state.$messages.values {
                        continuation.yield(messages.filter { $0.deletedAt == nil }.map(Self.message(from:)))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func loadOlderMessages(conversationId: String) async throws {
        let chat = try await watchedChat(conversationId)
        guard !chat.state.hasLoadedAllOldestMessages else { return }
        try await chat.loadOlderMessages()
    }

    public func conversation(id: String) async throws -> Conversation? {
        guard let userId = client.currentUserId else { throw ChatError.notConnected }
        let chat = try await watchedChat(id)
        return chat.state.channel.map { Self.conversation(from: $0, currentUserId: userId) }
    }

    public func createDirectConversation(with userId: String) async throws -> String {
        guard client.currentUserId != nil else { throw ChatError.notConnected }
        let chat = try client.makeDirectMessageChat(with: [userId], extraData: [:])
        try await chat.get(watch: true)
        guard let id = chat.state.cid?.rawValue else { throw ChatError.invalidConversationId }
        chats[id] = chat
        return id
    }

    public func sendMessage(_ text: String, conversationId: String) async throws {
        try await watchedChat(conversationId).sendMessage(with: text)
    }

    public func markRead(conversationId: String) async throws {
        try await watchedChat(conversationId).markRead()
    }

    // MARK: - helpers

    private func registerUnread(_ id: UUID, _ continuation: AsyncStream<Int>.Continuation) {
        unreadContinuations[id] = continuation
        continuation.yield(unreadCount)
    }

    private func publishUnread(_ count: Int) {
        unreadCount = count
        for continuation in unreadContinuations.values { continuation.yield(count) }
    }

    private func watchedChat(_ conversationId: String) async throws -> Chat {
        if let chat = chats[conversationId] { return chat }
        guard client.currentUserId != nil else { throw ChatError.notConnected }
        guard let cid = try? ChannelId(cid: conversationId) else { throw ChatError.invalidConversationId }
        let chat = client.makeChat(for: cid)
        try await chat.get(watch: true)
        chats[conversationId] = chat
        return chat
    }

    private static func conversation(from channel: ChatChannel, currentUserId: String) -> Conversation {
        let others = channel.lastActiveMembers.filter { $0.id != currentUserId }
        let name = channel.name.flatMap { $0.isEmpty ? nil : $0 }
            ?? others.compactMap(\.name).joined(separator: ", ").nonEmpty
            ?? others.first?.id
            ?? "conversation"
        let lastMessage = channel.latestMessages.first { $0.deletedAt == nil }
        return Conversation(
            id: channel.cid.rawValue,
            name: name,
            imageURL: channel.imageURL ?? others.first?.imageURL,
            memberIds: channel.lastActiveMembers.map(\.id),
            lastMessageText: lastMessage.map(previewText(for:)),
            lastMessageAt: channel.lastMessageAt,
            unreadCount: channel.unreadCount.messages
        )
    }

    private static func previewText(for message: ChatMessage) -> String {
        if !message.text.isEmpty { return message.text }
        return (message.attachmentCounts[.image] ?? 0) > 0 ? "sent a photo" : "sent an attachment"
    }

    private static func message(from message: ChatMessage) -> ConversationMessage {
        let status: ConversationMessage.Status = switch message.localState {
        case .pendingSend, .sending, .pendingSync, .syncing: .sending
        case .sendingFailed, .syncingFailed: .failed
        default: .sent
        }
        return ConversationMessage(
            id: message.id,
            text: message.text.isEmpty ? previewText(for: message) : message.text,
            authorId: message.author.id,
            authorName: message.author.name ?? message.author.id,
            authorImageURL: message.author.imageURL,
            createdAt: message.createdAt,
            isFromCurrentUser: message.isSentByCurrentUser,
            status: status
        )
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
