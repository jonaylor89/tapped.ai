import PhotosUI
import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `lib/ui/settings/settings_view.dart` as a native inset-grouped form.
struct SettingsView: View {
    @Environment(Router.self) private var router
    @Environment(AppSession.self) private var session
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    @State private var model: SettingsViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var isPickingLocation = false
    @State private var isPickingGenres = false
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingDelete = false
    @State private var isReauthenticating = false

    init(dependencies: Dependencies, currentUser: UserModel) {
        _model = State(initialValue: SettingsViewModel(dependencies: dependencies, currentUser: currentUser))
    }

    var body: some View {
        @Bindable var model = model
        Form {
            photoSection
            accountSection(model)
            performerSection(model)
            if model.isPerformer { socialsSection(model) }
            servicesSection
            notificationsSection(model)
            appearanceSection
            moreSection
            accountActionsSection
        }
        .formStyle(.grouped)
        .navigationTitle("settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if model.isSaving {
                    ProgressView()
                } else {
                    Button("save", systemImage: "checkmark") { Task { await save() } }
                        .disabled(!model.hasChanges)
                }
            }
        }
        .alert("something went wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("ok", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog("sign out?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("sign out", role: .destructive) {
                Task {
                    await session.signOut()
                    router.popToRoot()
                }
            }
        }
        .confirmationDialog("delete account?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("delete account", role: .destructive) { isReauthenticating = true }
        } message: {
            Text("this permanently deletes your profile, bookings and messages")
        }
        .reauthenticationSheet(isPresented: $isReauthenticating, reason: "enter your password to delete your account") {
            isReauthenticating = false
            Task {
                if await model.deleteAccount() { router.popToRoot() }
            }
        }
        .sheet(isPresented: $isPickingLocation) {
            LocationSearchSheet(search: model.searchPlaces, resolve: model.place(for:), onSelect: model.selectPlace)
        }
        .sheet(isPresented: $isPickingGenres) {
            GenrePickerView(selection: $model.selectedGenres)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { model.setPickedImage(data) }
            }
        }
        .task { await model.load() }
    }

    private func save() async {
        guard await model.save() != nil else { return }
        await session.refreshCurrentUser()
        router.pop()
    }

    // MARK: - sections

    private var photoSection: some View {
        let pickedImage = model.pickedImage
        let url = model.profilePictureURL
        let name = model.draft.displayName
        return Section {
            HStack {
                Spacer()
                PhotosPicker(selection: $photoItem, matching: .images) {
                    VStack(spacing: TappedSpacing.sm) {
                        SettingsAvatar(image: pickedImage, url: url, name: name)
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.fill")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(7)
                                    .background(TappedColors.accent, in: Circle())
                            }
                        Text("change photo")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .accessibilityLabel("change profile photo")
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    private func accountSection(_ model: SettingsViewModel) -> some View {
        @Bindable var model = model
        return Section {
            LabeledContent("username") {
                TextField("username", text: $model.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("display name") {
                TextField("display name", text: $model.draft.artistName)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: TappedSpacing.xs) {
                TextField("bio", text: $model.draft.bio, axis: .vertical)
                    .lineLimit(3...6)
                Text(model.bioCountLabel)
                    .font(.caption)
                    .foregroundStyle(model.draft.bio.count > SettingsViewModel.maxBioLength ? TappedColors.error : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Button { isPickingLocation = true } label: {
                LabeledContent("location") {
                    Text(model.placeName?.lowercased() ?? "add location")
                        .foregroundStyle(model.placeName == nil ? TappedColors.accent : .secondary)
                }
            }
            .tint(.primary)
            .swipeActions {
                if model.draft.location != nil {
                    Button("remove", role: .destructive) { model.clearLocation() }
                }
            }
        } header: {
            Text("account")
        }
    }

    private func performerSection(_ model: SettingsViewModel) -> some View {
        @Bindable var model = model
        return Section {
            Toggle("i'm a performer", isOn: $model.isPerformer)
            if model.isPerformer {
                Button { isPickingGenres = true } label: {
                    LabeledContent("genres") {
                        Text(model.genresSummary)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
                Picker("category", selection: $model.performer.category) {
                    ForEach(PerformerCategory.allCases) { Text($0.formattedName.lowercased()).tag($0) }
                }
                Picker("label", selection: $model.performer.label) {
                    ForEach(TappedDomain.Label.all) { Text($0.rawValue.lowercased()).tag($0.rawValue) }
                }
                LabeledContent("avg. ticket price") {
                    TextField("$0", value: $model.ticketPriceDollars, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("avg. attendance") {
                    TextField("0", value: $model.performer.averageAttendance, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("booking email") {
                    TextField("booking@example.com", text: $model.performer.bookingEmail.orEmpty)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("booking agency") {
                    TextField("none", text: $model.performer.bookingAgency.orEmpty)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("press kit") {
                    TextField("https://", text: $model.performer.pressKitUrl.orEmpty)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Text("performer info")
        } footer: {
            if model.isPerformer { Text("venues use your genres, category and audience to find you") }
        }
    }

    private func socialsSection(_ model: SettingsViewModel) -> some View {
        @Bindable var model = model
        return Section {
            SocialField(name: "instagram", handle: $model.draft.socialFollowing.instagramHandle.orEmpty, followers: $model.draft.socialFollowing.instagramFollowers)
            SocialField(name: "tiktok", handle: $model.draft.socialFollowing.tiktokHandle.orEmpty, followers: $model.draft.socialFollowing.tiktokFollowers)
            SocialField(name: "x", handle: $model.draft.socialFollowing.twitterHandle.orEmpty, followers: $model.draft.socialFollowing.twitterFollowers)
            SocialField(name: "facebook", handle: $model.draft.socialFollowing.facebookHandle.orEmpty, followers: $model.draft.socialFollowing.facebookFollowers)
            SocialField(name: "youtube", handle: $model.draft.socialFollowing.youtubeHandle.orEmpty)
            SocialField(name: "soundcloud", handle: $model.draft.socialFollowing.soundcloudHandle.orEmpty)
            SocialField(name: "audius", handle: $model.draft.socialFollowing.audiusHandle.orEmpty)
            SocialField(name: "twitch", handle: $model.draft.socialFollowing.twitchHandle.orEmpty)
        } header: {
            Text("socials")
        } footer: {
            Text("let promoters know how big your online presence is")
        }
    }

    private var servicesSection: some View {
        Section("services") {
            ForEach(model.services) { service in
                Button { router.push(.createService(service: service)) } label: {
                    ServiceRow(service: service)
                }
                .tint(.primary)
                .swipeActions {
                    Button("delete", role: .destructive) { Task { await model.deleteService(service) } }
                }
            }
            Button("add service", systemImage: "plus") { router.push(.createService(service: nil)) }
        }
    }

    private func notificationsSection(_ model: SettingsViewModel) -> some View {
        @Bindable var model = model
        return Group {
            Section("push notifications") {
                Toggle("new direct messages", isOn: $model.draft.pushNotifications.directMessages)
                Toggle("booking requests", isOn: $model.draft.pushNotifications.bookingRequests)
            }
            Section("emails") {
                Toggle("new app releases", isOn: $model.draft.emailNotifications.appReleases)
                Toggle("new direct messages", isOn: $model.draft.emailNotifications.directMessages)
                Toggle("booking requests", isOn: $model.draft.emailNotifications.bookingRequests)
                Toggle("tapped updates", isOn: $model.draft.emailNotifications.tappedUpdates)
            }
        }
    }

    private var appearanceSection: some View {
        Section("appearance") {
            Picker("appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var moreSection: some View {
        Section {
            Button("tapped premium", systemImage: "sparkles") { router.push(.paywall) }
            Link(destination: URL(string: "https://instagram.com/tappedai")!) {
                SwiftUI.Label("follow us on instagram", systemImage: "camera.fill")
            }
            Link(destination: URL(string: "https://app.tapped.ai/privacy")!) {
                SwiftUI.Label("privacy policy", systemImage: "hand.raised.fill")
            }
            Link(destination: URL(string: "https://app.tapped.ai/eula")!) {
                SwiftUI.Label("terms of service", systemImage: "doc.text.fill")
            }
        }
    }

    private var accountActionsSection: some View {
        Section {
            Button("sign out", role: .destructive) { isConfirmingSignOut = true }
            Button(role: .destructive) { isConfirmingDelete = true } label: {
                if model.isDeleting { ProgressView() } else { Text("delete account") }
            }
        } footer: {
            Text("@\(model.draft.username.username) · \(model.draft.email)")
        }
    }
}

/// Freshly picked photo, or the saved avatar.
private struct SettingsAvatar: View {
    let image: UIImage?
    let url: URL?
    let name: String

    var body: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            UserAvatar(url: url, name: name, size: 96)
        }
    }
}

/// Handle (+ optional follower count) row in the socials section.
private struct SocialField: View {
    let name: String
    @Binding var handle: String
    var followers: Binding<Int>?

    var body: some View {
        VStack(alignment: .leading, spacing: TappedSpacing.xs) {
            LabeledContent(name) {
                TextField("handle", text: $handle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            if let followers {
                LabeledContent("followers") {
                    TextField("0", value: followers, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private extension Binding where Value == String? {
    var orEmpty: Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

#Preview {
    let dependencies = Dependencies.mock(signedIn: true)
    NavigationStack {
        SettingsView(dependencies: dependencies, currentUser: Samples.performer)
    }
    .environment(Router())
    .environment(AppSession(dependencies: dependencies))
}
