import SwiftUI
import TappedDomain
import TappedUI

/// Genre and capacity filters; access is handled once by AppSession.
struct DiscoverFiltersView: View {
    let model: DiscoverViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var genres: Set<Genre>
    @State private var minCapacity: Double
    @State private var maxCapacity: Double

    init(model: DiscoverViewModel) {
        self.model = model
        _genres = State(initialValue: Set(model.genreFilters))
        _minCapacity = State(initialValue: model.capacityRange.lowerBound)
        _maxCapacity = State(initialValue: model.capacityRange.upperBound)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("capacity") {
                    LabeledContent("min", value: "\(Int(minCapacity))")
                    Slider(value: $minCapacity, in: 0...DiscoverViewModel.capacityLimit, step: 50)
                    LabeledContent("max", value: "\(Int(maxCapacity))\(maxCapacity >= DiscoverViewModel.capacityLimit ? "+" : "")")
                    Slider(value: $maxCapacity, in: 0...DiscoverViewModel.capacityLimit, step: 50)
                }
                Section("genres") {
                    ForEach(Genre.allCases) { genre in
                        Button {
                            if genres.contains(genre) { genres.remove(genre) } else { genres.insert(genre) }
                        } label: {
                            HStack {
                                Text(genre.formattedName.lowercased()).foregroundStyle(.primary)
                                Spacer()
                                if genres.contains(genre) {
                                    Image(systemName: "checkmark").foregroundStyle(TappedColors.accent)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("clear") {
                        genres = []
                        minCapacity = 0
                        maxCapacity = DiscoverViewModel.capacityLimit
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("done") {
                        let lower = min(minCapacity, maxCapacity), upper = max(minCapacity, maxCapacity)
                        let selected = Genre.allCases.filter(genres.contains)
                        Task {
                            await model.applyFilters(genres: selected, capacity: lower...upper)
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
