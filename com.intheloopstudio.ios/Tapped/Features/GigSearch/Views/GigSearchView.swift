import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `gig_search_view.dart` / `venue_filter_form.dart`. Search is premium-only (→ paywall).
struct GigSearchView: View {
    @State private var model: GigSearchViewModel
    @State private var showsResults: Bool
    @State private var validationMessage: String?
    @Environment(Router.self) private var router

    init(dependencies: Dependencies, currentUser: UserModel, isPremium: Bool, model: GigSearchViewModel? = nil, showsResults: Bool = false) {
        _model = State(initialValue: model ?? GigSearchViewModel(dependencies: dependencies, currentUser: currentUser, isPremium: isPremium))
        _showsResults = State(initialValue: showsResults)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: TappedSpacing.xs) {
                    Text("find gigs")
                        .font(TappedTypography.headingLg)
                    Text("reach thousands of venues in seconds")
                        .font(TappedTypography.bodyMd)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }

            Section("where") {
                LocationPickerRow(title: "city", place: $model.place)
            }

            Section("what") {
                GenreSelectionRow(selection: $model.genres)
            }

            Section {
                CapacityRangeRows(minCapacity: $model.minCapacity, maxCapacity: $model.maxCapacity, limit: GigSearchViewModel.capacityLimit)
            } header: {
                Text("capacity")
            } footer: {
                Text("the capacity range defaults to numbers that align with your previous booking history, so you reach rooms you can fill.")
            }
        }
        .navigationTitle("gig search")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .bottom) {
            Button {
                Task { await search() }
            } label: {
                HStack(spacing: TappedSpacing.sm) {
                    if model.isSearching {
                        ProgressView()
                    } else {
                        Image(systemName: model.isPremium ? "magnifyingglass" : "lock.fill")
                    }
                    Text(model.isPremium ? "search venues" : "unlock search")
                }
                .font(TappedTypography.headingXs)
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .disabled(model.isPremium && !model.canSearch || model.isSearching)
            .tappedFloatingInset()
            .padding(.bottom, TappedSpacing.sm)
        }
        .alert("can't search yet", isPresented: Binding { validationMessage != nil } set: { if !$0 { validationMessage = nil } }) {
            Button("ok", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "")
        }
        .navigationDestination(isPresented: $showsResults) {
            GigSearchResultsView(model: model)
        }
        .task {
            await model.loadInitialPlace()
            if showsResults, model.results.isEmpty { _ = await model.searchVenues() }
        }
    }

    private func search() async {
        switch await model.searchVenues() {
        case .results: showsResults = true
        case .needsPremium: router.push(.paywall)
        case let .invalid(message): validationMessage = message
        }
    }
}

/// Port of `gig_search_results_view.dart`: fit-sorted venues with multi-select → request to perform.
struct GigSearchResultsView: View {
    let model: GigSearchViewModel
    @Environment(Router.self) private var router

    var body: some View {
        List {
            Section {
                ForEach(model.results) { venue in
                    let fit = model.fit(for: venue)
                    Button {
                        withAnimation(GlassMotion.spring) { model.toggle(venue) }
                    } label: {
                        HStack(spacing: TappedSpacing.md) {
                            SelectionIndicator(isSelected: model.selectedIds.contains(venue.id))
                            UserTile(user: venue, subtitle: model.subtitle(for: venue)) {
                                if fit.isGoodFit {
                                    Text("for you")
                                        .font(TappedTypography.label.weight(.bold))
                                        .foregroundStyle(TappedColors.success)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: model.selectedIds.contains(venue.id))
                    .contextMenu {
                        Button("view profile", systemImage: "person.crop.circle") {
                            router.push(.profile(userId: venue.id, user: venue))
                        }
                    }
                }
            } header: {
                if !model.results.isEmpty { Text("pick the venues to reach out to") }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if model.results.isEmpty {
                if model.failed {
                    ErrorView("search is unavailable right now") { Task { _ = await model.searchVenues() } }
                } else {
                    GlassEmptyState("no venues found", message: "try widening the capacity range or genres", systemImage: "building.2")
                }
            }
        }
        .navigationTitle("venues")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !model.results.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.allSelected ? "deselect all" : "select all") {
                        withAnimation(GlassMotion.spring) { model.selectAll(!model.allSelected) }
                    }
                }
            }
        }
        .safeAreaBar(edge: .bottom) {
            if !model.selectedIds.isEmpty {
                Button {
                    router.push(.requestToPerform(venues: model.selectedVenues, collaborators: []))
                } label: {
                    Text("continue (\(model.selectedIds.count))")
                        .font(TappedTypography.headingXs)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glassProminent)
                .tappedFloatingInset()
                .padding(.bottom, TappedSpacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

#Preview("form") {
    let dependencies = Dependencies.mock(signedIn: true, isPremium: true)
    NavigationStack {
        GigSearchView(dependencies: dependencies, currentUser: Samples.performer, isPremium: true)
            .tappedRouteDestinations()
    }
    .environment(\.dependencies, dependencies)
    .environment(Router())
}

#Preview("locked") {
    NavigationStack {
        GigSearchView(dependencies: .mock(signedIn: true), currentUser: Samples.performer, isPremium: false)
    }
    .environment(\.dependencies, .mock(signedIn: true))
    .environment(Router())
}

#Preview("results") {
    let model = GigSearchViewModel(dependencies: .mock(signedIn: true, isPremium: true), currentUser: Samples.performer, isPremium: true)
    NavigationStack {
        GigSearchResultsView(model: model)
    }
    .environment(Router())
    .task {
        model.place = MockPlacesRepository.places.first
        _ = await model.searchVenues()
    }
}
