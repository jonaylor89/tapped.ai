import CoreLocationUI
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
            case .genres: GenresStep(model: model)
            case .location: LocationStep(model: model)
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
                    .foregroundStyle(Color(uiColor: .label))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct NameStep: View {
    private enum Field: Hashable { case name, username }

    @Bindable var model: OnboardingViewModel
    @FocusState private var focus: Field?

    var body: some View {
        SpotifyImportSection(model: model)
        Section {
            TextField("display name", text: $model.artistName)
                .textContentType(.nickname)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focus, equals: .name)
                .onSubmit { focus = .username }
        } header: {
            Text("display name")
        } footer: {
            if let error = model.nameError {
                Text(error).foregroundStyle(TappedColors.error)
            }
        }
        Section {
            LabeledContent {
                TextField(model.isUsernameCustom ? "username" : (model.username.isEmpty ? "username" : model.username), text: $model.customUsername)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($focus, equals: .username)
                    .onSubmit { model.next() }
            } label: {
                Image(systemName: "at").foregroundStyle(.secondary).accessibilityHidden(true)
            }
        } header: {
            Text("username")
        } footer: {
            usernameFooter
        }
        .task(id: model.username) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await model.checkUsername()
        }
        .onAppear { if model.artistName.isEmpty { focus = .name } }
    }

    @ViewBuilder
    private var usernameFooter: some View {
        if let error = model.usernameError {
            Text(error).foregroundStyle(TappedColors.error)
        } else if !model.username.isEmpty {
            switch model.usernameStatus {
            case .idle, .checking:
                Text(verbatim: "tapped.ai/u/\(model.username)")
            case let .available(username):
                Label("tapped.ai/u/\(username) is yours", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(TappedColors.success)
            case let .taken(username):
                Text("@\(username) is taken, so we'll add a few numbers to the end. or type your own.")
            }
        } else {
            Text("we'll make one from your name. you can type your own.")
        }
    }
}

/// `onboard_with_spotify_view.dart`: paste an artist link to prefill the name, photo and genres.
private struct SpotifyImportSection: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var photoSize: CGFloat = 44

    private var canImport: Bool {
        !model.isImportingSpotify && !model.spotifyLink.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Section {
            if let artist = model.spotifyArtist {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: TappedSpacing.sm) {
                        HStack {
                            photo(artist)
                            Spacer()
                            removeButton
                        }
                        artistLabels(artist)
                    }
                } else {
                    HStack(spacing: TappedSpacing.md) {
                        photo(artist)
                        artistLabels(artist)
                        Spacer()
                        removeButton
                    }
                }
            } else {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: TappedSpacing.sm))
                    : AnyLayout(HStackLayout())
                layout {
                    TextField("open.spotify.com/artist/…", text: $model.spotifyLink)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(importArtist)
                    if model.isImportingSpotify {
                        ProgressView()
                    } else {
                        Button("import", action: importArtist)
                            .fontWeight(.semibold)
                            .disabled(!canImport)
                    }
                }
            }
        } header: {
            Label("on spotify?", systemImage: "waveform")
        } footer: {
            if let error = model.spotifyError {
                Text(error).foregroundStyle(TappedColors.error)
            } else if model.spotifyArtist == nil {
                Text("paste your artist link to fill in your name, photo and genres.")
            }
        }
    }

    private func photo(_ artist: SpotifyArtist) -> some View {
        RemoteImage(url: artist.imageURL) {
            Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
        }
        .frame(width: min(photoSize, 88), height: min(photoSize, 88))
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private func artistLabels(_ artist: SpotifyArtist) -> some View {
        VStack(alignment: .leading) {
            Text(verbatim: artist.name)
            Text("imported from spotify").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var removeButton: some View {
        Button("remove spotify", systemImage: "xmark.circle.fill") { model.clearSpotify() }
            .labelStyle(.iconOnly)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
    }

    private func importArtist() {
        guard canImport else { return }
        Task { await model.importFromSpotify() }
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
                            Text(verbatim: place.name)
                            if let address = place.shortFormattedAddress {
                                Text(verbatim: address).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(TappedColors.accent)
                    }
                    Spacer()
                    Button("change city", systemImage: "xmark.circle.fill") { model.clearPlace() }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                }
            }
        } else {
            Section {
                CurrentCityButton(model: model)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("one tap. we only use it to find your city.")
            }
            Section {
                TextField("or search a city", text: $model.placeQuery)
                    .textContentType(.addressCity)
                    .autocorrectionDisabled()
                ForEach(model.placePredictions) { prediction in
                    Button {
                        Task { await model.select(prediction) }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(verbatim: prediction.primaryText).foregroundStyle(.primary)
                            Text(verbatim: prediction.secondaryText).font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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

/// `CoreLocationUI` `LocationButton` (`CLLocationButton`): a one-time location grant without a permission alert.
private struct CurrentCityButton: View {
    let model: OnboardingViewModel

    var body: some View {
        ZStack {
            LocationButton(.currentLocation) {
                Task { await model.useCurrentCity() }
            }
            .symbolVariant(.fill)
            .labelStyle(.titleAndIcon)
            .font(.headline)
            .foregroundStyle(.white)
            .tint(TappedColors.accent)
            .clipShape(Capsule())
            // The system only grants location if the button is fully legible, so it can't be clipped at AX sizes.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(maxWidth: .infinity)
            .opacity(model.isLocating ? 0 : 1)
            if model.isLocating {
                ProgressView("finding your city…")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }
}

/// Checkmark row used by the multi-select genres step.
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
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("location dark") {
    let model = OnboardingViewModel(dependencies: .mock(onboarding: true), initialStep: .location)
    return NavigationStack { OnboardingStepContent(model: model) }
        .preferredColorScheme(.dark)
}
