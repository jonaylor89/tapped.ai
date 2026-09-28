import SwiftUI
import TappedData
import TappedDomain

/// Signed-in root. Mirrors Flutter: there is no tab bar — Discover is the shell, and profile/messages
/// are pushed from its top chrome.
struct ShellView: View {
    @Environment(Router.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(\.dependencies) private var dependencies
    @Environment(InboundLinks.self) private var inbound: InboundLinks?
    @State private var shell: ShellViewModel
    @State private var showsReauthentication = false

    init(currentUser: UserModel) {
        _shell = State(initialValue: ShellViewModel(currentUser: currentUser))
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
        .task { applyLaunchOptions() }
        .task(id: inbound?.pending) { await openPendingLink() }
        .reauthenticationSheet(isPresented: $showsReauthentication, reason: "enter your password to continue") {}
    }

    private func applyLaunchOptions() {
        if let route = session.launchOptions.route { router.push(route) }
        showsReauthentication = session.launchOptions.sheet == .reauth
    }

    /// Universal links / notification taps buffered by `InboundLinks` (cold start included).
    private func openPendingLink() async {
        guard let link = inbound?.take() else { return }
        let resolution = await DeepLinkResolver(database: dependencies.database).resolve(link, currentUser: shell.currentUser)
        if let user = resolution.updatedUser {
            shell.update(user)
            session.updateCurrentUser(user)
        }
        if let route = resolution.route { router.push(route) }
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
