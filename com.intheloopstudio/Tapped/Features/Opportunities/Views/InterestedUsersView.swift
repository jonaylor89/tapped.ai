import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `interested_users_view.dart`: applicants for an opportunity the current user posted.
struct InterestedUsersView: View {
    @State private var model: InterestedUsersViewModel
    @Environment(Router.self) private var router

    init(dependencies: Dependencies, opportunity: Opportunity) {
        _model = State(initialValue: InterestedUsersViewModel(dependencies: dependencies, opportunity: opportunity))
    }

    var body: some View {
        List {
            if !model.users.isEmpty {
                Section {
                    ForEach(model.users) { user in
                        Button {
                            router.push(.profile(userId: user.id, user: user))
                        } label: {
                            UserTile(user: user, subtitle: "@\(user.username.username)") {
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(model.opportunity.title.lowercased())
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if model.isLoading && model.users.isEmpty {
                LoadingView()
            } else if model.failed {
                ErrorView { Task { await model.load() } }
            } else if model.users.isEmpty {
                GlassEmptyState("no applicants yet", message: "share the opportunity to reach more performers", systemImage: "person.2")
            }
        }
        .navigationTitle("applicants")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task { await model.load() }
    }
}

#Preview {
    NavigationStack {
        InterestedUsersView(dependencies: .mock(signedIn: true), opportunity: Samples.opportunities[0])
    }
    .environment(Router())
}
