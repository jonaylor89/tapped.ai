import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `lib/ui/services/service_view.dart`.
struct ServiceView: View {
    @State private var model: ServiceDetailViewModel
    @State private var confirmingDelete = false
    @Environment(Router.self) private var router

    init(dependencies: Dependencies, service: Service, serviceUser: UserModel?, currentUser: UserModel) {
        _model = State(initialValue: ServiceDetailViewModel(dependencies: dependencies, service: service, serviceUser: serviceUser, currentUserId: currentUser.id))
    }

    private var service: Service { model.service }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: TappedSpacing.xs) {
                    Text(service.title).font(TappedTypography.headingLg)
                    Text(service.formattedRate)
                        .font(TappedTypography.headingSm)
                        .monospacedDigit()
                        .foregroundStyle(TappedColors.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TappedSpacing.xs)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if let user = model.serviceUser {
                Section("offered by") {
                    Button { router.push(.profile(userId: user.id, user: user)) } label: {
                        UserTile(user: user, subtitle: "@\(user.username.username)")
                    }
                    .buttonStyle(.plain)
                }
            }

            if !service.description.isEmpty {
                Section("about") { Text(service.description) }
            }

            Section("details") {
                LabeledContent("billing", value: service.rateType.formattedName)
                LabeledContent("booked", value: service.count == 1 ? "1 time" : "\(service.count) times")
            }

            if model.isOwner {
                Section {
                    Button("edit service", systemImage: "pencil") { router.push(.createService(service: service)) }
                    Button("delete service", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(TappedColors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if !model.isOwner {
                GlassSubmitButton("book this service") {
                    router.push(.createBooking(requesteeId: service.userId, service: service, requesteeStripeConnectedAccountId: nil))
                }
            }
        }
        .overlay { if model.isDeleting { ProgressView().controlSize(.large) } }
        .navigationTitle("service")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("delete \(service.title)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("delete", role: .destructive) {
                Task { if await model.delete() { router.pop() } }
            }
        } message: {
            Text("bookers won't be able to request it anymore.")
        }
        .alert("service", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("ok", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task { await model.load() }
    }
}

#Preview("my service") {
    ServiceView(dependencies: .mock(signedIn: true), service: Samples.services[0], serviceUser: Samples.performer, currentUser: Samples.performer).bookingsPreview()
}

#Preview("book a service dark") {
    ServiceView(dependencies: .mock(signedIn: true), service: Samples.services[3], serviceUser: nil, currentUser: Samples.performer).bookingsPreview(dark: true)
}
