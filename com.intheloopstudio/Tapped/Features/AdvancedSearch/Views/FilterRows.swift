import SwiftUI
import TappedDomain
import TappedUI

/// Pushes a `MultiSelectList` of genres from a filter `Form`.
struct GenreSelectionRow: View {
    var title = "genres"
    @Binding var selection: Set<Genre>

    var body: some View {
        NavigationLink {
            MultiSelectList(title, items: Genre.allCases, selection: $selection) { $0.formattedName.lowercased() }
        } label: {
            LabeledContent {
                Text(MultiSelectList<Genre>.summary(selection) { $0.formattedName.lowercased() })
            } label: {
                SwiftUI.Label(title, systemImage: "music.note.list")
            }
        }
    }
}

/// Min/max sliders over `0...limit`; the top of the range reads "1000+".
struct CapacityRangeRows: View {
    @Binding var minCapacity: Double
    @Binding var maxCapacity: Double
    var limit = AdvancedSearchViewModel.capacityLimit

    var body: some View {
        LabeledContent("min", value: "\(Int(minCapacity))")
        Slider(value: $minCapacity, in: 0...limit, step: 50) { Text("minimum capacity") }
            .onChange(of: minCapacity) { _, value in if value > maxCapacity { maxCapacity = value } }
        LabeledContent("max", value: "\(Int(maxCapacity))\(maxCapacity >= limit ? "+" : "")")
        Slider(value: $maxCapacity, in: 0...limit, step: 50) { Text("maximum capacity") }
            .onChange(of: maxCapacity) { _, value in if value < minCapacity { minCapacity = value } }
    }
}

#Preview {
    @Previewable @State var genres: Set<Genre> = [.funk]
    @Previewable @State var minCapacity = 0.0
    @Previewable @State var maxCapacity = 600.0
    NavigationStack {
        Form {
            GenreSelectionRow(selection: $genres)
            Section("capacity") {
                CapacityRangeRows(minCapacity: $minCapacity, maxCapacity: $maxCapacity)
            }
        }
    }
}
