import PhotosUI
import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// The `Form` for the current onboarding step.
struct OnboardingStepContent: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        Form {
            OnboardingHeader(title: model.step.title, subtitle: model.step.subtitle)
            switch model.step {
            case .name: NameStep(model: model)
            case .occupation: OccupationStep(model: model)
            case .genres: GenresStep(model: model)
            case .location: LocationStep(model: model)
            case .socials: SocialsStep(model: model)
            case .avatar: AvatarStep(model: model)
            case .complete: CompleteStep(model: model)
            }
        }
        .textCase(nil)
        .scrollDismissesKeyboard(.interactively)
    }
}

struct OnboardingHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        Section {} header: {
            VStack(alignment: .leading, spacing: TappedSpacing.sm) {
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct NameStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        Section {
            TextField("artist name", text: $model.artistName)
                .textContentType(.nickname)
                .autocorrectionDisabled()
                .submitLabel(.continue)
                .onSubmit { model.next() }
        } footer: {
            footer
        }
        .task(id: model.username) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await model.checkUsername()
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let error = model.nameError {
            Text(error).foregroundStyle(TappedColors.error)
        } else if !model.username.isEmpty {
            switch model.usernameStatus {
            case .idle, .checking:
                Text("tapped.ai/u/\(model.username)")
            case let .available(username):
                Label("tapped.ai/u/\(username) is yours", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(TappedColors.success)
            case let .taken(username):
                Text("@\(username) is taken, so we'll add a few numbers to the end")
            }
        }
    }
}

private struct OccupationStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        Section {
            ForEach(Occupation.all) { occupation in
                SelectableRow(title: occupation.rawValue.lowercased(), isSelected: model.occupations.contains(occupation.rawValue)) {
                    model.toggle(occupation: occupation.rawValue)
                }
            }
        } footer: {
            if !model.occupations.isEmpty { Text("\(model.occupations.count) selected") }
        }
    }
}

private struct GenresStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        if !model.genres.isEmpty {
            Section("selected") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TappedSpacing.sm) {
                        ForEach(Genre.allCases.filter(model.genres.contains)) { genre in
                            GlassChip(genre.formattedName.lowercased(), isSelected: true) { model.toggle(genre: genre) }
                        }
                    }
                    .padding(.vertical, TappedSpacing.xs)
                }
            }
        }
        Section {
            TextField("search genres", text: $model.genreQuery)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            ForEach(model.filteredGenres) { genre in
                SelectableRow(title: genre.formattedName.lowercased(), isSelected: model.genres.contains(genre)) {
                    model.toggle(genre: genre)
                }
            }
        }
    }
}

private struct LocationStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        if let place = model.selectedPlace {
            Section("your city") {
                HStack {
                    Label {
                        VStack(alignment: .leading) {
                            Text(place.name.lowercased())
                            if let address = place.shortFormattedAddress {
                                Text(address.lowercased()).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(TappedColors.accent)
                    }
                    Spacer()
                    Button("change", systemImage: "xmark.circle.fill") { model.clearPlace() }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                }
            }
        } else {
            Section {
                TextField("search a city", text: $model.placeQuery)
                    .textContentType(.addressCity)
                    .autocorrectionDisabled()
                ForEach(model.placePredictions) { prediction in
                    Button {
                        Task { await model.select(prediction) }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(prediction.primaryText.lowercased()).foregroundStyle(.primary)
                            Text(prediction.secondaryText.lowercased()).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("powered by google")
            }
            .task(id: model.placeQuery) {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await model.searchPlaces()
            }
        }
    }
}

private struct SocialsStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        Section("tiktok") {
            HandleField(handle: $model.tiktokHandle)
            FollowersField(followers: $model.tiktokFollowers)
        }
        Section {
            HandleField(handle: $model.instagramHandle)
            FollowersField(followers: $model.instagramFollowers)
        } header: {
            Text("instagram")
        } footer: {
            if let error = model.socialsError {
                Text(error).foregroundStyle(TappedColors.error)
            }
        }
    }
}

private struct HandleField: View {
    @Binding var handle: String

    var body: some View {
        LabeledContent {
            TextField("handle", text: $handle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } label: {
            Image(systemName: "at").foregroundStyle(.secondary)
        }
    }
}

private struct FollowersField: View {
    @Binding var followers: String

    var body: some View {
        LabeledContent {
            TextField("followers", text: $followers)
                .keyboardType(.numberPad)
        } label: {
            Image(systemName: "person.2").foregroundStyle(.secondary)
        }
    }
}

private struct AvatarStep: View {
    @Bindable var model: OnboardingViewModel
    @State private var selection: PhotosPickerItem?

    var body: some View {
        Section {
            VStack(spacing: TappedSpacing.lg) {
                OnboardingAvatar(data: model.avatarData, name: model.trimmedArtistName, size: 160)
                PhotosPicker(selection: $selection, matching: .images) {
                    Label(model.avatarData == nil ? "choose a photo" : "change photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.glass)
                if model.avatarData != nil {
                    Button("remove", role: .destructive) {
                        selection = nil
                        model.setAvatar(nil)
                    }
                    .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                model.setAvatar(data.flatMap(OnboardingAvatar.jpeg))
            }
        }
    }
}

/// Picked photo preview; falls back to initials like `UserAvatar`.
struct OnboardingAvatar: View {
    let data: Data?
    let name: String
    let size: CGFloat

    var body: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
        } else {
            UserAvatar(url: nil, name: name.isEmpty ? "?" : name, size: size)
        }
    }

    /// Downscales to 1024pt and re-encodes as JPEG before upload (`image_picker` `imageQuality: 85`).
    static func jpeg(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1024
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

private struct CompleteStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        Section {
            HStack(spacing: TappedSpacing.md) {
                OnboardingAvatar(data: model.avatarData, name: model.trimmedArtistName, size: 64)
                VStack(alignment: .leading, spacing: TappedSpacing.xs) {
                    Text(model.trimmedArtistName.lowercased()).font(.headline)
                    Text("@\(model.username)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if !model.occupations.isEmpty {
                LabeledContent("occupation", value: Occupation.all.map(\.rawValue).filter(model.occupations.contains).joined(separator: ", ").lowercased())
            }
            if !model.genres.isEmpty {
                LabeledContent("genres", value: Genre.allCases.filter(model.genres.contains).map(\.formattedName).joined(separator: ", ").lowercased())
            }
            if let place = model.selectedPlace {
                LabeledContent("location", value: place.name.lowercased())
            }
        }
        Section {
            Toggle(isOn: $model.eulaAccepted) {
                Text("i agree to the [eula](\(OnboardingViewModel.eulaURL.absoluteString))")
            }
            .tint(TappedColors.accent)
        } footer: {
            Text("tapped has no tolerance for objectionable content or abusive users.")
        }
    }
}

/// Checkmark row used by the multi-select steps.
private struct SelectableRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(TappedColors.accent).fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("socials") {
    let model = OnboardingViewModel(dependencies: .mock(onboarding: true), initialStep: .socials)
    model.fillSampleAnswers()
    return NavigationStack { OnboardingStepContent(model: model) }
}

#Preview("location dark") {
    let model = OnboardingViewModel(dependencies: .mock(onboarding: true), initialStep: .location)
    return NavigationStack { OnboardingStepContent(model: model) }
        .preferredColorScheme(.dark)
}
