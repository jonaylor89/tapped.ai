import Foundation
import TappedDomain
import Testing
@testable import TappedData

/// Scripted `ChatTransport`: canned responses, a controllable event stream, and a call log.
final class FakeChatTransport: ChatTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _inbox: ChatInboxPage
    private var _pages: [String: [ChatMessageDTO]] = [:]
    private var _sendFailures: [any Error] = []
    private var _calls: [String] = []
    private var _events: AsyncThrowingStream<ChatEvent, any Error>.Continuation?
    private var _sent: [String] = []

    init(inbox: ChatInboxPage = ChatInboxPage(conversations: [], unreadTotal: 0)) {
        _inbox = inbox
    }

    var calls: [String] { lock.withLock { _calls } }
    var sentIds: [String] { lock.withLock { _sent } }
    func setInbox(_ inbox: ChatInboxPage) { lock.withLock { _inbox = inbox } }
    func setHistory(_ conversationId: String, _ messages: [ChatMessageDTO]) { lock.withLock { _pages[conversationId] = messages } }
    func failNextSends(_ errors: [any Error]) { lock.withLock { _sendFailures = errors } }
    func emit(_ event: ChatEvent) { lock.withLock { _events }?.yield(event) }
    private func log(_ call: String) { lock.withLock { _calls.append(call) } }

    func inbox(cursor: String?, limit: Int) async throws -> ChatInboxPage {
        log("inbox")
        return lock.withLock { _inbox }
    }

    func conversation(id: String) async throws -> ChatConversationDTO? {
        log("conversation \(id)")
        return lock.withLock { _inbox.conversations.first { $0.id == id } }
    }

    func openDirect(userId: String) async throws -> ChatConversationDTO {
        log("open \(userId)")
        return ChatConversationDTO(id: "new", members: [.init(id: "me", name: "Me"), .init(id: userId, name: "Them")],
                                   createdAt: .now)
    }

    func messages(conversationId: String, before: Int64?, after: Int64?, limit: Int) async throws -> ChatMessagePage {
        log("messages \(conversationId) before=\(before.map(String.init) ?? "-") after=\(after.map(String.init) ?? "-")")
        let all = lock.withLock { _pages[conversationId] ?? [] }
        if let after {
            let newer = all.filter { $0.seq > after }
            return ChatMessagePage(messages: Array(newer.prefix(limit)), hasMore: newer.count > limit)
        }
        let older = all.filter { before == nil || $0.seq < before! }
        return ChatMessagePage(messages: Array(older.suffix(limit)), hasMore: older.count > limit)
    }

    func send(conversationId: String, messageId: String, text: String) async throws -> ChatMessageDTO {
        log("send \(messageId)")
        if let error: any Error = lock.withLock({ _sendFailures.isEmpty ? nil : _sendFailures.removeFirst() }) { throw error }
        return lock.withLock {
            _sent.append(messageId)
            let seq = (_pages[conversationId]?.last?.seq ?? 0) + 1
            let message = msg(seq, in: conversationId, from: "me", text: text, id: messageId)
            _pages[conversationId, default: []].append(message)
            return message
        }
    }

    func markRead(conversationId: String, throughSeq: Int64?) async throws -> ChatReadResult {
        log("read \(conversationId) through=\(throughSeq.map(String.init) ?? "-")")
        return ChatReadResult(lastReadSeq: throughSeq ?? 0, unreadTotal: 0)
    }

    func events() -> AsyncThrowingStream<ChatEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream<ChatEvent, any Error>.makeStream()
        lock.withLock { _events = continuation }
        return stream
    }
}

func msg(_ seq: Int64, in conversationId: String = "c1", from author: String = "venue", text: String? = nil,
         id: String? = nil) -> ChatMessageDTO {
    ChatMessageDTO(id: id ?? "m\(seq)", conversationId: conversationId, seq: seq, authorId: author,
                   text: text ?? "message \(seq)", createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(seq)))
}

func conversationDTO(_ id: String = "c1", lastSeq: Int64, unread: Int = 0, frozen: Bool = false) -> ChatConversationDTO {
    ChatConversationDTO(
        id: id,
        members: [.init(id: "me", name: "Me"), .init(id: "venue", name: "The Bluebird", imageUrl: "https://img.example.test/b.jpg")],
        frozen: frozen,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        lastSeq: lastSeq,
        lastReadSeq: lastSeq - Int64(unread),
        unreadCount: unread,
        lastMessage: lastSeq > 0 ? msg(lastSeq, in: id) : nil,
        lastMessageAt: lastSeq > 0 ? msg(lastSeq, in: id).createdAt : nil
    )
}

private let me = UserModel(id: "me", username: "me", email: "me@example.test")

/// The first value from `iterator` matching `predicate` (Swift Testing's time limit bounds the wait).
@MainActor
private func first<I: AsyncIteratorProtocol>(
    _ iterator: inout I, where predicate: (I.Element) -> Bool
) async throws -> I.Element {
    while let value = try await iterator.next(isolation: MainActor.shared) {
        if predicate(value) { return value }
    }
    throw CancellationError()
}

