import Foundation
import Observation
import TappedData
import TappedDomain

/// Signed-in shell state shared by the top chrome (profile avatar, messages badge).
@Observable
@MainActor
final class ShellViewModel {
    let currentUser: UserModel
    /// Total unread messages from `ChatRepository.unreadCountUpdates()`.
    private(set) var unreadMessages = 0
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
}
