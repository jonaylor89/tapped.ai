import Foundation
import TappedData
import TappedDomain
import TappedUI
import Testing
@testable import Tapped

@MainActor
@Suite("ShellNavigator")
struct ShellNavigatorTests {
    let me = Samples.performer
    let venue = Samples.venues[0]
    let opportunity = Samples.opportunities[0]

    func makeNavigator(tab: ShellTab = .gigs, detent: MapsSheetDetent? = nil) -> ShellNavigator {
        ShellNavigator(currentUserId: me.id, tab: tab, detent: detent)
    }

    @Test func destinationsFollowTheTabMap() {
        func destination(_ route: Route) -> ShellNavigator.Destination? {
            ShellNavigator.destination(for: route, currentUserId: me.id)
        }
        let gigsMedium = ShellNavigator.Destination(tab: .gigs, detent: .medium)
        let large = { (tab: ShellTab) in ShellNavigator.Destination(tab: tab, detent: .large) }

        #expect(destination(.opportunity(opportunityId: opportunity.id, opportunity: opportunity)) == gigsMedium)
        #expect(destination(.opportunities(Samples.opportunities)) == gigsMedium)
        #expect(destination(.interestedUsers(opportunity)) == gigsMedium)
        #expect(destination(.profile(userId: venue.id, user: venue)) == gigsMedium)
        #expect(destination(.reviews(userId: venue.id)) == gigsMedium)

        #expect(destination(.bookings(userId: me.id)) == large(.bookings))
        #expect(destination(.booking(Samples.bookings[0])) == large(.bookings))
        #expect(destination(.requestToPerform(venues: [venue], collaborators: [])) == large(.bookings))
        #expect(destination(.requestToPerformConfirmation(venues: [venue])) == large(.bookings))
        #expect(destination(.bookingHistory(me)) == large(.bookings))
        #expect(destination(.addPastBooking) == large(.bookings))
        #expect(destination(.createBooking(requesteeId: venue.id, service: nil, requesteeStripeConnectedAccountId: nil)) == large(.bookings))

        #expect(destination(.messagingChannelList) == large(.messages))
        #expect(destination(.streamChannel(channelId: "c")) == large(.messages))

        #expect(destination(.profile(userId: me.id, user: me)) == large(.profile))
        #expect(destination(.reviews(userId: me.id)) == large(.profile))
        #expect(destination(.settings) == large(.profile))
        #expect(destination(.activities) == large(.profile))
        #expect(destination(.tasks) == large(.profile))

        #expect(destination(.search) == large(.search))
        #expect(destination(.advancedSearch) == large(.search))
        #expect(destination(.gigSearch) == large(.search))
        #expect(destination(.opportunityFeed) == large(.search))

        #expect(destination(.paywall) == nil)
    }

    @Test func openSelectsTabResetsItsStackAndSizesTheSheet() {
        let navigator = makeNavigator()
        navigator.bookings.push(.addPastBooking)
        let booking = Samples.bookings[0]
        navigator.open(.booking(booking))
        #expect(navigator.tab == .bookings)
        #expect(navigator.detent == .large)
        #expect(navigator.bookings.path == [.booking(booking)])
        #expect(navigator.gigs.isAtRoot)
    }

    @Test func tabRootsAreNotPushedAgain() {
        let navigator = makeNavigator()
        navigator.open(.messagingChannelList)
        #expect(navigator.tab == .messages)
        #expect(navigator.messages.isAtRoot)
        navigator.open(path: [.messagingChannelList, .streamChannel(channelId: "c")])
        #expect(navigator.messages.path == [.streamChannel(channelId: "c")])
        navigator.open(.profile(userId: me.id, user: me))
        #expect(navigator.tab == .profile)
        #expect(navigator.profile.isAtRoot)
        navigator.open(.bookings(userId: me.id))
        #expect(navigator.bookings.isAtRoot)
    }

    @Test func mapPinsOpenInGigsAtLeastMedium() {
        let navigator = makeNavigator()
        navigator.open(.profile(userId: venue.id, user: venue))
        #expect(navigator.tab == .gigs)
        #expect(navigator.detent == .medium)
        #expect(navigator.gigs.path == [.profile(userId: venue.id, user: venue)])

        navigator.setDetent(.large)
        navigator.open(.opportunity(opportunityId: opportunity.id, opportunity: opportunity))
        #expect(navigator.detent == .large)
    }

    @Test func gigsRemembersItsDetentOtherTabsSnapLarge() {
        let navigator = makeNavigator()
        #expect(navigator.detent == .collapsed)
        navigator.setDetent(.medium)
        navigator.select(.messages)
        #expect(navigator.detent == .large)
        navigator.setDetent(.medium)
        navigator.select(.gigs)
        #expect(navigator.detent == .medium)
        #expect(navigator.gigsDetent == .medium)
    }

