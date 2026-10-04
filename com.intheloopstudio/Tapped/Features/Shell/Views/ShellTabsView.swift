import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// The `TabView` inside the persistent map sheet. Each tab's `Router` is injected into its own stack so
/// existing `router.push/pop` call sites work unchanged.
struct ShellTabsView: View {
    let navigator: ShellNavigator
    @Bindable var discover: DiscoverViewModel
    let onHeaderHeight: (CGFloat) -> Void
    @Environment(ShellViewModel.self) private var shell

    private var currentUser: UserModel { shell.currentUser }

    var body: some View {
        TabView(selection: Binding(get: { navigator.tab }, set: { navigator.select($0) })) {
            Tab(ShellTab.gigs.title, systemImage: ShellTab.gigs.systemImage, value: ShellTab.gigs) {
                ShellTabStack(router: navigator.gigs) {
                    DiscoverSheetContent(
                        model: discover,
                        pendingRequests: shell.pendingRequests,
                        openBookings: { navigator.select(.bookings) },
                        expand: { navigator.setDetent(.medium) },
                        onHeaderHeight: onHeaderHeight
                    )
                }
                .onChange(of: navigator.gigs.path.count) { old, new in navigator.gigsPathDidChange(from: old, to: new) }
            }
            Tab(ShellTab.bookings.title, systemImage: ShellTab.bookings.systemImage, value: ShellTab.bookings) {
                ShellTabStack(router: navigator.bookings) {
                    RouteDestination(route: .bookings(userId: currentUser.id))
                }
            }
            .badge(shell.pendingRequests)
            Tab(ShellTab.messages.title, systemImage: ShellTab.messages.systemImage, value: ShellTab.messages) {
                ShellTabStack(router: navigator.messages) {
                    RouteDestination(route: .messagingChannelList)
                }
            }
            .badge(shell.unreadMessages)
            Tab(ShellTab.profile.title, systemImage: ShellTab.profile.systemImage, value: ShellTab.profile) {
                ShellTabStack(router: navigator.profile) {
                    RouteDestination(route: .profile(userId: currentUser.id, user: currentUser))
                }
            }
            .badge(shell.unreadActivities)
            Tab(value: ShellTab.search, role: .search) {
                ShellTabStack(router: navigator.search) {
                    RouteDestination(route: .search)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { navigator.search.push(.gigSearch) } label: {
                                    Label(Route.gigSearch.title, systemImage: "building.2").labelStyle(.titleAndIcon)
                                }
                            }
                        }
                }
            }
        }
        .sheet(item: $discover.modal) { modal in
            switch modal {
            case .filters:
                DiscoverFiltersView(model: discover, showPaywall: { discover.modal = nil; navigator.gigs.push(.paywall) })
            case .allResults:
                DiscoverAllResultsView(model: discover, push: { route in discover.modal = nil; navigator.gigs.push(route) })
            }
        }
    }
}

/// One tab's stack plus its takeovers: `.paywall` as a resizable sheet (the screen behind stays visible) and
/// `.videoCall` full screen.
struct ShellTabStack<Root: View>: View {
    @Bindable var router: Router
    @ViewBuilder let root: () -> Root

    var body: some View {
        NavigationStack(path: $router.path) {
            root().tappedRouteDestinations()
        }
        .environment(router)
        .sheet(item: $router.sheet) { route in
            NavigationStack {
                RouteDestination(route: route)
                    .trackingScreen(route.title)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("close", systemImage: "xmark") { router.sheet = nil }
                        }
                    }
            }
            .environment(router)
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $router.fullScreenCover) { route in
            NavigationStack {
                RouteDestination(route: route)
                    .trackingScreen(route.title)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("close", systemImage: "xmark") { router.fullScreenCover = nil }
                        }
                    }
            }
            .environment(router)
        }
    }
}
