import Foundation
import TappedData
import TappedDomain
import Testing
import UIKit
@testable import Tapped

@MainActor
@Suite("Paywall, messaging + admin")
struct PaywallMessagingAdminTests {
    // MARK: paywall

    @Test func paywallLoadsProductsAndPurchases() async {
        let model = PaywallViewModel(dependencies: .mock(signedIn: true))
        await model.load()
        #expect(model.phase == .ready)
        #expect(!model.products.isEmpty)
        #expect(model.selectedProduct != nil)
        #expect(!model.isPremium)

        await model.purchase()
        #expect(model.isPremium)
        #expect(model.successCount == 1)
        #expect(model.notice == nil)
    }

    @Test func paywallRestoreWithoutPurchasesShowsNotice() async {
        let model = PaywallViewModel(dependencies: .mock(signedIn: true))
        await model.load()
        await model.restore()
        #expect(!model.isPremium)
        #expect(model.notice == "no purchases to restore")
    }

    @Test func paywallAlreadyPremium() async {
        let model = PaywallViewModel(dependencies: .mock(signedIn: true, isPremium: true))
        await model.load()
        #expect(model.isPremium)
        #expect(model.phase == .ready)
    }

    @Test func premiumGateRoutesToPaywall() {
        let route = Route.messagingChannelList
        #expect(route.requiringPremium(true) == route)
        #expect(route.requiringPremium(false) == .paywall)
        let router = Router()
        router.push(.admin, requiresPremium: false)
        #expect(router.path == [.paywall])
    }

    // MARK: messaging

    @Test func channelListObservesConversations() async throws {
        let dependencies = Dependencies.mock(signedIn: true)
        try await dependencies.chat.connectUser(Samples.performer)
        let model = ChannelListViewModel(dependencies: dependencies)
        let task = Task { await model.observe() }
        defer { task.cancel() }
        try await waitUntil { model.phase == .loaded }
        #expect(model.conversations.count == Samples.conversations.count)
    }

    @Test func channelSendsMessageAndClearsDraft() async throws {
        let dependencies = Dependencies.mock(signedIn: true)
        try await dependencies.chat.connectUser(Samples.performer)
        let id = Samples.conversations[0].id
        let model = ChannelViewModel(dependencies: dependencies, conversationId: id)
        let task = Task { await model.observe() }
        defer { task.cancel() }
        try await waitUntil { model.phase == .loaded }
        let before = model.messages.count

        model.draft = "   "
        #expect(!model.canSend)
        model.draft = "load-in at 7?"
        await model.send()
        #expect(model.draft.isEmpty)
        #expect(model.sentCount == 1)
        try await waitUntil { model.messages.count == before + 1 }
        #expect(model.messages.last?.text == "load-in at 7?")
    }

    @Test func shellPublishesUnreadCount() async throws {
        let chat = MockChatRepository()
        let shell = ShellViewModel(currentUser: Samples.performer, chat: chat)
        let task = Task { await shell.run() }
        defer { task.cancel() }
        let expected = Samples.conversations.reduce(0) { $0 + $1.unreadCount }
        try await waitUntil { shell.unreadMessages == expected }
        #expect(shell.isChatConnected)
    }

    // MARK: admin

    @Test func createOpportunityValidation() async {
        let model = CreateOpportunityViewModel(dependencies: .mock(signedIn: true, claims: [.admin]), currentUserId: "admin")
        #expect(await model.submit() == nil)
        #expect(model.errorMessage == "missing title")
        model.title = "open mic"
        #expect(await model.submit() == nil)
        #expect(model.errorMessage == "missing description")
        model.description = "bring your own mic"
        #expect(await model.submit() == nil)
        #expect(model.errorMessage == "missing location")
    }

    @Test func createOpportunityKeepsDurationWhenStartMoves() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = CreateOpportunityViewModel(dependencies: .mock(), currentUserId: "admin", now: now)
        model.endTimeChanged(model.startTime.addingTimeInterval(3600))
        model.startTime = model.startTime.addingTimeInterval(86400)
        #expect(model.endTime.timeIntervalSince(model.startTime) == 3600)
    }

    @Test func createOpportunityAtVenueWritesOpportunityAndFeeds() async throws {
        let dependencies = Dependencies.mock(signedIn: true, claims: [.admin])
        let model = CreateOpportunityViewModel(dependencies: dependencies, currentUserId: "admin")
        let venue = try #require(Samples.venues.first { $0.location != nil })
        model.title = "friday showcase"
        model.description = "three local acts"
        model.isPaid = true
        model.selectVenue(venue)
        model.setFlier(data: Self.jpeg)

        let opportunity = try #require(await model.submit())
        #expect(model.errorMessage == nil)
        #expect(opportunity.venueId == venue.id)
        #expect(opportunity.userId == "admin")
        #expect(opportunity.location == venue.location)
        #expect(opportunity.isPaid)
        #expect(opportunity.flierUrl == "https://example.com/images/opportunities/\(opportunity.id).jpg")
        let database = try #require(dependencies.database as? MockDatabaseRepository)
        #expect(try await database.getOpportunityById(opportunity.id) == opportunity)
        #expect(await !database.opportunityFeeds.isEmpty)
    }

    @Test func createOpportunityWithDroppedPin() async throws {
        let model = CreateOpportunityViewModel(dependencies: .mock(signedIn: true, claims: [.admin]), currentUserId: "admin")
        model.title = "rooftop set"
        model.description = "sunset dj slot"
        model.placeQuery = "rich"
        await model.searchPlaces()
        let prediction = try #require(model.placeResults.first)
        await model.selectPlace(prediction)
        #expect(model.locationSummary != nil)
        let opportunity = try #require(await model.submit())
        #expect(opportunity.location.placeId == prediction.placeId)
        #expect(opportunity.venueId == nil)
    }

    private static let jpeg: Data = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        return renderer.jpegData(withCompressionQuality: 0.8) { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }()

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("condition not met")
    }

    // MARK: timestamp grouping

    @Test func timestampsOnlyStartClusters() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        func message(_ id: String, _ author: String, _ minutes: Double) -> ConversationMessage {
            ConversationMessage(
                id: id, text: id, authorId: author, authorName: author,
                createdAt: start.addingTimeInterval(minutes * 60), isFromCurrentUser: author == "me"
            )
        }
        let messages = [
            message("a", "me", 0),
            message("b", "me", 1),
            message("c", "me", 5.9),
            message("d", "them", 6),
            message("e", "them", 12),
            message("f", "them", 17),
        ]
        let shown = messages.indices.map { ChannelViewModel.startsCluster(messages, at: $0) }
        #expect(shown == [true, false, false, true, true, false])
        #expect(!ChannelViewModel.startsCluster(messages, at: 99))
    }

    @Test func paywallFallsBackToBundledProductIds() {
        let model = PaywallViewModel(dependencies: .mock(signedIn: true))
        #expect(model.productIds == TappedConfig.defaultPremiumProductIds)
    }
}
