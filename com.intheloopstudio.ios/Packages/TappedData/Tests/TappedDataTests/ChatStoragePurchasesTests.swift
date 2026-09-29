import Foundation
import TappedDomain
import Testing
@testable import TappedData

@Suite("Chat, storage, purchases + admin mocks")
struct ChatStoragePurchasesTests {
    @Test func mockChatRequiresConnectionForDirectMessages() async {
        await #expect(throws: ChatError.notConnected) {
            _ = try await MockChatRepository().createDirectConversation(with: Samples.venues[0].id)
        }
    }

    @Test func mockChatCreatesDirectConversationOnceAndSends() async throws {
        let chat = MockChatRepository(conversations: [], messages: [:])
        try await chat.connectUser(Samples.performer)
        let venue = Samples.venues[0]
        let id = try await chat.createDirectConversation(with: venue.id)
        #expect(try await chat.createDirectConversation(with: venue.id) == id)
        let conversation = try #require(try await chat.conversation(id: id))
        #expect(conversation.name == venue.displayName)
        #expect(Set(conversation.memberIds) == [Samples.performer.id, venue.id])

        try await chat.sendMessage("see you friday", conversationId: id)
        var messages = chat.messagesObserver(conversationId: id).makeAsyncIterator()
        let first = try await messages.next()
        #expect(first?.map(\.text) == ["see you friday"])
        #expect(first?.first?.isFromCurrentUser == true)
        #expect(try await chat.conversation(id: id)?.lastMessageText == "see you friday")
    }

    @Test func mockChatUnreadCountDropsOnMarkRead() async throws {
        let chat = MockChatRepository()
        try await chat.connectUser(Samples.performer)
        var unread = chat.unreadCountUpdates().makeAsyncIterator()
        let initial = try #require(await unread.next())
        let expected = Samples.conversations.reduce(0) { $0 + $1.unreadCount }
        #expect(initial == expected)
        let withUnread = try #require(Samples.conversations.first { $0.unreadCount > 0 })
        try await chat.markRead(conversationId: withUnread.id)
        #expect(await unread.next() == expected - withUnread.unreadCount)
    }

    @Test func mockChatRejectsUnknownConversation() async throws {
        let chat = MockChatRepository()
        try await chat.connectUser(Samples.performer)
        await #expect(throws: ChatError.invalidConversationId) {
            try await chat.sendMessage("hi", conversationId: "nope")
        }
    }

    @Test func mockStorageReturnsDeterministicURL() async throws {
        let storage = MockStorageRepository()
        let url = try await storage.uploadOpportunityFlier(opportunityId: "abc", jpegData: Data([1]))
        #expect(url.lastPathComponent == "abc.jpg")
        #expect(await storage.uploads["abc"] == Data([1]))
    }

    @Test func mockPurchasesBroadcastToEveryObserver() async throws {
        let purchases = MockPurchasesRepository()
        var first = purchases.entitlementUpdates().makeAsyncIterator()
        var second = purchases.entitlementUpdates().makeAsyncIterator()
        #expect(await first.next() == [])
        #expect(await second.next() == [])
        _ = try await purchases.purchase(productId: TappedConfig.defaultPremiumProductIds[0])
        #expect(await first.next() == [.premium])
        #expect(await second.next() == [.premium])
    }

    @Test func mockProductsCarrySubscriptionPeriods() async throws {
        let products = try await MockPurchasesRepository().products()
        #expect(products.compactMap(\.period).count == products.count)
    }

    @Test func copyOpportunityToFeedsSkipsCreatorStaffAndDeletedUsers() async throws {
        var staff = Samples.performers[1]
        staff.email = "ops@tapped.ai"
        var deleted = Samples.performers[2]
        deleted.deleted = true
        let creator = Samples.venues[0]
        let fan = Samples.performer
        let database = MockDatabaseRepository(users: [creator, staff, deleted, fan])
        var opportunity = Samples.opportunities[0]
        opportunity.id = "new-op"
        opportunity.userId = creator.id

        try await database.createOpportunity(opportunity)
        try await database.copyOpportunityToFeeds(opportunity)

        #expect(try await database.getOpportunityById("new-op") == opportunity)
        #expect(Set(await database.opportunityFeeds.keys) == [fan.id])
        #expect(await database.opportunityFeeds[fan.id]?["new-op"] == opportunity)
    }

    @Test func mockDependenciesWireChatAndStorage() {
        let dependencies = Dependencies.mock()
        #expect(dependencies.chat is MockChatRepository)
        #expect(dependencies.storage is MockStorageRepository)
    }
}
