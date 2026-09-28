import Foundation
import TappedData
import TappedDomain
import Testing
import UIKit
@testable import Tapped

@MainActor
@Suite("ProfileViewModel")
struct ProfileViewModelTests {
    @Test func ownProfileLoadsServicesBookingsAndLatestReview() async {
        let model = ProfileViewModel(dependencies: .mock(signedIn: true), currentUser: Samples.performer, userId: Samples.performer.id)
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.isCurrentUser)
        #expect(model.services.map(\.id) == ["service-nova-hourly", "service-nova-set"])
        #expect(model.latestBookings.map(\.id) == ["booking-1", "booking-3", "booking-4"])
        #expect(model.counterpartName(for: model.latestBookings[0]) == "The Camel")
        #expect(model.latestReview?.id == "review-nova-camel")
        #expect(model.latestReviewer?.id == "venue-camel")
        #expect(model.placeName == "Richmond, VA, USA")
        #expect(model.showAudience)
        #expect(!model.canMessage && !model.canRequestToPerform && !model.canRequestToBook)
        #expect(model.infoRows.map(\.title).starts(with: ["location", "genres"]))
        #expect(model.socials.map(\.name) == ["instagram"])
    }

    @Test func otherUserActionsAndBlocking() async throws {
        let dependencies = Dependencies.mock(signedIn: true)
        let venue = Samples.venues[0]
        let model = ProfileViewModel(dependencies: dependencies, currentUser: Samples.performer, userId: venue.id)
        await model.load()
        #expect(!model.isCurrentUser)
        #expect(model.canMessage)
        #expect(model.canRequestToPerform)
        #expect(!model.canRequestToBook)

        await model.block()
        #expect(model.isBlocked)
        #expect(model.toast == "user blocked")
        #expect(try await dependencies.database.isBlocked(currentUserId: Samples.performer.id, blockedUserId: venue.id))
        await model.unblock()
        #expect(!model.isBlocked)

        await model.report()
        #expect(model.toast == "user reported")
    }

    @Test func missingUserFails() async {
        let model = ProfileViewModel(dependencies: .mock(signedIn: true), currentUser: Samples.performer, userId: "nope")
        await model.load()
        #expect(model.phase == .failed("this profile doesn't exist"))
    }

    @Test func profileLinkMatchesDart() {
        #expect(Samples.performer.profileURL.absoluteString == "https://app.tapped.ai/u/djnova")
    }

    @Test func formatting() {
        #expect(ProfileViewModel.spaced("concertHall") == "concert hall")
        #expect(ProfileViewModel.genreNames([Genre.dance.rawValue, "custom"]) == "dance, custom")
        #expect(ProfileViewModel.compact(22_500) == "22.5k")
    }
}

@MainActor
@Suite("SettingsViewModel")
struct SettingsViewModelTests {
    @Test func savesEditsAndUploadsPhoto() async throws {
        let dependencies = Dependencies.mock(signedIn: true)
        let model = SettingsViewModel(dependencies: dependencies, currentUser: Samples.performer)
        await model.load()
        #expect(model.services.count == 2)
        #expect(model.placeName == "Richmond, VA, USA")
        #expect(!model.hasChanges)

        model.username = "  DJNova2 "
        model.draft.bio = "new bio "
        model.selectedGenres = [.funk, .jazz]
        model.ticketPriceDollars = 25
        model.draft.pushNotifications.directMessages = false
        model.setPickedImage(try #require(Self.pngData()))
        #expect(model.hasChanges)

        let saved = try #require(await model.save())
        #expect(saved.username.username == "djnova2")
        #expect(saved.bio == "new bio")
        #expect(saved.performerInfo?.genres == [Genre.funk.rawValue, Genre.jazz.rawValue])
        #expect(saved.performerInfo?.averageTicketPrice == 2500)
        #expect(saved.profilePicture?.hasPrefix("file://") == true)
        let stored = try await dependencies.database.getUserById(Samples.performer.id)
        #expect(stored == saved)
        #expect(!model.hasChanges)
    }

    @Test func rejectsTakenAndInvalidUsernames() async {
        let model = SettingsViewModel(dependencies: .mock(signedIn: true), currentUser: Samples.performer)
        model.username = Samples.venues[0].username.username
        #expect(await model.save() == nil)
        #expect(model.errorMessage == "username already exists")

        model.username = "bad name!"
        #expect(await model.save() == nil)
        #expect(model.errorMessage == "usernames can only contain letters, numbers, . and _")

        model.username = ""
        #expect(await model.save() == nil)
        #expect(model.errorMessage == "username can't be empty")
    }

    @Test func togglingPerformerAndDeletingServices() async throws {
        let dependencies = Dependencies.mock(signedIn: true)
        let model = SettingsViewModel(dependencies: dependencies, currentUser: Samples.performer)
        await model.load()
        model.isPerformer = false
        #expect(model.draft.performerInfo == nil)
        model.isPerformer = true
        #expect(model.draft.performerInfo == Samples.performer.performerInfo)

        await model.deleteService(model.services[0])
        #expect(model.services.count == 1)
        #expect(try await dependencies.database.getUserServices(Samples.performer.id).count == 1)
    }

    @Test func deleteAccountSignsOut() async {
        let dependencies = Dependencies.mock(signedIn: true)
        let model = SettingsViewModel(dependencies: dependencies, currentUser: Samples.performer)
        #expect(await model.deleteAccount())
        #expect(await !dependencies.auth.isSignedIn())
    }

    static func pngData() -> Data? {
        UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1200)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200))
        }.pngData()
    }

    @Test func compressionCapsLongEdge() throws {
        let png = try #require(Self.pngData())
        let image = try #require(UIImage(data: png))
        let jpeg = try #require(SettingsViewModel.compressedJPEG(image))
        let decoded = try #require(UIImage(data: jpeg))
        #expect(max(decoded.size.width, decoded.size.height) == 1080)
    }
}

