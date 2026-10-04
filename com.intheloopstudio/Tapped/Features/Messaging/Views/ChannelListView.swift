import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// `ChannelListView`: conversations, most recent first, under the system glass nav bar.
struct ChannelListView: View {
    @State private var model: ChannelListViewModel
    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    init(dependencies: Dependencies) {
        _model = State(initialValue: ChannelListViewModel(dependencies: dependencies))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                LoadingView()
            case .failed:
                ErrorView(ErrorCopy.load("your messages")) { model.retry() }
            case .loaded where model.conversations.isEmpty:
                GlassEmptyState(
                    "no conversations yet",
                    message: "start talking to venues and get the conversation started",
                    systemImage: "bubble.left.and.bubble.right"
                ) {
                    if !session.isPremium {
                        GlassCapsuleButton("upgrade to message", systemImage: "crown.fill", style: .accent) {
                            router.push(.paywall)
                        }
                    }
                }
                .padding(GlassMetrics.edgeInset)
            case .loaded:
                List(model.conversations) { conversation in
                    NavigationLink(value: Route.streamChannel(channelId: conversation.id)) {
                        ConversationRow(conversation: conversation)
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TappedColors.background.ignoresSafeArea())
        .navigationTitle(Route.messagingChannelList.title)
        .toolbarTitleDisplayMode(.inlineLarge)
        .animation(GlassMotion.ease, value: model.phase)
        .task(id: model.attempt) { await model.observe() }
    }
}

#Preview("conversations") {
    let dependencies = Dependencies.mock(signedIn: true)
    NavigationStack {
        ChannelListView(dependencies: dependencies)
            .tappedRouteDestinations()
    }
    .environment(\.dependencies, dependencies)
    .environment(AppSession(dependencies: dependencies))
    .environment(Router())
}

#Preview("empty") {
    var dependencies = Dependencies.mock(signedIn: true)
    dependencies.chat = MockChatRepository(conversations: [], messages: [:])
    return NavigationStack {
        ChannelListView(dependencies: dependencies)
    }
    .environment(\.dependencies, dependencies)
    .environment(AppSession(dependencies: dependencies))
    .environment(Router())
}
