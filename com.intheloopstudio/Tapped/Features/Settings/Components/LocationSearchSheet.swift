import SwiftUI
import TappedData
import TappedUI

/// Google Places autocomplete (Dart `LocationFormPage`), presented from settings.
struct LocationSearchSheet: View {
    let search: (String) async -> [AutocompletePrediction]
    let resolve: (AutocompletePrediction) async -> PlaceData?
    let onSelect: (PlaceData) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var predictions: [AutocompletePrediction] = []
    @State private var isResolving = false

    var body: some View {
        NavigationStack {
            List(predictions) { prediction in
                Button {
                    Task {
                        isResolving = true
                        defer { isResolving = false }
                        if let place = await resolve(prediction) {
                            onSelect(place)
                            dismiss()
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prediction.primaryText)
                            .foregroundStyle(.primary)
                        if !prediction.secondaryText.isEmpty {
                            Text(prediction.secondaryText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if isResolving {
                    ProgressView()
                } else if predictions.isEmpty {
                    GlassEmptyState(query.isEmpty ? "search for your city" : "no places found", systemImage: "mappin.and.ellipse")
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "city or venue")
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                predictions = await search(query)
            }
            .navigationTitle("location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    let places = MockPlacesRepository()
    LocationSearchSheet(
        search: { (try? await places.searchPlace($0)) ?? [] },
        resolve: { try? await places.getPlaceById($0.placeId) },
        onSelect: { _ in }
    )
}
