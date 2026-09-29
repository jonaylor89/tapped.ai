import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `lib/ui/create_booking/create_booking_view.dart` (Stripe/cost sections removed).
struct CreateBookingView: View {
    let dependencies: Dependencies
    @State private var model: CreateBookingViewModel
    @Environment(Router.self) private var router

    init(dependencies: Dependencies, currentUser: UserModel, requesteeId: String, service: Service?, now: @escaping () -> Date = { .now }) {
        self.dependencies = dependencies
        _model = State(initialValue: CreateBookingViewModel(dependencies: dependencies, currentUser: currentUser, requesteeId: requesteeId, service: service, now: now))
    }

    var body: some View {
        @Bindable var model = model
        Form {
            if let requestee = model.requestee {
                Section("performer") { UserTile(user: requestee) }
            }

            Section("event") {
                TextField("event name", text: $model.name)
                    .textInputAutocapitalization(.never)
                LocationRow(dependencies: dependencies, place: $model.place)
            }

            Section {
                DatePicker("starts", selection: $model.start, in: model.now()..., displayedComponents: [.date, .hourAndMinute])
                DatePicker("ends", selection: $model.end, in: model.start..., displayedComponents: [.date, .hourAndMinute])
                LabeledContent("length", value: Duration.seconds(max(model.duration, 0)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
            } header: {
                Text("when")
            }

            if !model.services.isEmpty {
                Section {
                    Picker("service", selection: $model.selectedServiceId) {
                        Text("none").tag(String?.none)
                        ForEach(model.services) { service in
                            Text(service.title).tag(Optional(service.id))
                        }
                    }
                } footer: {
                    if let service = model.selectedService, !service.description.isEmpty {
                        Text(service.description)
                    }
                }
            }

            Section {
                TextField("anything the performer should know?", text: $model.note, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("note")
            } footer: {
                if let message = model.validationMessage {
                    Text(message)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(model.isSubmitting)
        .safeAreaInset(edge: .bottom) {
            GlassSubmitButton("request booking", isSubmitting: model.isSubmitting, isEnabled: model.canSubmit) {
                Task {
                    if let booking = await model.submit() { router.push(.bookingConfirmation(booking)) }
                }
            }
        }
        .alert("create booking", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("ok", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .navigationTitle("create booking")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }
}

#Preview("create booking") {
    CreateBookingView(dependencies: .mock(signedIn: true), currentUser: Samples.performer, requesteeId: "performer-mara", service: nil)
        .bookingsPreview()
}

#Preview("create booking dark") {
    CreateBookingView(dependencies: .mock(signedIn: true), currentUser: Samples.performer, requesteeId: "performer-mara", service: Samples.services[3])
        .bookingsPreview(dark: true)
}
