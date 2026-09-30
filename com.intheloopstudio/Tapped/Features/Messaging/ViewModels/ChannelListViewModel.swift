import Foundation
import Observation
import TappedData
import TappedDomain

/// `lib/ui/messaging/channel_list_view.dart`: conversations the current user is a member of.
@Observable
@MainActor
final class ChannelListViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed
    }

    private(set) var phase: Phase = .loading
    private(set) var conversations: [Conversation] = []
    /// Changing this restarts `observe()` via `.task(id:)`.
    private(set) var attempt = 0

    private let chat: any ChatRepository

    init(dependencies: Dependencies) {
        chat = dependencies.chat
    }

    func observe() async {
        phase = conversations.isEmpty ? .loading : phase
        do {
            for try await conversations in chat.conversationsObserver() {
                self.conversations = conversations
                phase = .loaded
            }
        } catch is CancellationError {
        } catch {
            FirebaseBootstrap.record(error: error)
            phase = .failed
        }
    }

    func retry() {
        phase = .loading
        attempt += 1
    }
}
