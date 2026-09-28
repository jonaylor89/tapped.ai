import Foundation
import Observation
import TappedData
import TappedDomain

/// Signed-in shell state shared by the top chrome (profile avatar, messages + activity badges).
@Observable
@MainActor
final class ShellViewModel {
    let currentUser: UserModel
    /// TODO(session-6): drive from Stream Chat `totalUnreadCount`.
    private(set) var unreadMessages = 0
    /// Unread `activities` for the current user; driven by `observeActivities(database:)`.
    private(set) var unreadActivities = 0

    init(currentUser: UserModel) {
        self.currentUser = currentUser
    }

    /// Keeps `unreadActivities` in sync with the activity listener until the calling task is cancelled.
    func observeActivities(database: any DatabaseRepository) async {
        do {
            for try await activities in database.activitiesObserver(currentUser.id, limit: 100) {
                unreadActivities = activities.count { !$0.common.markedRead }
            }
        } catch {
            unreadActivities = 0
        }
    }
}
