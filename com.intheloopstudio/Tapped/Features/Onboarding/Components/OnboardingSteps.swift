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
            case .occupation: OccupationStep(model: model)
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

private struct OccupationStep: View {
    @Bindable var model: OnboardingViewModel

    var body: some View {
        Section {
            RoleRow(role: .performer, isSelected: model.role == .performer, prominent: true) { model.role = .performer }
        }
        Section("or are you a…") {
            ForEach([OnboardingViewModel.Role.venue, .promoter]) { role in
                RoleRow(role: role, isSelected: model.role == role, prominent: false) { model.role = role }
            }
        }
    }
}

private struct RoleRow: View {
    let role: OnboardingViewModel.Role
    let isSelected: Bool
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: TappedSpacing.md) {
                Image(systemName: role.systemImage)
                    .font(prominent ? .largeTitle : .title3)
                    .foregroundStyle(TappedColors.accent)
                    .frame(minWidth: prominent ? 48 : 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: TappedSpacing.xs) {
                    Text(role.title)
                        .font(prominent ? .title2.bold() : .headline)
                        .foregroundStyle(.primary)
                    Text(role.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(TappedColors.accent) : AnyShapeStyle(.tertiary))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, prominent ? TappedSpacing.lg : TappedSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(prominent ? prominentBackground : nil)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var prominentBackground: some View {
        RoundedRectangle(cornerRadius: TappedRadius.xl)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .strokeBorder(isSelected ? TappedColors.accent : .clear, lineWidth: 2)
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

#Preview("occupation") {
    let model = OnboardingViewModel(dependencies: .mock(onboarding: true), initialStep: .occupation)
    return NavigationStack { OnboardingStepContent(model: model) }
}

#Preview("location dark") {
    let model = OnboardingViewModel(dependencies: .mock(onboarding: true), initialStep: .location)
    return NavigationStack { OnboardingStepContent(model: model) }
        .preferredColorScheme(.dark)
}
