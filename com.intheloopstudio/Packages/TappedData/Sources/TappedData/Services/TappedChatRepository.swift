import Foundation
import TappedDomain
import UIKit

/// Direct messages on the Tapped API. Reads come from an in-memory store (seeded from a per-user disk
/// cache, so lists render instantly on cold open); one server-sent event stream keeps it live.
///
/// Correctness rests on the server's gap-free per-conversation `seq`: a live message that is not
/// the next `seq` triggers a gap fill, every (re)connect resyncs, and sends are idempotent per
/// client-generated message ID, so retries never duplicate.
@MainActor
public final class TappedChatRepository: ChatRepository {
    private struct Thread {
        /// Ascending, unique by `seq`.
        var messages: [ChatMessageDTO] = []
        var hasOlder = true
        var isLoaded = false
        var isLoadingOlder = false
        /// Own messages not yet confirmed by the server, shown after the history.
        var pending: [ConversationMessage] = []

        var newestSeq: Int64 { messages.last?.seq ?? 0 }

        /// The end of the gap-free run starting at the oldest loaded message; history is fetched
        /// forward from here, so a message that arrived ahead of its predecessors is not skipped.
        var contiguousSeq: Int64 {
            guard var expected = messages.first?.seq else { return 0 }
            for message in messages {
                if message.seq != expected { break }
                expected += 1
            }
            return expected - 1
        }

        var hasGap: Bool { contiguousSeq != newestSeq }

        /// Inserts by `seq` (replacing an equal `seq`) and drops matching pending messages.
        mutating func merge(_ incoming: [ChatMessageDTO]) {
            guard !incoming.isEmpty else { return }
            var bySeq = Dictionary(messages.map { ($0.seq, $0) }, uniquingKeysWith: { _, new in new })
            for message in incoming { bySeq[message.seq] = message }
            messages = bySeq.values.sorted { $0.seq < $1.seq }
            let ids = Set(incoming.map(\.id))
            pending.removeAll { ids.contains($0.id) }
        }
    }

    static let inboxPageSize = 50
    static let messagePageSize = 50
    static let cachedMessagesPerConversation = 50
    private static let sendAttempts = 3

    private let transport: any ChatTransport
    private let network: (any NetworkPathSource)?
    private let cache: ChatDiskCache?

    private var userId: String?
    private var conversations: [String: ChatConversationDTO] = [:]
    private var threads: [String: Thread] = [:]
    private var unreadTotal = 0
    private var inboxLoaded = false
    private var inboxRefresh: Task<Void, any Error>?
    private var gapFills: [String: Task<Void, any Error>] = [:]
    private var sessionTasks: [Task<Void, Never>] = []
    private var eventsTask: Task<Void, Never>?
    private var cacheWrite: Task<Void, Never>?

    private var unreadContinuations: [UUID: AsyncStream<Int>.Continuation] = [:]
    private var listContinuations: [UUID: AsyncThrowingStream<[Conversation], any Error>.Continuation] = [:]
    private var messageContinuations: [UUID: (conversationId: String, continuation: AsyncThrowingStream<[ConversationMessage], any Error>.Continuation)] = [:]

    public nonisolated init(
        transport: any ChatTransport,
        network: (any NetworkPathSource)? = NWPathNetworkSource(),
        cache: ChatDiskCache? = ChatDiskCache()
    ) {
        self.transport = transport
        self.network = network
        self.cache = cache
    }

    // MARK: - session

    public func connectUser(_ user: UserModel) async throws {
        if userId == user.id { return }
        if userId != nil { await disconnect() }
        userId = user.id
        if let snapshot = await cache?.load(userId: user.id), userId == user.id {
            apply(snapshot)
        }
        startSession()
    }

    public func disconnect() async {
        let previous = userId
        userId = nil
        eventsTask?.cancel()
        eventsTask = nil
        for task in sessionTasks { task.cancel() }
        sessionTasks = []
        inboxRefresh?.cancel()
        inboxRefresh = nil
        for task in gapFills.values { task.cancel() }
        gapFills = [:]
        cacheWrite?.cancel()
        cacheWrite = nil
        conversations = [:]
        threads = [:]
        unreadTotal = 0
        inboxLoaded = false
        publishAll()
        if let previous { await cache?.remove(userId: previous) }
    }