/// Polls `condition` on the main actor until it holds (repository work hops through tasks).
@MainActor
private func eventually(_ condition: @MainActor () async -> Bool) async throws {
    for _ in 0..<200 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("condition never became true")
}

@Suite("Server-sent event parsing")
struct ServerSentEventParserTests {
    private func parse(_ text: String) -> [String] {
        var parser = ServerSentEventParser()
        return text.utf8.compactMap { parser.consume($0) }
    }

    @Test func dispatchesDataOnBlankLinesAndSkipsKeepAlives() {
        #expect(parse("data: {\"a\":1}\n\n:\n\ndata: two\n\n") == ["{\"a\":1}", "two"])
    }

    @Test func handlesCRLFMultiLineDataAndOtherFields() {
        #expect(parse("event: x\r\nid: 7\r\ndata: one\r\ndata:two\r\n\r\n") == ["one\ntwo"])
    }

    @Test func holdsAnIncompleteEvent() {
        #expect(parse("data: partial\n").isEmpty)
    }

    @Test func decodesServerEventsIncludingMicrosecondTimestamps() throws {
        let json = #"{"type":"message","conversationId":"c1","lastReadSeq":2,"unreadCount":1,"unreadTotal":4,"frozen":false,"message":{"id":"m3","conversationId":"c1","seq":3,"authorId":"venue","text":"hi","attachments":[],"createdAt":"2026-11-17T12:00:00.123456Z"}}"#
        guard case let .message(message, unread, lastRead, total, frozen)? = try ChatEvent.decode(Data(json.utf8)) else {
            Issue.record("not a message event")
            return
        }
        #expect(message.seq == 3)
        #expect(abs(message.createdAt.timeIntervalSince1970 - 1_794_916_800.123456) < 0.001)
        #expect((unread, lastRead, total, frozen) == (1, 2, 4, false))
        #expect(try ChatEvent.decode(Data(#"{"type":"ready","unreadTotal":3}"#.utf8)) == .ready(unreadTotal: 3))
        #expect(try ChatEvent.decode(Data(#"{"type":"typing"}"#.utf8)) == nil)
    }
}

@Suite("TappedChatRepository", .timeLimit(.minutes(1)))
@MainActor
struct TappedChatRepositoryTests {
    private func connected(_ transport: FakeChatTransport, cache: ChatDiskCache? = nil) async throws -> TappedChatRepository {
        let repository = TappedChatRepository(transport: transport, network: nil, cache: cache)
        try await repository.connectUser(me)
        return repository
    }

    @Test func readyResyncsTheInboxAndBadge() async throws {
        let transport = FakeChatTransport(inbox: ChatInboxPage(conversations: [conversationDTO(lastSeq: 3, unread: 2)], unreadTotal: 2))
        let chat = try await connected(transport)
        var unread = chat.unreadCountUpdates().makeAsyncIterator()
        transport.emit(.ready(unreadTotal: 2))
        var list = chat.conversationsObserver().makeAsyncIterator()
        let conversations = try #require(try await list.next())
        #expect(conversations.map(\.name) == ["The Bluebird"])
        #expect(conversations.first?.unreadCount == 2)
        #expect(conversations.first?.imageURL == URL(string: "https://img.example.test/b.jpg"))
        _ = try await first(&unread) { $0 == 2 }
    }

    @Test func liveMessagesAppendAndGapsAreFilledFromTheServer() async throws {
        let transport = FakeChatTransport(inbox: ChatInboxPage(conversations: [conversationDTO(lastSeq: 2)], unreadTotal: 0))
        transport.setHistory("c1", [msg(1), msg(2)])
        let chat = try await connected(transport)
        var messages = chat.messagesObserver(conversationId: "c1").makeAsyncIterator()
        var list = chat.conversationsObserver().makeAsyncIterator()
        _ = try await first(&messages) { $0.count == 2 }
        _ = try await first(&list) { !$0.isEmpty }

        transport.emit(.message(msg(3), unreadCount: 1, lastReadSeq: 2, unreadTotal: 1, frozen: nil))
        _ = try await first(&messages) { $0.map(\.id) == ["m1", "m2", "m3"] }
        // seq 4 and 5 were missed (e.g. while backgrounded): 6 arrives, the gap is fetched.
        transport.setHistory("c1", [msg(1), msg(2), msg(3), msg(4), msg(5), msg(6)])
        transport.emit(.message(msg(6), unreadCount: 4, lastReadSeq: 2, unreadTotal: 4, frozen: nil))
        _ = try await first(&messages) { $0.map(\.id) == ["m1", "m2", "m3", "m4", "m5", "m6"] }
        #expect(transport.calls.contains("messages c1 before=- after=3"))
        #expect(try await chat.conversation(id: "c1")?.unreadCount == 4)
    }

