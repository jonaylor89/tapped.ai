import Foundation
import Observation
import TappedData
import TappedDomain

/// Signed-in shell state behind the tab badges (bookings, messages, profile activity).
@Observable
@MainActor
final class ShellViewModel {
    private(set) var currentUser: UserModel
    /// Total unread messages from `ChatRepository.unreadCountUpdates()`.
    private(set) var unreadMessages = 0
    /// Unread `activities` for the current user; driven by `observeActivities(database:)`.
    private(set) var unreadActivities = 0
    /// Pending, unexpired booking requests waiting on the current user (they are the requestee).
    private(set) var pendingRequests = 0
    private(set) var isChatConnected = false

    private let chat: (any ChatRepository)?
    private let now: () -> Date

    init(currentUser: UserModel, chat: (any ChatRepository)? = nil, now: @escaping () -> Date = { .now }) {
        self.currentUser = currentUser
        self.chat = chat
        self.now = now
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

    /// Keeps `pendingRequests` in sync with the requestee bookings listener until the calling task is cancelled.
    func observePendingRequests(database: any DatabaseRepository) async {
        do {
            for try await bookings in database.getBookingsByRequesteeObserver(currentUser.id, limit: 100, status: .pending) {
                let now = now()
                pendingRequests = bookings.count { $0.isPending && !$0.isExpired(now: now) }
            }
        } catch {
            pendingRequests = 0
        }
    }

    func update(_ user: UserModel) {
        guard user.id == currentUser.id else { return }
        currentUser = user
    }
}
