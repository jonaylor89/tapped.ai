import Foundation
import Observation
import TappedData
import TappedDomain

/// Signed-in shell state shared by the top chrome (profile avatar, messages badge).
@Observable
@MainActor
final class ShellViewModel {
    private(set) var currentUser: UserModel
    /// TODO(session-6): drive from Stream Chat `totalUnreadCount`.
    private(set) var unreadMessages = 0

    init(currentUser: UserModel) {
        self.currentUser = currentUser
    }

    func update(_ user: UserModel) {
        guard user.id == currentUser.id else { return }
        currentUser = user
    }
}
