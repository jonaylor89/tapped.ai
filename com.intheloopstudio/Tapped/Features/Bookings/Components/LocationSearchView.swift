import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Google Places search pushed from a form's location row (`location_form_view.dart` behaviour, scoped to booking forms).
struct LocationSearchView: View {
    @Binding var selection: PlaceData?
    @State private var model: LocationSearchViewModel
    @Environment(\.dismiss) private var dismiss

    init(dependencies: Dependencies, selection: Binding<PlaceData?>, initialQuery: String = "") {
        _selection = selection
        let model = LocationSearchViewModel(dependencies: dependencies)
        model.query = initialQuery
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model
        List {
            if let selection {
                Section("selected") {
                    PlaceRow(title: selection.name, subtitle: selection.displayAddress, isSelected: true)
                }
            }
            if !model.results.isEmpty {
                Section("results") {
                    ForEach(model.results) { prediction in
                        Button {
                            Task {
                                if let place = await model.resolve(prediction) {
                                    selection = place
                                    dismiss()
                                }
                            }
                        } label: {
                            PlaceRow(title: prediction.primaryText, subtitle: prediction.secondaryText, isSelected: prediction.placeId == selection?.placeId)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .overlay {
            if model.results.isEmpty, !model.isSearching {
                if model.query.trimmed.isEmpty {
                    if selection == nil {
                        ContentUnavailableView("search for a place", systemImage: "mappin.and.ellipse", description: Text("venues, addresses and cities"))
                    }
                } else {
                    ContentUnavailableView.search(text: model.query)
                }
            }
        }
        .overlay {
            if model.isResolving { ProgressView().controlSize(.large) }
        }
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "search venues and addresses")
        .textInputAutocapitalization(.never)
        .task(id: model.query) { await model.search() }
        .alert("location", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("ok", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .navigationTitle("location")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PlaceRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: TappedSpacing.md) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(.white, TappedColors.error)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(TappedTypography.bodyLg)
                if !subtitle.isEmpty {
                    Text(subtitle).font(TappedTypography.bodySm).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark").foregroundStyle(TappedColors.accent).fontWeight(.semibold)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Disclosure row that pushes `LocationSearchView`.
struct LocationRow: View {
    let dependencies: Dependencies
    @Binding var place: PlaceData?

    var body: some View {
        NavigationLink {
            LocationSearchView(dependencies: dependencies, selection: $place)
        } label: {
            LabeledContent {
                Text(place?.name ?? "choose")
                    .foregroundStyle(place == nil ? .secondary : .primary)
                    .lineLimit(1)
            } label: {
                Label("location", systemImage: "mappin.and.ellipse")
            }
        }
    }
}

#Preview("LocationSearchView") {
    @Previewable @State var place: PlaceData? = MockPlacesRepository.places[0]
    NavigationStack {
        LocationSearchView(dependencies: .mock(), selection: $place, initialQuery: "the")
    }
}

#Preview("LocationSearchView dark") {
    @Previewable @State var place: PlaceData?
    NavigationStack {
        LocationSearchView(dependencies: .mock(), selection: $place)
    }
    .preferredColorScheme(.dark)
}

#Preview("LocationRow") {
    @Previewable @State var place: PlaceData? = MockPlacesRepository.places[3]
    NavigationStack {
        Form { LocationRow(dependencies: .mock(), place: $place) }
    }
}
