import SwiftUI
import UIKit
import TappedData
import TappedDomain
import TappedUI

/// The `TabView` inside the persistent map sheet. Each tab's `Router` is injected into its own stack so
/// existing `router.push/pop` call sites work unchanged.
struct ShellTabsView: View {
    let navigator: ShellNavigator
    @Bindable var discover: DiscoverViewModel
    let onHeaderHeight: (CGFloat) -> Void
    let onTabBarHeight: (CGFloat) -> Void
    @Environment(ShellViewModel.self) private var shell
    @State private var contentTab: ShellTab = .gigs

    private var currentUser: UserModel { shell.currentUser }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                tabs
                    .opacity(navigator.tab == .search ? 0 : 1)
                    .allowsHitTesting(navigator.tab != .search)
                    .accessibilityHidden(navigator.tab == .search)
                search
                    .opacity(navigator.tab == .search ? 1 : 0)
                    .allowsHitTesting(navigator.tab == .search)
                    .accessibilityHidden(navigator.tab != .search)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ShellTabBar(navigator: navigator)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onTabBarHeight($0) }
        }
        .onChange(of: navigator.tab, initial: true) { _, tab in
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            if tab != .search { contentTab = tab }
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

    private var tabs: some View {
        TabView(selection: Binding(get: { contentTab }, set: { navigator.select($0) })) {
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
        }
    }

    private var search: some View {
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

struct ShellTabBar: View {
    let navigator: ShellNavigator
    @Environment(ShellViewModel.self) private var shell
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var controlHeight: CGFloat = 58
    @ScaledMetric(relativeTo: .caption2) private var iconSize: CGFloat = 22

    private var height: CGFloat { min(controlHeight, 72) }

    var body: some View {
        GlassEffectContainer(spacing: TappedSpacing.sm) {
            HStack(spacing: TappedSpacing.md) {
                HStack(spacing: 0) {
                    ForEach(ShellTab.barTabs, id: \.self) { tab in
                        tabButton(tab)
                    }
                }
                .padding(TappedSpacing.xs)
                .frame(height: height)
                .glassEffect(.regular.interactive(), in: .capsule)

                Button { navigator.select(.search) } label: {
                    Image(systemName: ShellTab.search.systemImage)
                        .font(.system(size: min(iconSize, 28), weight: .semibold))
                        .foregroundStyle(navigator.tab == .search ? TappedColors.accent : .primary)
                        .frame(width: height, height: height)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(ShellTab.search.title)
                .accessibilityAddTraits(navigator.tab == .search ? .isSelected : [])
                .accessibilityIdentifier("shell-search")
            }
        }
        .padding(.horizontal, GlassMetrics.edgeInset)
        .padding(.vertical, TappedSpacing.sm)
    }

    private func tabButton(_ tab: ShellTab) -> some View {
        Button { navigator.select(tab) } label: {
            VStack(spacing: TappedSpacing.xs) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: min(iconSize, 28), weight: .semibold))
                    .overlay(alignment: .topTrailing) {
                        UnreadBadge(count: badge(for: tab))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .offset(x: TappedSpacing.md, y: -TappedSpacing.sm)
                            .accessibilityHidden(true)
                    }
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(tab.title)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(navigator.tab == tab ? TappedColors.accent : .primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if navigator.tab == tab {
                    Capsule().fill(.primary.opacity(0.08))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityValue(badgeDescription(for: tab))
        .accessibilityAddTraits(navigator.tab == tab ? .isSelected : [])
        .accessibilityIdentifier("shell-tab-\(tab.rawValue)")
    }

    private func badge(for tab: ShellTab) -> Int {
        switch tab {
        case .bookings: shell.pendingRequests
        case .messages: shell.unreadMessages
        case .profile: shell.unreadActivities
        case .gigs, .search: 0
        }
    }

    private func badgeDescription(for tab: ShellTab) -> String {
        let count = badge(for: tab)
        guard count > 0 else { return "" }
        switch tab {
        case .bookings: return "\(count) pending requests"
        case .messages: return "\(count) unread messages"
        case .profile: return "\(count) unread activities"
        case .gigs, .search: return ""
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
        .toolbarVisibility(.hidden, for: .tabBar)
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
