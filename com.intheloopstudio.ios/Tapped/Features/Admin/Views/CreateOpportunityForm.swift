import PhotosUI
import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// `CreateOpportunityForm`: flier, details, where, pay, when → "full send".
struct CreateOpportunityForm: View {
    @State private var model: CreateOpportunityViewModel
    @State private var flierItem: PhotosPickerItem?
    @Environment(Router.self) private var router

    init(dependencies: Dependencies, currentUserId: String) {
        _model = State(initialValue: CreateOpportunityViewModel(dependencies: dependencies, currentUserId: currentUserId))
    }

    var body: some View {
        Form {
            flierSection
            Section("details") {
                TextField("title", text: $model.title, prompt: Text("open mic night"))
                    .textInputAutocapitalization(.never)
                TextField("description", text: $model.description, prompt: Text("add a description"), axis: .vertical)
                    .lineLimit(3...8)
                    .textInputAutocapitalization(.never)
                    .onChange(of: model.description) { _, newValue in
                        if newValue.count > CreateOpportunityViewModel.maxDescriptionLength {
                            model.description = String(newValue.prefix(CreateOpportunityViewModel.maxDescriptionLength))
                        }
                    }
            }
            whereSection
            Section("pay") {
                Picker("pay", selection: $model.isPaid) {
                    Text("unpaid").tag(false)
                    Text("paid").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                DatePicker("start time", selection: $model.startTime, in: Date.now...)
                DatePicker(
                    "end time",
                    selection: Binding(get: { model.endTime }, set: { model.endTimeChanged($0) }),
                    in: model.startTime...
                )
            } header: {
                Text("when")
            } footer: {
                Text("get the date right")
            }
            Section {
                Button {
                    Task {
                        if let opportunity = await model.submit() {
                            router.pop()
                            router.push(.opportunity(opportunityId: opportunity.id, opportunity: opportunity))
                        }
                    }
                } label: {
                    ZStack {
                        Text("full send").opacity(model.isSubmitting ? 0 : 1)
                        if model.isSubmitting { ProgressView().tint(.white) }
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: GlassMetrics.control)
                }
                .buttonStyle(.glassProminent)
                .tint(TappedColors.accent)
                .disabled(!model.canSubmit)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: flierItem) { _, item in
            Task {
                let data = try? await item?.loadTransferable(type: Data.self)
                model.setFlier(data: data)
            }
        }
        .alert(model.errorMessage ?? "", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("okay", role: .cancel) {}
        }
        .sensoryFeedback(.error, trigger: model.errorMessage) { _, new in new != nil }
        .sensoryFeedback(.success, trigger: model.created)
    }

    private var flierSection: some View {
        Section {
            if let image = model.flierImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: TappedRadius.lg, style: .continuous))
                    .listRowInsets(EdgeInsets())
                    .accessibilityLabel("flier")
            }
            PhotosPicker(selection: $flierItem, matching: .images) {
                Label(model.flierImage == nil ? "upload flier" : "change flier", systemImage: "photo.on.rectangle.angled")
            }
            if model.flierImage != nil {
                Button("remove flier", systemImage: "trash", role: .destructive) {
                    flierItem = nil
                    model.removeFlier()
                }
            }
        }
    }

    @ViewBuilder
    private var whereSection: some View {
        Section {
            if let venue = model.venue {
                HStack {
                    UserTile(user: venue)
                    Button("remove venue", systemImage: "xmark.circle.fill") { model.selectVenue(nil) }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.borderless)
                }
            } else {
                TextField("search venues", text: $model.venueQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .task(id: model.venueQuery) {
                        try? await Task.sleep(for: .milliseconds(250))
                        await model.searchVenues()
                    }
                ForEach(model.venueResults) { venue in
                    Button { model.selectVenue(venue) } label: { UserTile(user: venue) }
                        .buttonStyle(.plain)
                }
            }
            if let summary = model.locationSummary {
                HStack {
                    Label(summary, systemImage: "mappin.and.ellipse")
                    Spacer()
                    Button("clear location", systemImage: "xmark.circle.fill") { model.clearPlace() }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.borderless)
                }
            } else if model.venue == nil {
                TextField("drop a pin (city or address)", text: $model.placeQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .task(id: model.placeQuery) {
                        try? await Task.sleep(for: .milliseconds(250))
                        await model.searchPlaces()
                    }
                ForEach(model.placeResults) { prediction in
                    Button {
                        Task { await model.selectPlace(prediction) }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(prediction.primaryText)
                            Text(prediction.secondaryText).font(TappedTypography.bodySm).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("where")
        } footer: {
            Text("pick a venue on tapped, or drop a pin if they’re not on here yet")
        }
    }
}

#Preview {
    NavigationStack {
        CreateOpportunityForm(dependencies: .mock(signedIn: true, claims: [.admin]), currentUserId: Samples.performer.id)
            .navigationTitle("new opportunity")
    }
    .environment(Router())
}
