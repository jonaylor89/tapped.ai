import SwiftUI
import TappedDomain
import TappedUI

/// `MapSettings`: genre + capacity filters. Premium-only, like Flutter.
struct DiscoverFiltersView: View {
    let model: DiscoverViewModel
    let showPaywall: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var genres: Set<Genre>
    @State private var minCapacity: Double
    @State private var maxCapacity: Double

    init(model: DiscoverViewModel, showPaywall: @escaping () -> Void) {
        self.model = model
        self.showPaywall = showPaywall
        _genres = State(initialValue: Set(model.genreFilters))
        _minCapacity = State(initialValue: model.capacityRange.lowerBound)
        _maxCapacity = State(initialValue: model.capacityRange.upperBound)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !model.isPremium {
                    Section {
                        Button(action: showPaywall) {
                            Label("unlock filters with premium", systemImage: "crown")
                        }
                    }
                }
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
            .disabled(!model.isPremium)
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
                            if await model.applyFilters(genres: selected, capacity: lower...upper) {
                                dismiss()
                            } else {
                                showPaywall()
                            }
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
