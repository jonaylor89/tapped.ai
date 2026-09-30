import Foundation
import TappedDomain

/// `lib/data/stream_repository.dart`. Messaging backend behind a protocol so Stream can later be
/// swapped for Firestore without touching the messaging UI.
public protocol ChatRepository: Sendable {
    /// Connects `user` to the chat backend. No-op when that user is already connected.
    func connectUser(_ user: UserModel) async throws
    func disconnect() async

    /// Total unread messages across every conversation (Discover top-chrome badge).
    func unreadCountUpdates() -> AsyncStream<Int>

    /// Conversations the current user is a member of, most recent first.
    func conversationsObserver() -> AsyncThrowingStream<[Conversation], any Error>
    /// Messages in a conversation, oldest first. Starts watching the channel.
    func messagesObserver(conversationId: String) -> AsyncThrowingStream<[ConversationMessage], any Error>
    func loadOlderMessages(conversationId: String) async throws

    func conversation(id: String) async throws -> Conversation?
    /// `createSimpleChat`: returns the existing 1:1 conversation with `userId` or creates it.
    func createDirectConversation(with userId: String) async throws -> String
    func sendMessage(_ text: String, conversationId: String) async throws
    func markRead(conversationId: String) async throws
}

public enum ChatError: Error, Equatable, Sendable {
    case notConnected
    case invalidConversationId
    case invalidToken
}
