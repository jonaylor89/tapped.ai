import Foundation
import Observation
import TappedData
import TappedDomain

/// Port of `ActivityBloc` (paginated list + mark read).
@Observable
@MainActor
final class ActivityViewModel {
    static let pageSize = 20

    let currentUser: UserModel
    private(set) var activities: [Activity] = []
    private(set) var users: [String: UserModel] = [:]
    private(set) var hasReachedMax = false
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?

    private let database: any DatabaseRepository

    init(dependencies: Dependencies, currentUser: UserModel) {
        self.currentUser = currentUser
        database = dependencies.database
    }

    var hasUnread: Bool { activities.contains { !$0.common.markedRead } }

    /// First page (initial load + pull-to-refresh).
    func refresh() async {
        isLoading = activities.isEmpty
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await database.getActivities(currentUser.id, limit: Self.pageSize, lastActivityId: nil)
            activities = page
            hasReachedMax = page.count < Self.pageSize
            await resolveUsers(for: page)
        } catch {
            errorMessage = "couldn't load activity"
        }
    }

    /// Dart `FetchActivitiesEvent` — next page after the last loaded activity.
    func loadMore() async {
        guard !hasReachedMax, !isLoadingMore, let last = activities.last else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await database.getActivities(currentUser.id, limit: Self.pageSize, lastActivityId: last.id)
            let known = Set(activities.map(\.id))
            activities += page.filter { !known.contains($0.id) }
            hasReachedMax = page.count < Self.pageSize
            await resolveUsers(for: page)
        } catch {
            hasReachedMax = true
        }
    }

    func markRead(_ activity: Activity) async {
        guard !activity.common.markedRead, let index = activities.firstIndex(where: { $0.id == activity.id }) else { return }
        activities[index] = activity.copyAsRead()
        try? await database.markActivityAsRead(activity)
    }

    /// Dart `MarkAllAsReadEvent`.
    func markAllRead() async {
        let unread = activities.filter { !$0.common.markedRead }
        activities = activities.map { $0.common.markedRead ? $0 : $0.copyAsRead() }
        await withTaskGroup(of: Void.self) { group in
            for activity in unread {
                group.addTask { [database] in try? await database.markActivityAsRead(activity) }
            }
        }
    }

    /// Marks the row read and returns where tapping it should navigate.
    func open(_ activity: Activity) async -> Route? {
        await markRead(activity)
        switch activity {
        case let .follow(follow):
            return .profile(userId: follow.fromUserId, user: users[follow.fromUserId])
        case let .bookingRequest(request):
            return await bookingRoute(request.bookingId)
        case let .bookingUpdate(update):
            return await bookingRoute(update.bookingId)
        case let .bookingReminder(reminder):
            return await bookingRoute(reminder.bookingId)
        case .searchAppearance:
            return .profile(userId: currentUser.id, user: currentUser)
        }
    }

    func fromUser(for activity: Activity) -> UserModel? {
        activity.fromUserId.flatMap { users[$0] }
    }

    private func bookingRoute(_ bookingId: String) async -> Route? {
        guard let booking = try? await database.getBookingById(bookingId) else { return nil }
        return .booking(booking)
    }

    private func resolveUsers(for page: [Activity]) async {
        let ids = Set(page.compactMap(\.fromUserId)).subtracting(users.keys)
        await withTaskGroup(of: UserModel?.self) { group in
            for id in ids {
                group.addTask { [database] in try? await database.getUserById(id) }
            }
            for await user in group {
                if let user { users[user.id] = user }
            }
        }
    }
}

extension Activity {
    var fromUserId: String? {
        switch self {
        case let .follow(value): value.fromUserId
        case let .bookingRequest(value): value.fromUserId
        case let .bookingUpdate(value): value.fromUserId
        case let .bookingReminder(value): value.fromUserId
        case .searchAppearance: nil
        }
    }

    /// Dart `ActivityTile` copy.
    var message: String {
        switch self {
        case .follow: "followed you 🤝"
        case .bookingRequest: "sent you a booking request 📩"
        case .bookingUpdate: "updated your booking 📩"
        case .bookingReminder: "sent you a booking reminder 📩"
        case let .searchAppearance(value): "you've appeared in \(value.count) searches recently"
        }
    }

    var systemImage: String {
        switch self {
        case .follow: "person.fill.badge.plus"
        case .bookingRequest: "calendar.badge.plus"
        case .bookingUpdate: "calendar.badge.checkmark"
        case .bookingReminder: "bell.badge.fill"
        case .searchAppearance: "magnifyingglass"
        }
    }
}