@MainActor
@Suite("TasksViewModel")
struct TasksViewModelTests {
    @Test func fiveDartCriteriaInOrder() async {
        let model = TasksViewModel(dependencies: .mock(signedIn: true), currentUser: Samples.performer)
        await model.load()
        #expect(model.tasks.map(\.title) == [
            "add a profile picture", "add genres", "add social following", "add booking history", "contact your first venue",
        ])
        #expect(model.tasks.map(\.isCompleted) == [false, true, true, true, false])
        #expect(model.tasks.map(\.route) == [.settings, .settings, .settings, .addPastBooking, .gigSearch])
        #expect(model.completedCount == 3)
        #expect(model.summary == "2 tasks left to get booked")
    }

    @Test func allDone() {
        var user = Samples.performer
        user.profilePicture = "https://example.com/me.jpg"
        let tasks = TasksViewModel.tasks(for: user, hasBookings: true, contactedVenuesCount: 2)
        #expect(tasks.allSatisfy { $0.isCompleted })
    }
}

@MainActor
@Suite("ActivityViewModel")
struct ActivityViewModelTests {
    @Test func paginatesAndResolvesUsers() async {
        let model = ActivityViewModel(dependencies: .mock(signedIn: true), currentUser: Samples.performer)
        await model.refresh()
        #expect(model.activities.count == ActivityViewModel.pageSize)
        #expect(!model.hasReachedMax)
        #expect(model.fromUser(for: model.activities[0])?.id == "venue-canal")
        #expect(model.activities[0].message == "sent you a booking request 📩")

        await model.loadMore()
        #expect(model.activities.count == Samples.activities.count)
        #expect(model.hasReachedMax)
        await model.loadMore()
        #expect(model.activities.count == Samples.activities.count)
    }

    @Test func markAllReadClearsShellBadge() async throws {
        let dependencies = Dependencies.mock(signedIn: true)
        let shell = ShellViewModel(currentUser: Samples.performer)
        let observer = Task { await shell.observeActivities(database: dependencies.database) }
        defer { observer.cancel() }
        try await Self.waitUntil { shell.unreadActivities == 3 }

        let model = ActivityViewModel(dependencies: dependencies, currentUser: Samples.performer)
        await model.refresh()
        #expect(model.hasUnread)
        await model.markAllRead()
        #expect(!model.hasUnread)
        try await Self.waitUntil { shell.unreadActivities == 0 }
    }

    @Test func openingRowsMarksReadAndRoutes() async {
        let model = ActivityViewModel(dependencies: .mock(signedIn: true), currentUser: Samples.performer)
        await model.refresh()
        let request = model.activities[0]
        let route = await model.open(request)
        #expect(route == .booking(Samples.profileBookings[0]))
        #expect(model.activities[0].common.markedRead)

        let follow = model.activities[1]
        guard case let .profile(userId, _) = await model.open(follow) else { Issue.record("expected profile"); return }
        #expect(userId == "performer-lowtide")
    }

    @Test func emptyForUsersWithoutActivity() async {
        let model = ActivityViewModel(dependencies: .mock(signedIn: true), currentUser: Samples.venues[0])
        await model.refresh()
        #expect(model.activities.isEmpty)
        #expect(model.hasReachedMax)
        #expect(model.errorMessage == nil)
    }

    static func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}

@Suite("Session 2 routes")
struct Session2RouteTests {
    @Test func mockLaunchRoutes() {
        let me = Samples.performer
        #expect(Route.mockLaunch("settings", currentUser: me) == .settings)
        #expect(Route.mockLaunch("activities", currentUser: me) == .activities)
        #expect(Route.mockLaunch("tasks", currentUser: me) == .tasks)
        #expect(Route.mockLaunch("shareProfile", currentUser: me) == .shareProfile(userId: me.id, user: me))
        #expect(Route.mockLaunch("profile", currentUser: me) == .profile(userId: me.id, user: me))
        #expect(Route.mockLaunch("profile:venue-camel", currentUser: me) == .profile(userId: "venue-camel", user: nil))
        #expect(Route.mockLaunch("nope", currentUser: me) == nil)
    }

    @Test func launchOptionsReadRoute() {
        #expect(LaunchOptions.from(["TAPPED_MOCK": "1", "TAPPED_MOCK_ROUTE": "settings"]).route == "settings")
        #expect(LaunchOptions.from(["TAPPED_MOCK_ROUTE": "settings"]).route == nil)
    }
}
