import Foundation
import Observation
import TappedData
import TappedDomain

/// Stream channel page: watches one conversation, sends messages, marks it read.
@Observable
@MainActor
final class ChannelViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed
    }

    let conversationId: String
    private(set) var phase: Phase = .loading
    private(set) var conversation: Conversation?
    private(set) var messages: [ConversationMessage] = []
    var draft = ""
    private(set) var isSending = false
    /// Increments per sent message; drives the send haptic.
    private(set) var sentCount = 0
    private(set) var attempt = 0

    private let chat: any ChatRepository
    private var isActive = false
    private var isMarkingRead = false
    private var unreadOnOpen = false
    /// Newest incoming message already covered by a read receipt (or known read when the channel opened).
    private var readThroughId: String?

    init(dependencies: Dependencies, conversationId: String) {
        chat = dependencies.chat
        self.conversationId = conversationId
    }

    var title: String { conversation?.name ?? Route.streamChannel(channelId: conversationId).title }

    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending }

    /// Consecutive incoming messages from the same author only label the first.
    func showsAuthor(at index: Int) -> Bool {
        guard messages.indices.contains(index), !messages[index].isFromCurrentUser else { return false }
        guard (conversation?.memberIds.count ?? 2) > 2 else { return false }
        return index == 0 || messages[index - 1].authorId != messages[index].authorId
    }

    /// Messages cluster until the sender changes or more than five minutes pass; each cluster gets one timestamp.
    static let clusterGap: TimeInterval = 5 * 60

    func showsTimestamp(at index: Int) -> Bool {
        Self.startsCluster(messages, at: index)
    }

    static func startsCluster(_ messages: [ConversationMessage], at index: Int) -> Bool {
        guard messages.indices.contains(index) else { return false }
        guard index > 0 else { return true }
        let previous = messages[index - 1], current = messages[index]
        return previous.authorId != current.authorId || current.createdAt.timeIntervalSince(previous.createdAt) > clusterGap
    }

    func observe() async {
        conversation = try? await chat.conversation(id: conversationId)
        unreadOnOpen = conversation.map { $0.unreadCount > 0 } ?? true
        var isFirst = true
        do {
            for try await messages in chat.messagesObserver(conversationId: conversationId) {
                self.messages = messages
                phase = .loaded
                if isFirst, !unreadOnOpen { readThroughId = latestIncomingId }
                isFirst = false
                await markReadIfNeeded()
            }
        } catch is CancellationError {
        } catch {
            FirebaseBootstrap.record(error: error)
            phase = .failed
        }
    }

    /// Read receipts only go out while the channel is on screen and the app is in the foreground.
    func setActive(_ active: Bool) async {
        isActive = active
        await markReadIfNeeded()
    }

    private var latestIncomingId: String? { messages.last { !$0.isFromCurrentUser }?.id }

    private var hasUnread: Bool { unreadOnOpen || latestIncomingId != readThroughId }

    private func markReadIfNeeded() async {
        guard phase == .loaded, !isMarkingRead else { return }
        isMarkingRead = true
        defer { isMarkingRead = false }
        while isActive, hasUnread {
            let target = latestIncomingId
            do {
                try await chat.markRead(conversationId: conversationId)
            } catch {
                return
            }
            unreadOnOpen = false
            readThroughId = target
        }
    }

    func retry() {
        phase = .loading
        attempt += 1
    }

    func loadOlder() async {
        try? await chat.loadOlderMessages(conversationId: conversationId)
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        draft = ""
        defer { isSending = false }
        do {
            try await chat.sendMessage(text, conversationId: conversationId)
            sentCount += 1
        } catch {
            FirebaseBootstrap.record(error: error)
            draft = text
        }
    }
}
