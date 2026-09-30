import SwiftUI

/// Searchable inset-grouped checklist, pushed from a filter `Form` row (genres, occupations, labels).
public struct MultiSelectList<Item: Hashable>: View {
    let title: String
    let items: [Item]
    let label: (Item) -> String
    @Binding var selection: Set<Item>
    @State private var query = ""

    public init(_ title: String, items: [Item], selection: Binding<Set<Item>>, label: @escaping (Item) -> String) {
        self.title = title
        self.items = items
        _selection = selection
        self.label = label
    }

    private var filtered: [Item] {
        query.isEmpty ? items : items.filter { label($0).localizedCaseInsensitiveContains(query) }
    }

    public var body: some View {
        List {
            ForEach(filtered, id: \.self) { item in
                Button {
                    if selection.contains(item) { selection.remove(item) } else { selection.insert(item) }
                } label: {
                    HStack {
                        Text(label(item)).foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(item) {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(TappedColors.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(selection.contains(item) ? .isSelected : [])
            }
        }
        .searchable(text: $query, prompt: "search \(title)")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !selection.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("clear") { selection.removeAll() }
                }
            }
        }
    }

    /// Summary for the pushing row: "any", a single value, or "n selected".
    public static func summary(_ selection: Set<Item>, label: (Item) -> String) -> String {
        switch selection.count {
        case 0: "any"
        case 1: selection.first.map(label) ?? "any"
        default: "\(selection.count) selected"
        }
    }
}

#Preview("MultiSelectList") {
    @Previewable @State var selection: Set<String> = ["jazz"]
    NavigationStack {
        MultiSelectList("genres", items: ["rock", "jazz", "pop", "house"], selection: $selection) { $0 }
    }
}
