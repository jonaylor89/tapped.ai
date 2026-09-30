import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `add_collaborators_view.dart`. Edits `collaborators` in place (Dart `onCollaboratorAdded/Removed`).
struct AddCollaboratorsView: View {
    @Binding var collaborators: [UserModel]
    @State private var model: AddCollaboratorsViewModel
    @Environment(\.dismiss) private var dismiss

    init(dependencies: Dependencies, currentUserId: String, maxCollaborators: Int = 5, collaborators: Binding<[UserModel]>) {
        _collaborators = collaborators
        _model = State(initialValue: AddCollaboratorsViewModel(dependencies: dependencies, currentUserId: currentUserId, maxCollaborators: maxCollaborators))
    }

    var body: some View {
        @Bindable var model = model
        List {
            if !model.query.isEmpty {
                Section {
                    if model.isAtMax(collaborators) {
                        Text("you can add up to \(model.maxCollaborators) collaborators")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.results.filter { user in !collaborators.contains { $0.id == user.id } }) { user in
                        Button {
                            collaborators.append(user)
                            model.query = ""
                        } label: {
                            UserTile(user: user, subtitle: "@\(user.username.username)") {
                                Image(systemName: "plus.circle.fill").foregroundStyle(TappedColors.accent)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isAtMax(collaborators))
                    }
                }
            }
            Section("bill · \(collaborators.count)/\(model.maxCollaborators)") {
                if collaborators.isEmpty {
                    Text("search for performers to add to the bill")
                        .foregroundStyle(.secondary)
                }
                ForEach(collaborators) { user in
                    UserTile(user: user, subtitle: "@\(user.username.username)")
                }
                .onDelete { collaborators.remove(atOffsets: $0) }
            }
        }
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "search performers")
        .task(id: model.query) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await model.runSearch()
        }
        .navigationTitle("add collaborators")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") { dismiss() }
            }
        }
    }
}

/// `Route.addCollaborators` destination: owns the bill when pushed without a caller binding.
struct AddCollaboratorsRoute: View {
    let dependencies: Dependencies
    let currentUserId: String
    let maxCollaborators: Int
    @State var collaborators: [UserModel]

    var body: some View {
        AddCollaboratorsView(dependencies: dependencies, currentUserId: currentUserId, maxCollaborators: maxCollaborators, collaborators: $collaborators)
    }
}

#Preview {
    @Previewable @State var collaborators = [Samples.performers[2]]
    NavigationStack {
        AddCollaboratorsView(dependencies: .mock(signedIn: true), currentUserId: Samples.performer.id, collaborators: $collaborators)
    }
}

#Preview("dark") {
    @Previewable @State var collaborators: [UserModel] = []
    NavigationStack {
        AddCollaboratorsView(dependencies: .mock(signedIn: true), currentUserId: Samples.performer.id, collaborators: $collaborators)
    }
    .preferredColorScheme(.dark)
}
