import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `lib/ui/create_service/create_service_view.dart`.
struct CreateServiceView: View {
    @State private var model: ServiceFormViewModel
    @Environment(Router.self) private var router

    init(dependencies: Dependencies, service: Service?, ownerId: String) {
        _model = State(initialValue: ServiceFormViewModel(dependencies: dependencies, service: service, ownerId: ownerId))
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                TextField("title", text: $model.title)
                    .textInputAutocapitalization(.never)
                TextField("description", text: $model.description, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("service")
            } footer: {
                Text("\(model.description.count)/\(ServiceFormViewModel.descriptionLimit)")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Section {
                Picker("billing", selection: $model.rateType) {
                    ForEach(RateType.allCases, id: \.self) { Text($0.formattedName).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                LabeledContent(model.rateType == .hourly ? "rate per hour" : "rate") {
                    TextField("$0", value: $model.rate, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
            } header: {
                Text("rate")
            } footer: {
                Text(model.validationMessage ?? (model.rateType == .hourly ? "hourly services are priced by the length of the booking." : "one price, however long the set runs."))
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(model.isSubmitting)
        .safeAreaInset(edge: .bottom) {
            GlassSubmitButton(model.isEditing ? "save changes" : "create service", isSubmitting: model.isSubmitting, isEnabled: model.canSubmit) {
                Task { if await model.save() != nil { router.pop() } }
            }
        }
        .alert("service", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("ok", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .navigationTitle(model.isEditing ? "edit service" : "create service")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("create service") {
    CreateServiceView(dependencies: .mock(signedIn: true), service: nil, ownerId: Samples.performer.id).bookingsPreview()
}

#Preview("edit service dark") {
    CreateServiceView(dependencies: .mock(signedIn: true), service: Samples.services[0], ownerId: Samples.performer.id).bookingsPreview(dark: true)
}
