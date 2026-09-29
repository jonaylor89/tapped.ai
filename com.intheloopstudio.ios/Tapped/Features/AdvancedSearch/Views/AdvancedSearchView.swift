import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `advanced_search_view.dart`: inset-grouped filter form → results list.
struct AdvancedSearchView: View {
    @State private var model: AdvancedSearchViewModel
    @State private var showsResults: Bool

    init(dependencies: Dependencies, model: AdvancedSearchViewModel? = nil, showsResults: Bool = false) {
        _model = State(initialValue: model ?? AdvancedSearchViewModel(dependencies: dependencies))
        _showsResults = State(initialValue: showsResults)
    }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    MultiSelectList("occupations", items: [Occupation.venue] + Occupation.all, selection: $model.occupations) { $0.rawValue.lowercased() }
                } label: {
                    LabeledContent {
                        Text(MultiSelectList<Occupation>.summary(model.occupations) { $0.rawValue.lowercased() })
                    } label: {
                        SwiftUI.Label("occupations", systemImage: "person.2")
                    }
                }
                GenreSelectionRow(selection: $model.genres)
                NavigationLink {
                    MultiSelectList("labels", items: TappedDomain.Label.all, selection: $model.labels) { $0.rawValue.lowercased() }
                } label: {
                    LabeledContent {
                        Text(MultiSelectList<TappedDomain.Label>.summary(model.labels) { $0.rawValue.lowercased() })
                    } label: {
                        SwiftUI.Label("labels", systemImage: "opticaldisc")
                    }
                }
            } header: {
                Text("who")
            } footer: {
                Text("narrow down who you find")
            }

            Section("where") {
                LocationPickerRow(title: "location", place: $model.place)
                Picker(selection: $model.radiusMiles) {
                    ForEach(AdvancedSearchViewModel.radiusOptions, id: \.self) { Text("\($0) mi").tag($0) }
                } label: {
                    SwiftUI.Label("radius", systemImage: "scope")
                }
                .disabled(model.place == nil)
            }

            if model.isVenueSearch {
                Section {
                    CapacityRangeRows(minCapacity: $model.minCapacity, maxCapacity: $model.maxCapacity)
                } header: {
                    Text("capacity")
                } footer: {
                    Text("only applies when searching venues")
                }
            }
        }
        .navigationTitle("filters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("clear") { withAnimation { model.clear() } }
                    .disabled(!model.hasFilters)
            }
        }
        .safeAreaBar(edge: .bottom) {
            Button {
                showsResults = true
            } label: {
                Text("apply filters")
                    .font(TappedTypography.headingXs)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .tappedFloatingInset()
            .padding(.bottom, TappedSpacing.sm)
        }
        .navigationDestination(isPresented: $showsResults) {
            AdvancedSearchResultsView(model: model)
        }
        .animation(GlassMotion.ease, value: model.isVenueSearch)
    }
}

struct AdvancedSearchResultsView: View {
    let model: AdvancedSearchViewModel
    @Environment(Router.self) private var router

    var body: some View {
        List {
            Section {
                ForEach(model.results) { user in
                    Button {
                        router.push(.profile(userId: user.id, user: user))
                    } label: {
                        UserTile(user: user, subtitle: user.isVenue ? VenueRow.subtitle(user) : "@\(user.username.username)")
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                if !model.results.isEmpty { Text("\(model.results.count) \(model.results.count == 1 ? "result" : "results")") }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if model.isSearching && model.results.isEmpty {
                LoadingView()
            } else if model.failed {
                ErrorView("search is unavailable right now") { Task { await model.runSearch() } }
            } else if model.results.isEmpty {
                GlassEmptyState("no one matches", message: "try removing a filter or widening the radius", systemImage: "person.fill.questionmark")
            }
        }
        .navigationTitle("results")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.runSearch() }
    }
}

#Preview("filters") {
    NavigationStack {
        AdvancedSearchView(dependencies: .mock(signedIn: true))
    }
    .environment(\.dependencies, .mock(signedIn: true))
    .environment(Router())
}

#Preview("results") {
    let model = AdvancedSearchViewModel(dependencies: .mock(signedIn: true))
    model.occupations = [.venue]
    return NavigationStack {
        AdvancedSearchResultsView(model: model)
    }
    .environment(Router())
}