    @Test func pushingInsideGigsRaisesToMedium() {
        let navigator = makeNavigator()
        navigator.gigsPathDidChange(from: 0, to: 1)
        #expect(navigator.detent == .medium)
        navigator.setDetent(.large)
        navigator.gigsPathDidChange(from: 1, to: 2)
        #expect(navigator.detent == .large)
    }

    @Test func discoveryReturnsToCollapsedGigsRoot() {
        let navigator = makeNavigator()
        navigator.open(.opportunity(opportunityId: opportunity.id, opportunity: opportunity))
        navigator.select(.bookings)
        navigator.bookings.push(.discovery)
        #expect(navigator.tab == .gigs)
        #expect(navigator.detent == .collapsed)
        #expect(navigator.gigs.isAtRoot)
    }

    @Test func takeoversStayOnTheCurrentTab() {
        let navigator = makeNavigator(tab: .bookings)
        navigator.open(.paywall)
        #expect(navigator.tab == .bookings)
        #expect(navigator.bookings.sheet == .paywall)
        navigator.open(.videoCall)
        #expect(navigator.tab == .messages)
        #expect(navigator.messages.fullScreenCover == .videoCall)
    }

    @Test func initialTabFromLaunchOptions() {
        let navigator = makeNavigator(tab: .search)
        #expect(navigator.tab == .search)
        #expect(navigator.detent == .large)
        #expect(navigator.gigsDetent == .collapsed)
        #expect(makeNavigator(detent: .medium).detent == .medium)
    }

    @Test(arguments: ["bookings", "messages", "channel", "settings", "search", "gig-search", "opportunity", "profile:venue-canal"])
    func mockLaunchRoutesLandOnTheirTab(name: String) throws {
        let path = try #require(Route.mockLaunchPath(name, currentUser: me))
        let navigator = makeNavigator()
        navigator.open(path: path)
        let expected = try #require(ShellNavigator.destination(for: path[0], currentUserId: me.id))
        #expect(navigator.tab == expected.tab)
    }

    @Test func pendingRequestsCountsUnexpiredRequestsWaitingOnMe() async throws {
        let now = Samples.referenceDate
        let shell = ShellViewModel(currentUser: me, now: { now })
        let expected = Samples.bookings.count { $0.requesteeId == me.id && $0.isPending && !$0.isExpired(now: now) }
        #expect(expected > 0)
        let database = MockDatabaseRepository()
        let observer = Task { await shell.observePendingRequests(database: database) }
        defer { observer.cancel() }
        for _ in 0..<200 where shell.pendingRequests != expected { try await Task.sleep(for: .milliseconds(10)) }
        #expect(shell.pendingRequests == expected)
    }
}

@MainActor
@Suite("NotificationsPrompt")
struct NotificationsPromptTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "tapped.tests.\(UUID().uuidString)")!
    }

    private func model(
        _ context: NotificationsPromptModel.Context,
        notifications: MockNotificationRepository,
        defaults: UserDefaults
    ) -> NotificationsPromptModel {
        NotificationsPromptModel(
            context: context,
            dependencies: .mock(signedIn: true, notifications: notifications),
            userId: Samples.performer.id,
            venueName: "The Camel",
            defaults: defaults
        )
    }

    @Test func showsForProvisionalAndNamesTheVenue() async {
        let notifications = MockNotificationRepository(status: .provisional)
        let prompt = model(.application, notifications: notifications, defaults: defaults())
        await prompt.load()
        #expect(prompt.isVisible)
        #expect(prompt.message == "know the moment The Camel replies — only bookings, replies and gigs that match your genres")
    }

    @Test func turnOnIsTheOnlyPathToTheSystemPrompt() async {
        let notifications = MockNotificationRepository(status: .provisional)
        let prompt = model(.requestToPerform, notifications: notifications, defaults: defaults())
        await prompt.load()
        #expect(await notifications.authorizationRequests == 0)
        await prompt.turnOn()
        #expect(!prompt.isVisible)
        #expect(await notifications.authorizationRequests == 1)
        #expect(await notifications.savedTokens[Samples.performer.id] != nil)
    }

    @Test func notNowIsRememberedPerConfirmationType() async {
        let store = defaults()
        let notifications = MockNotificationRepository()
        let first = model(.application, notifications: notifications, defaults: store)
        await first.load()
        first.notNow()
        #expect(!first.isVisible)

        let again = model(.application, notifications: notifications, defaults: store)
        await again.load()
        #expect(!again.isVisible)

        let other = model(.requestToPerform, notifications: notifications, defaults: store)
        await other.load()
        #expect(other.isVisible)
    }

    @Test(arguments: [NotificationAuthorizationStatus.authorized, .denied])
    func hiddenOnceDecided(status: NotificationAuthorizationStatus) async {
        let prompt = model(.application, notifications: MockNotificationRepository(status: status), defaults: defaults())
        await prompt.load()
        #expect(!prompt.isVisible)
    }
}
