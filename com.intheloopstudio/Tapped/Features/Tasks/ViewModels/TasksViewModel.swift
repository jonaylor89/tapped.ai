import Foundation
import Observation
import TappedData
import TappedDomain

/// One row of the "finish setting up" checklist (Dart `_Task`).
struct SetupTask: Identifiable, Equatable {
    let title: String
    let description: String
    let systemImage: String
    let isCompleted: Bool
    let route: Route

    var id: String { title }
}

/// Port of `lib/ui/tasks/tasks_view.dart`.
@Observable
@MainActor
final class TasksViewModel {
    private(set) var currentUser: UserModel
    private(set) var hasBookings = false
    private(set) var contactedVenuesCount = 0
    private(set) var isLoading = true

    private let database: any DatabaseRepository

    init(dependencies: Dependencies, currentUser: UserModel) {
        self.currentUser = currentUser
        database = dependencies.database
    }

    var tasks: [SetupTask] {
        Self.tasks(for: currentUser, hasBookings: hasBookings, contactedVenuesCount: contactedVenuesCount)
    }

    var completedCount: Int { tasks.count(where: \.isCompleted) }

    var progress: Double { tasks.isEmpty ? 1 : Double(completedCount) / Double(tasks.count) }

    var summary: String {
        let remaining = tasks.count - completedCount
        return remaining == 0 ? "you're all set" : "\(remaining) \(remaining == 1 ? "task" : "tasks") left to get booked"
    }

    func load() async {
        defer { isLoading = false }
        if let user = try? await database.getUserById(currentUser.id) { currentUser = user }
        async let requestee = try? database.getBookingsByRequestee(currentUser.id, limit: 1, lastBookingRequestId: nil, status: .confirmed)
        async let requester = try? database.getBookingsByRequester(currentUser.id, limit: 1, lastBookingRequestId: nil, status: .confirmed)
        async let contacted = try? database.getContactedVenues(currentUser.id)
        hasBookings = !((await requestee ?? []) + (await requester ?? [])).isEmpty
        contactedVenuesCount = await contacted?.count ?? 0
    }

    /// Same five criteria (and order) as the Dart checklist.
    static func tasks(for user: UserModel, hasBookings: Bool, contactedVenuesCount: Int) -> [SetupTask] {
        [
            SetupTask(
                title: "add a profile picture",
                description: "add a profile picture to your account",
                systemImage: "person.crop.circle",
                isCompleted: !(user.profilePicture ?? "").isEmpty,
                route: .settings
            ),
            SetupTask(
                title: "add genres",
                description: "add what genres you perform",
                systemImage: "music.note.list",
                isCompleted: !(user.performerInfo?.genres.isEmpty ?? true),
                route: .settings
            ),
            SetupTask(
                title: "add social following",
                description: "let promoters know how big your online presence is",
                systemImage: "person.3",
                isCompleted: user.socialFollowing.audienceSize > 0 || hasSocialHandle(user.socialFollowing),
                route: .settings
            ),
            SetupTask(
                title: "add booking history",
                description: "your past gigs are probably the most important part of your profile",
                systemImage: "calendar",
                isCompleted: hasBookings,
                route: .addPastBooking
            ),
            SetupTask(
                title: "contact your first venue",
                description: "contact venues to get your first gig on tapped!",
                systemImage: "paperplane",
                isCompleted: contactedVenuesCount > 0,
                route: .gigSearch
            ),
        ]
    }

    /// Onboarding and the checklist only ask for handles, so a handle alone completes "add social following".
    private static func hasSocialHandle(_ social: SocialFollowing) -> Bool {
        [social.instagramHandle, social.tiktokHandle, social.twitterHandle, social.facebookHandle, social.soundcloudHandle]
            .contains { !($0 ?? "").isEmpty }
    }
}