    @Test func sendsShowImmediatelyRetryWithTheSameIdAndClearUnread() async throws {
        let transport = FakeChatTransport(inbox: ChatInboxPage(conversations: [conversationDTO(lastSeq: 1, unread: 1)], unreadTotal: 1))
        transport.setHistory("c1", [msg(1)])
        let chat = try await connected(transport)
        var messages = chat.messagesObserver(conversationId: "c1").makeAsyncIterator()
        _ = try await messages.next()
        try await eventually { (try? await chat.conversation(id: "c1")) != nil }
        transport.failNextSends([URLError(.networkConnectionLost)])

        try await chat.sendMessage("see you at 7", conversationId: "c1")
        let sendCalls = transport.calls.filter { $0.hasPrefix("send ") }
        #expect(sendCalls.count == 2, "a transient failure retried once")
        #expect(Set(sendCalls).count == 1, "with the same message id")
        let latest = try await first(&messages) { $0.last?.status == .sent && $0.last?.text == "see you at 7" }
        #expect(latest.count == 2, "the confirmed message replaced the optimistic one")
        #expect(latest.last?.isFromCurrentUser == true)
        #expect(try await chat.conversation(id: "c1")?.unreadCount == 0, "sending reads the conversation")
    }

    @Test func aFailedSendDisappearsAndThrowsSoTheDraftComesBack() async throws {
        let transport = FakeChatTransport(inbox: ChatInboxPage(conversations: [conversationDTO(lastSeq: 1)], unreadTotal: 0))
        transport.setHistory("c1", [msg(1)])
        let chat = try await connected(transport)
        var messages = chat.messagesObserver(conversationId: "c1").makeAsyncIterator()
        _ = try await messages.next()
        transport.failNextSends([ChatTransportError.unexpectedStatus(409)])
        await #expect(throws: ChatTransportError.unexpectedStatus(409)) {
            try await chat.sendMessage("hello?", conversationId: "c1")
        }
        _ = try await first(&messages) { $0.map(\.id) == ["m1"] }
    }

    @Test func markReadIsOptimisticAndSkippedWhenNothingIsUnread() async throws {
        let transport = FakeChatTransport(inbox: ChatInboxPage(conversations: [conversationDTO(lastSeq: 5, unread: 3)], unreadTotal: 3))
        let chat = try await connected(transport)
        var list = chat.conversationsObserver().makeAsyncIterator()
        _ = try await list.next()
        try await chat.markRead(conversationId: "c1")
        #expect(try await chat.conversation(id: "c1")?.unreadCount == 0)
        #expect(transport.calls.contains("read c1 through=5"))
        try await chat.markRead(conversationId: "c1")
        #expect(transport.calls.filter { $0.hasPrefix("read ") }.count == 1)
    }

    @Test func frozenConversationsThawWhenTheVenueReplies() async throws {
        let transport = FakeChatTransport(inbox: ChatInboxPage(conversations: [conversationDTO(lastSeq: 1, frozen: true)], unreadTotal: 0))
        let chat = try await connected(transport)
        var list = chat.conversationsObserver().makeAsyncIterator()
        #expect(try await list.next()?.first?.isFrozen == true)
        transport.emit(.message(msg(2), unreadCount: 1, lastReadSeq: 1, unreadTotal: 1, frozen: false))
        try await eventually { (try? await chat.conversation(id: "c1"))?.isFrozen == false }
    }

    @Test func directConversationsAreReusedPerPair() async throws {
        let transport = FakeChatTransport(inbox: ChatInboxPage(conversations: [conversationDTO(lastSeq: 1)], unreadTotal: 0))
        let chat = try await connected(transport)
        var list = chat.conversationsObserver().makeAsyncIterator()
        _ = try await list.next()
        #expect(try await chat.createDirectConversation(with: "venue") == "c1")
        #expect(try await chat.createDirectConversation(with: "someone-else") == "new")
        #expect(transport.calls.filter { $0.hasPrefix("open ") } == ["open someone-else"])
    }

    @Test func theDiskCacheRendersBeforeTheNetworkAndIsWipedOnSignOut() async throws {
        let directory = URL.temporaryDirectory.appending(path: "chat-cache-\(UUID().uuidString)")
        let cache = ChatDiskCache(directory: directory)
        await cache.save(.init(conversations: [conversationDTO(lastSeq: 2)], messages: ["c1": [msg(1), msg(2)]], unreadTotal: 0),
                         userId: "me")
        let transport = FakeChatTransport()
        let chat = try await connected(transport, cache: cache)
        var messages = chat.messagesObserver(conversationId: "c1").makeAsyncIterator()
        #expect(try await messages.next()?.map(\.id) == ["m1", "m2"], "cached history shows first")
        await chat.disconnect()
        #expect(await cache.load(userId: "me") == nil)
        await #expect(throws: ChatError.notConnected) { _ = try await chat.createDirectConversation(with: "venue") }
    }
}
