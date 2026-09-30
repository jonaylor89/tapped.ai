import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `lib/ui/add_past_booking/add_past_booking_view.dart` (flier upload and amount paid not ported).
struct AddPastBookingView: View {
    let dependencies: Dependencies
    @State private var model: AddPastBookingViewModel
    @Environment(Router.self) private var router
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(ShellViewModel.self) private var shell: ShellViewModel?

    init(dependencies: Dependencies, currentUser: UserModel, now: @escaping () -> Date = { .now }) {
        self.dependencies = dependencies
        _model = State(initialValue: AddPastBookingViewModel(dependencies: dependencies, currentUser: currentUser, now: now))
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section("event") {
                TextField("event name", text: $model.name)
                    .textInputAutocapitalization(.never)
                LocationRow(dependencies: dependencies, place: $model.place)
            }

            Section("when") {
                DatePicker("started", selection: $model.start, in: ...model.now(), displayedComponents: [.date, .hourAndMinute])
                Picker("length", selection: $model.duration) {
                    ForEach(AddPastBookingViewModel.durations, id: \.self) { duration in
                        Text(Duration.seconds(duration).formatted(.units(allowed: [.hours], width: .wide))).tag(duration)
                    }
                }
            }

            Section {
                TextField("lineup, highlights, anything worth remembering", text: $model.note, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("note")
            } footer: {
                Text(model.validationMessage ?? "past bookings show on your profile and booking history map.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(model.isSubmitting)
        .safeAreaInset(edge: .bottom) {
            GlassSubmitButton("add booking", isSubmitting: model.isSubmitting, isEnabled: model.canSubmit) {
                Task {
                    guard await model.submit() != nil else { return }
                    if let user = model.updatedUser {
                        shell?.update(user)
                        session?.updateCurrentUser(user)
                    }
                    router.pop()
                }
            }
        }
        .alert("add past booking", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("ok", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .navigationTitle("add past booking")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("add past booking") {
    AddPastBookingView(dependencies: .mock(signedIn: true), currentUser: Samples.performer).bookingsPreview()
}

#Preview("add past booking dark") {
    AddPastBookingView(dependencies: .mock(signedIn: true), currentUser: Samples.performer).bookingsPreview(dark: true)
}
