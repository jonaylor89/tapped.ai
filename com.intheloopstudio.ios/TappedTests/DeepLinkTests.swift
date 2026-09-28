import Foundation
import TappedData
import TappedDomain
import Testing
@testable import Tapped

@MainActor
@Suite("Deep links")
struct DeepLinkTests {
    @Test(arguments: [
        ("https://app.tapped.ai/u/DJNova", DeepLink.profile(username: "djnova")),
        ("https://tappednetwork.page.link/djnova", .profile(username: "djnova")),
        ("https://app.tapped.ai/map?user_id=performer-nova", .profileId(userId: "performer-nova")),
        ("https://app.tapped.ai/opportunity/op-friday-openers", .opportunity(opportunityId: "op-friday-openers")),
        ("https://app.tapped.ai/booking/booking-1", .booking(bookingId: "booking-1")),
        ("https://app.tapped.ai/settings", .settings),
        ("https://app.tapped.ai/connect_payment?account_id=acct_123", .connectPayment(accountId: "acct_123")),
        ("com.intheloopstudio://u/djnova", .profile(username: "djnova")),
        ("com.intheloopstudio://opportunity/abc", .opportunity(opportunityId: "abc")),
    ])
    func parsesLinks(url: String, expected: DeepLink) throws {
        #expect(DeepLink(url: try #require(URL(string: url))) == expected)
    }

    @Test(arguments: [
        "https://app.tapped.ai/",
        "https://app.tapped.ai/u",
        "https://app.tapped.ai/map",
        "https://app.tapped.ai/connect_payment",
        "https://app.tapped.ai/privacy",
        "https://app.tapped.ai/eula",
        "https://example.com/u/djnova",
        "mailto:hi@tapped.ai",
    ])
    func rejectsNonAppLinks(url: String) throws {
        #expect(DeepLink(url: try #require(URL(string: url))) == nil)
    }

    @Test func notificationPayloads() {
        #expect(NotificationPayload(userInfo: ["url": "https://app.tapped.ai/u/djnova"]).link == .profile(username: "djnova"))
        #expect(NotificationPayload(userInfo: ["bookingId": "booking-1"]).link == .booking(bookingId: "booking-1"))
        #expect(NotificationPayload(userInfo: ["opportunityId": "abc"]).link == .opportunity(opportunityId: "abc"))
        let external = NotificationPayload(userInfo: ["url": "https://blog.example.com/post"])
        #expect(external.link == nil)
        #expect(external.externalURL?.host == "blog.example.com")
        #expect(NotificationPayload(userInfo: ["aps": ["alert": "hi"]]) == NotificationPayload())
    }

    @Test func inboundLinksBufferUntilTaken() throws {
        var opened: [URL] = []
        let inbound = InboundLinks { opened.append($0) }
        #expect(inbound.open(try #require(URL(string: "https://app.tapped.ai/settings"))))
        #expect(!inbound.open(try #require(URL(string: "https://example.com/settings"))))
        #expect(inbound.pending == .settings)

        inbound.receive(NotificationPayload(userInfo: ["url": "https://blog.example.com/post"]))
        #expect(opened.map(\.host) == ["blog.example.com"])
        #expect(inbound.take() == .settings)
        #expect(inbound.pending == nil)
    }

    @Test func resolvesRoutes() async throws {
        let database = MockDatabaseRepository()
        let resolver = DeepLinkResolver(database: database)
        let me = Samples.performer

        let profile = await resolver.resolve(.profile(username: "djnova"), currentUser: me)
        #expect(profile.route == .profile(userId: me.id, user: me))

        let missing = await resolver.resolve(.profile(username: "nobody-here"), currentUser: me)
        #expect(missing.route == nil)

        let booking = await resolver.resolve(.booking(bookingId: "booking-1"), currentUser: me)
        #expect(booking.route == .booking(try #require(Samples.bookings.first { $0.id == "booking-1" })))

        let opportunity = await resolver.resolve(.opportunity(opportunityId: "op-friday-openers"), currentUser: me)
        guard case let .opportunity(id, loaded) = opportunity.route else {
            Issue.record("expected opportunity route")
            return
        }
        #expect(id == "op-friday-openers")
        #expect(loaded?.id == "op-friday-openers")
    }

    @Test func stripeConnectReturnSavesAccountAndOpensSettings() async throws {
        let database = MockDatabaseRepository()
        let resolution = await DeepLinkResolver(database: database).resolve(.connectPayment(accountId: "acct_123"), currentUser: Samples.performer)
        #expect(resolution.route == .settings)
        #expect(resolution.updatedUser?.stripeConnectedAccountId == "acct_123")
        #expect(try await database.getUserById(Samples.performer.id)?.stripeConnectedAccountId == "acct_123")
    }
}
