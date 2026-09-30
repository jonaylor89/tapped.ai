import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// `MessageButton` (profile): opens — or creates — the 1:1 conversation with `userId`.
struct MessageUserButton: View {
    let userId: String

    @Environment(\.dependencies) private var dependencies
    @Environment(Router.self) private var router
    @State private var isLoading = false
    @State private var failed = false

    var body: some View {
        GlassCapsuleButton(isLoading ? "opening…" : "message", systemImage: "bubble.left.fill") {
            Task { await open() }
        }
        .disabled(isLoading)
        .accessibilityHint("opens a direct message")
        .sensoryFeedback(.error, trigger: failed)
        .alert("couldn't start a conversation", isPresented: $failed) {
            Button("okay", role: .cancel) {}
        }
    }

    private func open() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let conversationId = try await dependencies.chat.createDirectConversation(with: userId)
            router.push(.streamChannel(channelId: conversationId))
        } catch {
            FirebaseBootstrap.record(error: error)
            failed = true
        }
    }
}

#Preview {
    MessageUserButton(userId: Samples.venues[0].id)
        .padding()
        .background(PreviewBackdrop())
        .environment(\.dependencies, .mock(signedIn: true))
        .environment(Router())
}
