import SwiftUI
import TappedDomain

/// Multi-select genre list (Dart `GenreSelection`).
struct GenrePickerView: View {
    @Binding var selection: Set<Genre>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(Genre.allCases) { genre in
                Button {
                    if selection.contains(genre) { selection.remove(genre) } else { selection.insert(genre) }
                } label: {
                    HStack {
                        Text(genre.formattedName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(genre) {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .accessibilityAddTraits(selection.contains(genre) ? .isSelected : [])
            }
            .navigationTitle("genres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var selection: Set<Genre> = [.funk, .electronic]
    GenrePickerView(selection: $selection)
}
