import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Signed-in shell: the full-bleed Discover map is the permanent background and a persistent, non-dismissable
/// sheet holds the five tabs, each with its own `NavigationStack` (`ShellNavigator`).
struct ShellView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dependencies) private var dependencies
    @Environment(InboundLinks.self) private var inbound: InboundLinks?
    @Environment(\.scenePhase) private var scenePhase
    @State private var shell: ShellViewModel
    @State private var navigator: ShellNavigator
    @State private var discover: DiscoverViewModel
    @State private var showsReauthentication = false
    @State private var headerHeight: CGFloat = 0
    @State private var containerHeight: CGFloat = 0
    /// Room for the sheet's tab bar below the Gigs header.
    @ScaledMetric(relativeTo: .caption2) private var tabBarHeight: CGFloat = 58

    init(
        currentUser: UserModel,
        dependencies: Dependencies,
        isPremium: Bool,
        claims: [CustomClaim],
        launchOptions: LaunchOptions = .none
    ) {
        let now: () -> Date = dependencies.mode == .mock ? { Samples.referenceDate } : { .now }
        _shell = State(initialValue: ShellViewModel(currentUser: currentUser, chat: dependencies.chat, now: now))
        _navigator = State(initialValue: ShellNavigator(
            currentUserId: currentUser.id,
            tab: launchOptions.tab ?? .gigs,
            detent: launchOptions.detent
        ))
        _discover = State(initialValue: DiscoverViewModel(
            dependencies: dependencies,
            currentUser: currentUser,
            isPremium: isPremium,
            claims: claims,
            now: now
        ))
    }

    /// Measured Gigs header + tab bar, so the collapsed sheet shows exactly the "is there work for me?" lines.
    private var collapsedHeight: CGFloat {
        guard headerHeight > 0 else { return MapsSheetDetent.defaultCollapsedHeight }
        let height = headerHeight + min(tabBarHeight, 72)
        // Stay below `.medium` so the three detents keep their order at accessibility sizes.
        let cap = containerHeight > 0 ? containerHeight * 0.42 : height
        return min(height, cap).rounded()
    }

    var body: some View {
        DiscoverView(model: discover, collapsedHeight: collapsedHeight, open: navigator.open)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { containerHeight = $0 }
            .mapsStyleSheet(
                isPresented: Binding(get: { scenePhase != .background }, set: { _ in }),
                detent: Binding(get: { navigator.detent }, set: { navigator.setDetent($0) }),
                collapsedHeight: collapsedHeight,
                progress: $discover.sheetProgress,
                sheetTop: $discover.sheetTop
            ) {
                ShellTabsView(navigator: navigator, discover: discover, onHeaderHeight: { headerHeight = $0 })
                    .environment(shell)
                    .reauthenticationSheet(isPresented: $showsReauthentication, reason: "enter your password to continue") {}
            }
            .environment(shell)
            .onChange(of: session.isPremium) { _, isPremium in discover.isPremium = isPremium }
            .task { await shell.run() }
            .task { await shell.observeActivities(database: dependencies.database) }
            .task { await shell.observePendingRequests(database: dependencies.database) }
            .task { await applyLaunchOptions() }
            .task(id: inbound?.pending) { await openPendingLink() }
    }

    private func applyLaunchOptions() async {
        let options = session.launchOptions
        if let name = options.route, let path = Route.mockLaunchPath(name, currentUser: shell.currentUser) {
            navigator.open(path: path)
            if let detent = options.detent { navigator.setDetent(detent) }
        }
        if options.sheet == .reauth { showsReauthentication = true }
    }

    /// Universal links / notification taps buffered by `InboundLinks` (cold start included).
    private func openPendingLink() async {
        guard let link = inbound?.take() else { return }
        let resolution = await DeepLinkResolver(database: dependencies.database).resolve(link, currentUser: shell.currentUser)
        if let user = resolution.updatedUser {
            shell.update(user)
            session.updateCurrentUser(user)
        }
        if let route = resolution.route { navigator.open(route) }
    }
}

#Preview {
    let dependencies = Dependencies.mock(signedIn: true)
    ShellView(currentUser: .previewPerformer, dependencies: dependencies, isPremium: false, claims: [])
        .environment(\.dependencies, dependencies)
        .environment(AppSession(dependencies: dependencies))
}

extension UserModel {
    static let previewPerformer = Samples.performer
}
