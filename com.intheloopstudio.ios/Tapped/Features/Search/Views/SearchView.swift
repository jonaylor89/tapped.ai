import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `search_view.dart`: floating glass search capsule, recent searches, user/venue result tiles.
struct SearchView: View {
    @State private var model: SearchViewModel
    @Environment(Router.self) private var router
    @Environment(AppSession.self) private var session: AppSession?

    init(dependencies: Dependencies, currentUser: UserModel, recents: RecentSearches = RecentSearches(), initialQuery: String = "") {
        let model = SearchViewModel(dependencies: dependencies, currentUser: currentUser, recents: recents)
        model.query = initialQuery
        _model = State(initialValue: model)
    }

    var body: some View {
        List {
            if model.isIdle {
                idleContent
            } else {
                resultsContent
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("filters", systemImage: "line.3.horizontal.decrease") { router.push(.advancedSearch) }
            }
        }
        .safeAreaBar(edge: .top) {
            VStack(spacing: TappedSpacing.sm) {
                GlassSearchField(text: $model.query, placeholder: "search performers and venues", onSubmit: model.submit)
                GlassSegmentedPicker(selection: $model.scope, options: SearchScope.allCases) { $0.rawValue }
            }
            .tappedFloatingInset()
            .padding(.bottom, TappedSpacing.sm)
        }
        .overlay {
            if !model.isIdle {
                if model.isSearching && model.results.isEmpty {
                    LoadingView()
                } else if model.failed {
                    ErrorView(ErrorCopy.action("search right now")) { model.scheduleSearch(immediately: true) }
                } else if model.results.isEmpty {
                    GlassEmptyState("no results", message: "try a different name or username", systemImage: "person.fill.questionmark")
                }
            }
        }
        .task { await model.loadNearby() }
    }

    @ViewBuilder
    private var idleContent: some View {
        if !model.recentSearches.isEmpty {
            Section {
                ForEach(model.recentSearches, id: \.self) { term in
                    Button {
                        model.selectRecent(term)
                    } label: {
                        SwiftUI.Label(term, systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.primary)
                    }
                    .swipeActions {
                        Button("remove", systemImage: "trash", role: .destructive) { model.removeRecent(term) }
                    }
                }
            } header: {
                HStack {
                    Text("recent")
                    Spacer()
                    Button("clear") { model.clearRecents() }
                        .font(TappedTypography.label)
                }
            }
        }
        Section("explore") {
            exploreRow("gig feed", systemImage: "rectangle.stack.fill", route: .opportunityFeed)
            exploreRow("find venues", systemImage: "map.fill", route: .gigSearch, isPremiumOnly: true)
            exploreRow("advanced search", systemImage: "slider.horizontal.3", route: .advancedSearch)
        }
        if !model.nearbyOpportunities.isEmpty {
            Section {
                ForEach(model.nearbyOpportunities.prefix(3)) { opportunity in
                    Button {
                        router.push(.opportunity(opportunityId: opportunity.id, opportunity: opportunity))
                    } label: {
                        OpportunityTile(opportunity: opportunity)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                HStack {
                    Text("gigs near you")
                    Spacer()
                    Button("see all") { router.push(.opportunities(model.nearbyOpportunities)) }
                        .font(TappedTypography.label)
                }
            }
        }
    }

    private func exploreRow(_ title: String, systemImage: String, route: Route, isPremiumOnly: Bool = false) -> some View {
        let isLocked = isPremiumOnly && session?.isPremium != true
        return Button {
            router.push(route)
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack {
                    SwiftUI.Label(title, systemImage: systemImage).foregroundStyle(.primary).fixedSize()
                    Spacer(minLength: TappedSpacing.sm)
                    if isLocked { PremiumBadge() }
                }
                VStack(alignment: .leading, spacing: TappedSpacing.xs) {
                    SwiftUI.Label(title, systemImage: systemImage).foregroundStyle(.primary)
                    if isLocked { PremiumBadge() }
                }
            }
        }
        .accessibilityHint(isLocked ? "premium feature" : "")
    }

    @ViewBuilder
    private var resultsContent: some View {
        if !model.results.isEmpty {
            Section {
                ForEach(model.results) { user in
                    Button {
                        model.didSelect(user)
                        router.push(.profile(userId: user.id, user: user))
                    } label: {
                        UserTile(user: user, subtitle: model.subtitle(for: user)) {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(model.isSearching ? "searching…" : "\(model.results.count) \(model.results.count == 1 ? "result" : "results")")
            }
        }
    }
}

#Preview("idle") {
    let dependencies = Dependencies.mock(signedIn: true)
    NavigationStack {
        SearchView(dependencies: dependencies, currentUser: Samples.performer)
            .tappedRouteDestinations()
    }
    .environment(\.dependencies, dependencies)
    .environment(Router())
}

#Preview("results") {
    NavigationStack {
        SearchView(dependencies: .mock(signedIn: true), currentUser: Samples.performer, initialQuery: "the")
    }
    .environment(Router())
}
