import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `lib/ui/service_selection/service_selection_view.dart` + profile services list.
/// Owners manage their services (tap to view, swipe to delete); others pick one to book.
struct ServiceSelectionView: View {
    @State private var model: ServiceListViewModel
    @State private var pendingDelete: Service?
    @Environment(Router.self) private var router

    init(dependencies: Dependencies, userId: String, currentUser: UserModel) {
        _model = State(initialValue: ServiceListViewModel(dependencies: dependencies, userId: userId, currentUserId: currentUser.id))
    }

    var body: some View {
        List {
            if model.isOwner {
                if !model.services.isEmpty {
                    Section {
                        ForEach(model.services) { service in
                            Button { router.push(.service(service, serviceUser: model.user)) } label: {
                                ServiceRow(service: service)
                            }
                            .foregroundStyle(.primary)
                            .swipeActions {
                                Button("delete", systemImage: "trash", role: .destructive) { pendingDelete = service }
                            }
                        }
                    } footer: {
                        Text("swipe a service to delete it.")
                    }
                }
            } else {
                Section {
                    Button {
                        router.push(.createBooking(requesteeId: model.userId, service: nil, requesteeStripeConnectedAccountId: nil))
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("custom booking").foregroundStyle(.primary)
                                Text("pick your own time and details").font(TappedTypography.bodySm).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "calendar.badge.plus").foregroundStyle(TappedColors.accent)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                if !model.services.isEmpty {
                    Section("services") {
                        ForEach(model.services) { service in
                            Button {
                                router.push(.createBooking(requesteeId: model.userId, service: service, requesteeStripeConnectedAccountId: nil))
                            } label: {
                                ServiceRow(service: service)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if model.isLoading {
                ProgressView()
            } else if model.isOwner, model.services.isEmpty {
                GlassEmptyState("no services yet", message: "add the sets and packages bookers can request", systemImage: "list.bullet.rectangle") {
                    Button("add service") { router.push(.createService(service: nil)) }.buttonStyle(.glass)
                }
                .padding(GlassMetrics.edgeInset)
            }
        }
        .navigationTitle("services")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("add service", systemImage: "plus") { router.push(.createService(service: nil)) }
                }
            }
        }
        .confirmationDialog(
            "delete \(pendingDelete?.title ?? "service")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { service in
            Button("delete", role: .destructive) { Task { await model.delete(service) } }
        } message: { _ in
            Text("bookers won't be able to request it anymore.")
        }
        .alert("services", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("ok", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .refreshable { await model.load() }
        .task { await model.load() }
    }
}

#Preview("my services") {
    ServiceSelectionView(dependencies: .mock(signedIn: true), userId: Samples.performer.id, currentUser: Samples.performer).bookingsPreview()
}

#Preview("book a service dark") {
    ServiceSelectionView(dependencies: .mock(signedIn: true), userId: "performer-mara", currentUser: Samples.performer).bookingsPreview(dark: true)
}
