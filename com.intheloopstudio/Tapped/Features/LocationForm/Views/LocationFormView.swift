import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `location_form_view.dart`: glass search capsule over Places predictions.
/// Presented as a sheet by filter forms (which need the result) or pushed via `.locationForm`.
struct LocationFormView: View {
    @State private var model: LocationFormViewModel
    let onSelect: (PlaceData) -> Void

    init(dependencies: Dependencies, initialPlace: PlaceData?, onSelect: @escaping (PlaceData) -> Void) {
        _model = State(initialValue: LocationFormViewModel(dependencies: dependencies, initialPlace: initialPlace))
        self.onSelect = onSelect
    }

    var body: some View {
        List {
            if let place = model.initialPlace, model.query.isEmpty {
                Section("current") {
                    Button {
                        onSelect(place)
                    } label: {
                        placeRow(title: place.name.lowercased(), subtitle: place.shortFormattedAddress?.lowercased(), systemImage: "checkmark.circle.fill", isResolving: false)
                    }
                }
            }
            if !model.predictions.isEmpty {
                Section {
                    ForEach(model.predictions) { prediction in
                        Button {
                            Task {
                                if let place = await model.resolve(prediction) { onSelect(place) }
                            }
                        } label: {
                            placeRow(
                                title: prediction.primaryText.lowercased(),
                                subtitle: prediction.secondaryText.lowercased(),
                                systemImage: "mappin.circle.fill",
                                isResolving: model.resolvingPlaceId == prediction.placeId
                            )
                        }
                        .disabled(model.resolvingPlaceId != nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if model.isSearching && model.predictions.isEmpty {
                LoadingView()
            } else if model.failed {
                ErrorView("couldn't reach google places") { model.scheduleSearch() }
            } else if !model.query.isEmpty && model.predictions.isEmpty {
                GlassEmptyState("no places found", message: "try a city name", systemImage: "mappin.slash")
            } else if model.query.isEmpty && model.initialPlace == nil {
                GlassEmptyState("search for a city", message: "we use it to find venues and gigs near you", systemImage: "map")
            }
        }
        .safeAreaBar(edge: .top) {
            GlassSearchField(text: $model.query, placeholder: "search a city")
                .tappedFloatingInset()
                .padding(.bottom, TappedSpacing.sm)
        }
        .navigationTitle("location")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func placeRow(title: String, subtitle: String?, systemImage: String, isResolving: Bool) -> some View {
        HStack(spacing: TappedSpacing.md) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(TappedColors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(TappedTypography.headingXs).foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(TappedTypography.bodySm).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if isResolving { ProgressView() }
        }
        .contentShape(Rectangle())
    }
}

/// Inset-grouped `Form` row that opens `LocationFormView` in a sheet and writes the picked place back.
struct LocationPickerRow: View {
    let title: String
    @Binding var place: PlaceData?
    @Environment(\.dependencies) private var dependencies
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            LabeledContent {
                Text(place?.name.lowercased() ?? "choose a city")
                    .foregroundStyle(place == nil ? .secondary : .primary)
            } label: {
                SwiftUI.Label(title, systemImage: "mappin.and.ellipse")
                    .foregroundStyle(.primary)
            }
        }
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                LocationFormView(dependencies: dependencies, initialPlace: place) { selected in
                    place = selected
                    isPresented = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("cancel", systemImage: "xmark") { isPresented = false }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }
}

#Preview("LocationFormView") {
    NavigationStack {
        LocationFormView(dependencies: .mock(), initialPlace: MockPlacesRepository.places.first) { _ in }
    }
}

#Preview("LocationPickerRow") {
    @Previewable @State var place: PlaceData?
    Form {
        LocationPickerRow(title: "where", place: $place)
    }
    .environment(\.dependencies, .mock())
}
