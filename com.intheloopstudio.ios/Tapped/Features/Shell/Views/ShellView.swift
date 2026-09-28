import SwiftUI
import TappedData
import TappedDomain

/// Signed-in root. Mirrors Flutter: there is no tab bar — Discover is the shell, and profile/messages
/// are pushed from its top chrome.
struct ShellView: View {
    @Environment(Router.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(\.dependencies) private var dependencies
    @State private var shell: ShellViewModel

    init(currentUser: UserModel, chat: (any ChatRepository)? = nil) {
        _shell = State(initialValue: ShellViewModel(currentUser: currentUser, chat: chat))
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            DiscoverView(
                dependencies: dependencies,
                currentUser: shell.currentUser,
                isPremium: session.isPremium,
                claims: session.claims,
                initialDetent: session.launchOptions.detent
            )
            .tappedRouteDestinations()
        }
        .environment(shell)
        .task { await shell.run() }
        .task {
            if let route = session.launchOptions.initialRoute, router.isAtRoot { router.push(route) }
        }
    }
}

#Preview {
    let dependencies = Dependencies.mock(signedIn: true)
    ShellView(currentUser: .previewPerformer)
        .environment(\.dependencies, dependencies)
        .environment(AppSession(dependencies: dependencies))
        .environment(Router())
}

extension UserModel {
    static let previewPerformer = Samples.performer
}
