import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `lib/ui/request_to_perform/request_to_perform_view.dart`.
struct RequestToPerformView: View {
    @State private var model: RequestToPerformViewModel
    @Environment(Router.self) private var router
    @State private var isAddingCollaborators = false
    private let dependencies: Dependencies

    init(dependencies: Dependencies, currentUser: UserModel, venues: [UserModel], collaborators: [UserModel]) {
        self.dependencies = dependencies
        _model = State(initialValue: RequestToPerformViewModel(dependencies: dependencies, currentUser: currentUser, venues: venues, collaborators: collaborators))
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                ForEach(model.venues) { venue in
                    UserTile(user: venue, subtitle: venue.venueInfo?.bookingEmail)
                }
                .onDelete { model.venues.remove(atOffsets: $0) }
            } header: {
                Text(model.venues.count == 1 ? "venue" : "venues")
            }

            Section("collaborators") {
                ForEach(model.collaborators) { UserTile(user: $0) }
                    .onDelete { model.collaborators.remove(atOffsets: $0) }
                Button("add collaborators", systemImage: "person.badge.plus") { isAddingCollaborators = true }
                    .fontWeight(.semibold)
            }

            Section {
                TextField("introduce yourself and what you'd like to play", text: $model.note, axis: .vertical)
                    .lineLimit(5...10)
            } header: {
                Text("message")
            } footer: {
                Text(model.validationMessage ?? "we'll email each venue from tapped. replies land in your inbox.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(model.isSubmitting)
        .safeAreaInset(edge: .bottom) {
            GlassSubmitButton("send request", isSubmitting: model.isSubmitting, isEnabled: model.canSubmit) {
                Task {
                    if let venues = await model.submit() { router.push(.requestToPerformConfirmation(venues: venues)) }
                }
            }
        }
        .alert("request to perform", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("ok", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: $isAddingCollaborators) {
            NavigationStack {
                AddCollaboratorsView(dependencies: dependencies, currentUserId: model.currentUser.id, collaborators: $model.collaborators)
            }
        }
        .navigationTitle("request to perform")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("request to perform") {
    RequestToPerformView(dependencies: .mock(signedIn: true), currentUser: Samples.performer, venues: Array(Samples.venues.prefix(2)), collaborators: [Samples.performers[2]])
        .bookingsPreview()
}

#Preview("request to perform dark") {
    RequestToPerformView(dependencies: .mock(signedIn: true), currentUser: Samples.performer, venues: [Samples.venues[3]], collaborators: [])
        .bookingsPreview(dark: true)
}
