import Foundation
import Observation
import TappedData
import TappedDomain

/// Signed-in shell state shared by the top chrome (profile avatar, messages + activity badges).
@Observable
@MainActor
final class ShellViewModel {
    private(set) var currentUser: UserModel
    /// Total unread messages from `ChatRepository.unreadCountUpdates()`.
    private(set) var unreadMessages = 0
    /// Unread `activities` for the current user; driven by `observeActivities(database:)`.
    private(set) var unreadActivities = 0
    private(set) var isChatConnected = false

    private let chat: (any ChatRepository)?

    init(currentUser: UserModel, chat: (any ChatRepository)? = nil) {
        self.currentUser = currentUser
        self.chat = chat
    }

    /// Connects chat for the signed-in user and keeps `unreadMessages` current. Runs for the shell's lifetime.
    func run() async {
        guard let chat else { return }
        do {
            try await chat.connectUser(currentUser)
            isChatConnected = true
        } catch {
            FirebaseBootstrap.record(error: error)
            return
        }
        for await count in chat.unreadCountUpdates() {
            unreadMessages = count
        }
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

    func update(_ user: UserModel) {
        guard user.id == currentUser.id else { return }
        currentUser = user
    }
}
