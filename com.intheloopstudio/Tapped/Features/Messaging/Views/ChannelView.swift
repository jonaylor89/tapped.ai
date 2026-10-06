import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// `StreamChannelPage`: message history + floating glass composer.
struct ChannelView: View {
    @State private var model: ChannelViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(dependencies: Dependencies, conversationId: String) {
        _model = State(initialValue: ChannelViewModel(dependencies: dependencies, conversationId: conversationId))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                LoadingView()
            case .failed:
                ErrorView(ErrorCopy.load("this conversation")) { model.retry() }
            case .loaded where model.messages.isEmpty:
                GlassEmptyState("say hi 👋", message: "send the first message", systemImage: "bubble.left")
                    .padding(GlassMetrics.edgeInset)
            case .loaded:
                messageList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TappedColors.background.ignoresSafeArea())
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let conversation = model.conversation {
                    HStack(spacing: TappedSpacing.sm) {
                        UserAvatar(url: conversation.imageURL, name: conversation.name, size: 28)
                        Text(conversation.name).font(TappedTypography.headingXs).lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.phase == .loaded {
                MessageComposer(text: $model.draft, canSend: model.canSend) {
                    Task { await model.send() }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.sentCount)
        .task(id: model.attempt) { await model.observe() }
        .task(id: scenePhase) { await model.setActive(scenePhase == .active) }
        .onDisappear { Task { await model.setActive(false) } }
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(spacing: TappedSpacing.sm) {
                Color.clear.frame(height: 1)
                    .onAppear { Task { await model.loadOlder() } }
                ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                    ChatBubble(
                        text: message.text,
                        authorName: message.authorName,
                        timestamp: message.createdAt,
                        isOutgoing: message.isFromCurrentUser,
                        status: message.status.bubbleStatus,
                        showsAuthor: model.showsAuthor(at: index),
                        showsTimestamp: model.showsTimestamp(at: index)
                    )
                    .id(message.id)
                }
            }
            .padding(.horizontal, GlassMetrics.edgeInset)
            .padding(.vertical, TappedSpacing.sm)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
    }
}

private extension ConversationMessage.Status {
    var bubbleStatus: ChatBubble.Status {
        switch self {
        case .sent: .sent
        case .sending: .sending
        case .failed: .failed
        }
    }
}

#Preview {
    let dependencies = Dependencies.mock(signedIn: true)
    NavigationStack {
        ChannelView(dependencies: dependencies, conversationId: Samples.conversations[0].id)
    }
    .task { try? await dependencies.chat.connectUser(Samples.performer) }
}