    /// The event loop, plus immediate reconnects when the app returns to the foreground or the
    /// network comes back (instead of waiting out the backoff).
    private func startSession() {
        restartEvents()
        sessionTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.willEnterForegroundNotification) {
                self?.restartEvents()
            }
        })
        if let network {
            sessionTasks.append(Task { [weak self] in
                var wasOnline = true
                for await isOnline in network.updates() {
                    if isOnline, !wasOnline { self?.restartEvents() }
                    wasOnline = isOnline
                }
            })
        }
    }

    private func restartEvents() {
        guard userId != nil else { return }
        eventsTask?.cancel()
        eventsTask = Task { [weak self] in await self?.runEvents() }
    }

    private func runEvents() async {
        var failures = 0
        while !Task.isCancelled, userId != nil {
            var delivered = false
            do {
                for try await event in transport.events() {
                    delivered = true
                    failures = 0
                    await handle(event)
                }
            } catch is CancellationError {
                return
            } catch {}
            guard !Task.isCancelled else { return }
            // A stream that delivered (it ended at its server lifetime or a deploy) reconnects at
            // once; one that failed or closed without a single event backs off up to 30 s.
            if !delivered { failures += 1 }
            if failures > 0 {
                let base = min(30.0, pow(2.0, Double(failures - 1)))
                try? await Task.sleep(for: .seconds(base + Double.random(in: 0...(base / 2))))
            }
        }
    }

    func handle(_ event: ChatEvent) async {
        switch event {
        case let .ready(total):
            setUnreadTotal(total)
            await resync()
        case .resync:
            await resync()
        case let .message(message, unreadCount, lastReadSeq, total, frozen):
            await receive(message, unreadCount: unreadCount, lastReadSeq: lastReadSeq, frozen: frozen)
            setUnreadTotal(total)
        case let .read(conversationId, lastReadSeq, unreadCount, total):
            if var conversation = conversations[conversationId] {
                conversation.lastReadSeq = max(conversation.lastReadSeq, lastReadSeq)
                conversation.unreadCount = unreadCount
                conversations[conversationId] = conversation
                publishList()
            }
            setUnreadTotal(total)
        }
    }

    /// Refetches the inbox and fills every loaded conversation forward from its newest message.
    private func resync() async {
        try? await refreshInbox()
        for id in threads.keys where threads[id]?.isLoaded == true {
            try? await fillGap(id)
        }
    }

    private func receive(_ message: ChatMessageDTO, unreadCount: Int, lastReadSeq: Int64, frozen: Bool?) async {
        let id = message.conversationId
        guard var conversation = conversations[id] else {
            // A conversation this device has not seen yet (a new contact): fetch its summary.
            if let fetched = try? await transport.conversation(id: id), userId != nil {
                conversations[id] = fetched
                publishList()
            }
            return
        }
        if message.seq >= conversation.lastSeq {
            conversation.lastSeq = message.seq
            conversation.lastMessage = message
            conversation.lastMessageAt = message.createdAt
        }
        conversation.lastReadSeq = max(conversation.lastReadSeq, lastReadSeq)
        conversation.unreadCount = unreadCount
        if let frozen { conversation.frozen = frozen }
        conversations[id] = conversation
        publishList()
        guard var thread = threads[id], thread.isLoaded else { return }
        thread.merge([message])
        threads[id] = thread
        publishMessages(id)
        if thread.hasGap { try? await fillGap(id) }
    }

    // MARK: - reads

    public nonisolated func unreadCountUpdates() -> AsyncStream<Int> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            Task { @MainActor in
                self.unreadContinuations[id] = continuation
                continuation.yield(self.unreadTotal)
            }
            continuation.onTermination = { _ in Task { @MainActor in self.unreadContinuations[id] = nil } }
        }
    }

    public nonisolated func conversationsObserver() -> AsyncThrowingStream<[Conversation], any Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            let task = Task { @MainActor in
                guard self.userId != nil else { return continuation.finish(throwing: ChatError.notConnected) }
                self.listContinuations[id] = continuation
                let hasCache = !self.conversations.isEmpty || self.inboxLoaded
                if hasCache { continuation.yield(self.sortedConversations) }
                guard !self.inboxLoaded else { return }
                do {
                    try await self.refreshInbox()
                } catch {
                    // Cached data stays on screen; the event loop retries.
                    if !hasCache, !(error is CancellationError) { continuation.finish(throwing: error) }
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { @MainActor in self.listContinuations[id] = nil }
            }
        }
    }

    public nonisolated func messagesObserver(conversationId: String) -> AsyncThrowingStream<[ConversationMessage], any Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            let task = Task { @MainActor in
                guard self.userId != nil else { return continuation.finish(throwing: ChatError.notConnected) }
                self.messageContinuations[id] = (conversationId, continuation)
                let thread = self.threads[conversationId]
                let hasCache = !(thread?.messages.isEmpty ?? true)
                if hasCache { continuation.yield(self.visibleMessages(conversationId)) }
                guard thread?.isLoaded != true else { return }
                do {
                    try await self.loadLatest(conversationId)
                } catch {
                    if !hasCache, !(error is CancellationError) { continuation.finish(throwing: error) }
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { @MainActor in self.messageContinuations[id] = nil }
            }
        }
    }

    public func loadOlderMessages(conversationId: String) async throws {
        guard var thread = threads[conversationId], thread.isLoaded, thread.hasOlder, !thread.isLoadingOlder,
              let oldest = thread.messages.first?.seq else { return }
        thread.isLoadingOlder = true
        threads[conversationId] = thread
        defer { threads[conversationId]?.isLoadingOlder = false }
        let page = try await transport.messages(conversationId: conversationId, before: oldest, after: nil,
                                                limit: Self.messagePageSize)
        guard var current = threads[conversationId] else { return }
        current.merge(page.messages)
        // `seq` starts at 1 and has no gaps, so the first message is the end of history.
        current.hasOlder = !page.messages.isEmpty && (current.messages.first?.seq ?? 1) > 1
        threads[conversationId] = current
        publishMessages(conversationId)
    }

    public func conversation(id: String) async throws -> Conversation? {
        guard let userId else { throw ChatError.notConnected }
        if let conversation = conversations[id] { return Self.conversation(conversation, currentUserId: userId) }
        guard let fetched = try await transport.conversation(id: id) else { return nil }
        guard self.userId == userId else { throw ChatError.notConnected }
        conversations[id] = fetched
        return Self.conversation(fetched, currentUserId: userId)
    }

    // MARK: - writes

    public func createDirectConversation(with otherUserId: String) async throws -> String {
        guard let userId else { throw ChatError.notConnected }
        let pair = Set([userId, otherUserId])
        if let existing = conversations.values.first(where: { Set($0.members.map(\.id)) == pair && $0.members.count == 2 }) {
            return existing.id
        }
        let conversation = try await transport.openDirect(userId: otherUserId)
        guard self.userId == userId else { throw ChatError.notConnected }
        conversations[conversation.id] = conversations[conversation.id] ?? conversation
        return conversation.id
    }

    /// Shows the message immediately as `.sending`. Transient failures retry with the same ID (the
    /// server deduplicates); a final failure removes it and throws so the caller restores the draft.
    public func sendMessage(_ text: String, conversationId: String) async throws {
        guard let userId else { throw ChatError.notConnected }
        let messageId = UUID().uuidString.lowercased()
        let author = conversations[conversationId]?.members.first { $0.id == userId }
        let optimistic = ConversationMessage(
            id: messageId, text: text, authorId: userId, authorName: author?.name ?? "",
            authorImageURL: author?.imageUrl.flatMap(URL.init(string:)), createdAt: .now,
            isFromCurrentUser: true, status: .sending
        )
        threads[conversationId, default: Thread()].pending.append(optimistic)
        publishMessages(conversationId)
        do {
            let sent = try await sendWithRetry(conversationId: conversationId, messageId: messageId, text: text)
            guard self.userId == userId else { return }
            confirmSent(sent)
        } catch {
            threads[conversationId]?.pending.removeAll { $0.id == messageId }
            publishMessages(conversationId)
            throw error
        }
    }

    private func sendWithRetry(conversationId: String, messageId: String, text: String) async throws -> ChatMessageDTO {
        var attempt = 0
        while true {
            do {
                return try await transport.send(conversationId: conversationId, messageId: messageId, text: text)
            } catch let error as URLError where attempt + 1 < Self.sendAttempts && error.code != .cancelled {
                attempt += 1
                try await Task.sleep(for: .milliseconds(400 * attempt))
            }
        }
    }

    private func confirmSent(_ message: ChatMessageDTO) {
        let id = message.conversationId
        if var conversation = conversations[id] {
            if message.seq >= conversation.lastSeq {
                conversation.lastSeq = message.seq
                conversation.lastMessage = message
                conversation.lastMessageAt = message.createdAt
            }
            // Sending reads everything before it.
            conversation.lastReadSeq = max(conversation.lastReadSeq, message.seq)
            conversation.unreadCount = Int(max(0, conversation.lastSeq - conversation.lastReadSeq))
            conversations[id] = conversation
            publishList()
        }
        guard var thread = threads[id] else { return }
        thread.merge([message])
        threads[id] = thread
        publishMessages(id)
        // Messages from others may have landed between our newest and this one.
        if thread.isLoaded, thread.hasGap { Task { try? await self.fillGap(id) } }
    }

    /// Optimistically clears the conversation's unread count, then confirms with the server.
    public func markRead(conversationId: String) async throws {
        guard userId != nil, var conversation = conversations[conversationId] else { return }
        let through = max(conversation.lastSeq, threads[conversationId]?.newestSeq ?? 0)
        guard conversation.lastReadSeq < through || conversation.unreadCount > 0 else { return }
        setUnreadTotal(max(0, unreadTotal - conversation.unreadCount))
        conversation.lastReadSeq = through
        conversation.unreadCount = 0
        conversations[conversationId] = conversation
        publishList()
        let result = try await transport.markRead(conversationId: conversationId, throughSeq: through)
        setUnreadTotal(result.unreadTotal)
    }

    // MARK: - loading

    private func refreshInbox() async throws {
        if let inboxRefresh { return try await inboxRefresh.value }
        let task = Task { @MainActor in
            let page = try await self.transport.inbox(cursor: nil, limit: Self.inboxPageSize)
            guard self.userId != nil else { return }
            for conversation in page.conversations { self.conversations[conversation.id] = conversation }
            self.inboxLoaded = true
            self.unreadTotal = page.unreadTotal
            self.publishAll()
        }
        inboxRefresh = task
        defer { inboxRefresh = nil }
        try await task.value
    }

    private func loadLatest(_ conversationId: String) async throws {
        let page = try await transport.messages(conversationId: conversationId, before: nil, after: nil,
                                                limit: Self.messagePageSize)
        guard userId != nil else { return }
        var thread = threads[conversationId] ?? Thread()
        // A cache that does not reach this page is stale or has a hole; the page replaces it.
        if let first = page.messages.first?.seq, thread.contiguousSeq + 1 < first {
            thread.messages = []
        }
        thread.merge(page.messages)
        thread.hasOlder = (thread.messages.first?.seq ?? 1) > 1
        thread.isLoaded = true
        threads[conversationId] = thread
        publishMessages(conversationId)
    }

    /// Fetches everything after the newest loaded message. Concurrent callers share one fill.
    private func fillGap(_ conversationId: String) async throws {
        if let running = gapFills[conversationId] { return try await running.value }
        let task = Task { @MainActor in
            while self.userId != nil, let thread = self.threads[conversationId], thread.isLoaded {
                let page = try await self.transport.messages(conversationId: conversationId, before: nil,
                                                             after: thread.contiguousSeq, limit: Self.messagePageSize)
                self.threads[conversationId]?.merge(page.messages)
                self.publishMessages(conversationId)
                // A seq that never arrives (a deleted message) must not refetch the same page forever.
                let advanced = (self.threads[conversationId]?.contiguousSeq ?? 0) > thread.contiguousSeq
                if !page.hasMore || page.messages.isEmpty || !advanced { break }
            }
        }
        gapFills[conversationId] = task
        defer { gapFills[conversationId] = nil }
        try await task.value
    }

    // MARK: - publishing

    private var sortedConversations: [Conversation] {
        guard let userId else { return [] }
        return conversations.values
            .filter { $0.lastSeq > 0 }
            .sorted { ($0.lastMessageAt ?? $0.createdAt, $0.id) > ($1.lastMessageAt ?? $1.createdAt, $1.id) }
            .map { Self.conversation($0, currentUserId: userId) }
    }

    private func visibleMessages(_ conversationId: String) -> [ConversationMessage] {
        guard let userId, let thread = threads[conversationId] else { return [] }
        let members = Dictionary((conversations[conversationId]?.members ?? []).map { ($0.id, $0) },
                                 uniquingKeysWith: { first, _ in first })
        let confirmed = Set(thread.messages.map(\.id))
        return thread.messages.map { Self.message($0, author: members[$0.authorId], currentUserId: userId) }
            + thread.pending.filter { !confirmed.contains($0.id) }
    }

    private func setUnreadTotal(_ total: Int) {
        guard total != unreadTotal else { return }
        unreadTotal = total
        for continuation in unreadContinuations.values { continuation.yield(total) }
        scheduleCacheWrite()
    }

    private func publishAll() {
        for continuation in unreadContinuations.values { continuation.yield(unreadTotal) }
        publishList()
        for entry in messageContinuations.values { entry.continuation.yield(visibleMessages(entry.conversationId)) }
    }

    private func publishList() {
        let list = sortedConversations
        for continuation in listContinuations.values { continuation.yield(list) }
        scheduleCacheWrite()
    }

    private func publishMessages(_ conversationId: String) {
        var messages: [ConversationMessage]?
        for entry in messageContinuations.values where entry.conversationId == conversationId {
            if messages == nil { messages = visibleMessages(conversationId) }
            entry.continuation.yield(messages!)
        }
        scheduleCacheWrite()
    }

    // MARK: - disk cache

    private func apply(_ snapshot: ChatDiskCache.Snapshot) {
        for conversation in snapshot.conversations { conversations[conversation.id] = conversation }
        for (id, messages) in snapshot.messages {
            var thread = Thread()
            thread.merge(messages)
            threads[id] = thread
        }
        unreadTotal = snapshot.unreadTotal
        publishAll()
    }

    /// Coalesces bursts of updates into one write a second later, off the main actor.
    private func scheduleCacheWrite() {
        guard let cache, let userId, cacheWrite == nil else { return }
        cacheWrite = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled, self.userId == userId else { return }
            self.cacheWrite = nil
            let snapshot = ChatDiskCache.Snapshot(
                conversations: Array(self.conversations.values.filter { $0.lastSeq > 0 }),
                messages: self.threads.mapValues { Array($0.messages.suffix(Self.cachedMessagesPerConversation)) }
                    .filter { !$0.value.isEmpty },
                unreadTotal: self.unreadTotal
            )
            await cache.save(snapshot, userId: userId)
        }
    }

    // MARK: - mapping

    static func conversation(_ dto: ChatConversationDTO, currentUserId: String) -> Conversation {
        let others = dto.members.filter { $0.id != currentUserId }
        return Conversation(
            id: dto.id,
            name: others.map(\.name).filter { !$0.isEmpty }.joined(separator: ", ").nonEmpty ?? "conversation",
            imageURL: others.first?.imageUrl.flatMap(URL.init(string:)),
            memberIds: dto.members.map(\.id),
            lastMessageText: dto.lastMessage.map(previewText(for:)),
            lastMessageAt: dto.lastMessageAt,
            unreadCount: dto.unreadCount,
            isFrozen: dto.frozen
        )
    }

    static func previewText(for message: ChatMessageDTO) -> String {
        if !message.text.isEmpty { return message.text }
        return message.attachments.contains { $0.type == "image" } ? "sent a photo" : "sent an attachment"
    }

    static func message(_ dto: ChatMessageDTO, author: ChatMemberDTO?, currentUserId: String) -> ConversationMessage {
        ConversationMessage(
            id: dto.id,
            text: dto.text.isEmpty ? previewText(for: dto) : dto.text,
            authorId: dto.authorId,
            authorName: author?.name ?? dto.authorId,
            authorImageURL: author?.imageUrl.flatMap(URL.init(string:)),
            createdAt: dto.createdAt,
            isFromCurrentUser: dto.authorId == currentUserId,
            imageURLs: dto.attachments.filter { $0.type == "image" }.compactMap { URL(string: $0.url) },
            status: .sent
        )
    }
}

/// Per-user snapshot of recent conversations and messages in Caches, so the inbox and open
/// conversations render before the network answers. Deleted on sign out.
public actor ChatDiskCache {
    public struct Snapshot: Codable, Sendable, Equatable {
        public var conversations: [ChatConversationDTO]
        public var messages: [String: [ChatMessageDTO]]
        public var unreadTotal: Int
    }

    private static let version = 1
    private let directory: URL

    public init(directory: URL = URL.cachesDirectory.appending(path: "tapped-chat", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    private func file(_ userId: String) -> URL {
        // User IDs are Firebase UIDs; encode anyway so no ID can escape the directory.
        let name = Data(userId.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        return directory.appending(path: "v\(Self.version)-\(name).json")
    }

    public func load(userId: String) -> Snapshot? {
        guard let data = try? Data(contentsOf: file(userId)) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    public func save(_ snapshot: Snapshot, userId: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: file(userId), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            ErrorReporting.record(error: error)
        }
    }

    public func remove(userId: String) {
        try? FileManager.default.removeItem(at: file(userId))
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
