import Foundation
import Observation
import TappedData
import TappedDomain

/// `onboarding_flow_cubit.dart` + `onboarding_bloc`: four steps (name → what you do → genres → location), then
/// writes `users/{uid}` and lands in the app. Photo and socials live in the "finish setting up" checklist.
@Observable
@MainActor
final class OnboardingViewModel {
    enum Step: String, CaseIterable, Hashable, Sendable {
        case name, occupation, genres, location

        var title: String {
            switch self {
            case .name: "what should we call you?"
            case .occupation: "what do you do?"
            case .genres: "what do you play?"
            case .location: "where are you based?"
            }
        }

        var subtitle: String {
            switch self {
            case .name: "this is how venues and fans see you. your username is your tapped link."
            case .occupation: "we tailor your map, search and gigs to how you work."
            case .genres: "we use these to match you with gigs and venues."
            case .location: "we use your city to show you gigs and venues nearby."
            }
        }

        var isSkippable: Bool {
            switch self {
            case .name, .occupation: false
            case .genres, .location: true
            }
        }

        var isLast: Bool { self == Step.allCases.last }
    }

    /// Step 2. Each role writes one `occupations` entry.
    enum Role: String, CaseIterable, Identifiable, Sendable {
        case performer, venue, promoter

        var id: String { rawValue }

        var occupation: Occupation {
            switch self {
            case .performer: "Performer"
            case .venue: .venue
            case .promoter: "Concert Promoter"
            }
        }

        var title: String { rawValue }

        var subtitle: String {
            switch self {
            case .performer: "dj, band or solo act. find gigs and get booked."
            case .venue: "book acts for your stage."
            case .promoter: "put on shows and find talent."
            }
        }

        var systemImage: String {
            switch self {
            case .performer: "music.mic"
            case .venue: "building.2"
            case .promoter: "megaphone"
            }
        }
    }

    enum UsernameStatus: Equatable {
        case idle, checking
        case available(String)
        /// Taken. A username derived from the name gets a 4-digit suffix like Flutter; a typed one must change.
        case taken(String)
    }

    static let eulaURL = URL(string: "https://tapped.ai/eula")!
    static let privacyURL = URL(string: "https://tapped.ai/privacy")!
    static let artistNameLimit = 50
    static let usernameLimit = 30

    private(set) var step: Step
    var artistName = ""
    /// Empty until the user edits the username field; until then the username follows `artistName`.
    var customUsername = "" {
        didSet {
            let sanitized = Self.sanitizeUsername(customUsername, trimming: false)
            if sanitized != customUsername { customUsername = sanitized }
        }
    }
    private(set) var usernameStatus: UsernameStatus = .idle
    var role: Role = .performer
    private(set) var genres: Set<Genre> = []
    var genreQuery = ""
    var placeQuery = ""
    private(set) var placePredictions: [AutocompletePrediction] = []
    private(set) var selectedPlace: PlaceData?
    private(set) var isLocating = false
    private(set) var isSubmitting = false
    var errorMessage: String?

    private let auth: any AuthRepository
    private let database: any DatabaseRepository
    private let placesSessionToken = UUID().uuidString
    private let places: any PlacesRepository
    private let location: any LocationRepository
    private let analytics: any AnalyticsRepository
    private let now: @Sendable () -> Date

    init(dependencies: Dependencies, initialStep: Step = .name, now: @escaping @Sendable () -> Date = { .now }) {
        auth = dependencies.auth
        database = dependencies.database
        places = dependencies.places
        location = dependencies.location
        analytics = dependencies.analytics
        step = initialStep
        self.now = now
    }

    // MARK: - progress

    static var stepCount: Int { Step.allCases.count }
    var stepIndex: Int { Step.allCases.firstIndex(of: step) ?? 0 }
    var stepNumber: Int { stepIndex + 1 }
    var progress: Double { Double(stepNumber) / Double(Self.stepCount) }
    var canGoBack: Bool { stepIndex > 0 && !isSubmitting }

    var canContinue: Bool {
        guard !isSubmitting else { return false }
        return switch step {
        case .name: nameError == nil && usernameError == nil && !trimmedArtistName.isEmpty && !username.isEmpty
        case .occupation: true
        case .genres: !genres.isEmpty
        case .location: selectedPlace != nil
        }
    }

    func next() {
        guard canContinue, let next = Step.allCases[safe: stepIndex + 1] else { return }
        step = next
        Task { await analytics.track("onboarding_next_question", properties: ["index": .int(stepIndex)]) }
    }

    func back() {
        guard canGoBack else { return }
        step = Step.allCases[stepIndex - 1]
    }

    /// Skipping discards anything half-entered on the step so it isn't saved. Returns `true` when that was the last
    /// step and the caller should `finish()`.
    @discardableResult
    func skip() -> Bool {
        guard step.isSkippable else { return false }
        switch step {
        case .genres: genres = []
        case .location: selectedPlace = nil; placeQuery = ""; placePredictions = []
        case .name, .occupation: break
        }
        guard let next = Step.allCases[safe: stepIndex + 1] else { return true }
        step = next
        return false
    }

    // MARK: - name

    var trimmedArtistName: String { artistName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isUsernameCustom: Bool { !customUsername.isEmpty }
    var username: String { isUsernameCustom ? customUsername : Self.sanitizeUsername(artistName) }

    var nameError: String? {
        if trimmedArtistName.count > Self.artistNameLimit { return "keep it under \(Self.artistNameLimit) characters" }
        if !trimmedArtistName.isEmpty, username.isEmpty { return "use at least one letter or number" }
        return nil
    }

    var usernameError: String? {
        if username.count > Self.usernameLimit { return "usernames can be up to \(Self.usernameLimit) characters" }
        if isUsernameCustom, case let .taken(taken) = usernameStatus, taken == username { return "@\(taken) is taken" }
        return nil
    }

    /// `sanitize_username.dart`: lowercase, whitespace → `_`, drop anything outside `[a-z0-9_]`.
    nonisolated static func sanitizeUsername(_ input: String, trimming: Bool = true) -> String {
        let lowered = (trimming ? input.trimmingCharacters(in: .whitespacesAndNewlines) : input).lowercased()
        let underscored = lowered.replacing(/\s+/, with: "_")
        return underscored.replacing(/[^a-z0-9_]/, with: "")
    }

    func checkUsername() async {
        let candidate = username
        guard !candidate.isEmpty else { usernameStatus = .idle; return }
        usernameStatus = .checking
        let available = await isAvailable(candidate)
        guard candidate == username else { return }
        usernameStatus = available ? .available(candidate) : .taken(candidate)
    }

    private func isAvailable(_ candidate: String) async -> Bool {
        guard let uid = try? await auth.getAuthUserId() else { return false }
        return (try? await database.checkUsernameAvailability(candidate, userId: uid)) ?? false
    }

    /// `_getUsername`: the sanitized name, or the name + last four digits of the epoch millis if taken.
    /// A typed username is used as is; `nil` if someone took it in the meantime.
    func resolveUsername() async -> String? {
        let candidate = username
        if await isAvailable(candidate) { return candidate }
        if isUsernameCustom {
            usernameStatus = .taken(candidate)
            return nil
        }
        let millis = String(Int64(now().timeIntervalSince1970 * 1000))
        return candidate + millis.suffix(4)
    }

    // MARK: - genres

    func toggle(genre: Genre) {
        if genres.contains(genre) { genres.remove(genre) } else { genres.insert(genre) }
    }

    var filteredGenres: [Genre] {
        let query = genreQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Genre.allCases }
        return Genre.allCases.filter { $0.formattedName.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - location

    /// After a `LocationButton` grant: device position → Google reverse geocode (locality) → place details, so the
    /// saved `placeId` is the same kind the city search returns.
    func useCurrentCity() async {
        guard !isLocating else { return }
        isLocating = true
        defer { isLocating = false }
        do {
            let coordinate = try await location.currentCoordinate()
            guard let placeId = try await places.getPlaceIdByLatLng(lat: coordinate.lat, lng: coordinate.lng),
                  let place = try await places.getPlaceById(placeId)
            else { throw LocationError.unavailable }
            selectedPlace = place
            placeQuery = ""
            placePredictions = []
        } catch LocationError.denied {
            errorMessage = "location access is off. search for your city instead"
        } catch {
            errorMessage = "couldn't find your city. search for it instead"
        }
    }

    func searchPlaces() async {
        let query = placeQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { placePredictions = []; return }
        do {
            let results = try await places.searchPlace(query, sessionToken: placesSessionToken)
            guard query == placeQuery.trimmingCharacters(in: .whitespaces) else { return }
            placePredictions = results
        } catch {
            placePredictions = []
        }
    }

    func select(_ prediction: AutocompletePrediction) async {
        do {
            selectedPlace = try await places.getPlaceById(prediction.placeId, sessionToken: placesSessionToken)
            placeQuery = ""
            placePredictions = []
        } catch {
            errorMessage = "couldn't load that place. try another"
        }
    }

    func clearPlace() { selectedPlace = nil }

    // MARK: - finish

    /// `finishOnboarding`: tapping "let's go" accepts the EULA, then writes `users/{uid}`. Returns the saved user.
    /// Fields Flutter collected in steps that moved to the checklist keep `UserModel.empty` defaults: no
    /// `profilePicture`, no social handles, follower counts `0`.
    func finish() async -> UserModel? {
        guard !isSubmitting else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            guard let authUser = await auth.getAuthUser() else { throw AuthError.notSignedIn }
            guard let username = await resolveUsername() else {
                step = .name
                errorMessage = "@\(self.username) was just taken. pick another username"
                return nil
            }
            let user = UserModel(
                id: authUser.uid,
                timestamp: now(),
                username: Username(username),
                email: authUser.email ?? "",
                artistName: trimmedArtistName,
                occupations: [role.occupation.rawValue],
                location: selectedPlace.map { Location(placeId: $0.placeId, lat: $0.lat, lng: $0.lng) },
                performerInfo: PerformerInfo(genres: Genre.allCases.filter(genres.contains).map(\.rawValue)),
                socialFollowing: .empty
            )
            try await database.createUser(user)
            await analytics.track("onboarding_complete", properties: [
                "username": .string(username),
                "occupations": .string(user.occupations.joined(separator: ",")),
                "role": .string(role.rawValue),
                "eula_accepted": .bool(true),
            ])
            return user
        } catch {
            errorMessage = "couldn't save your profile. \(error.localizedDescription.lowercased())"
            return nil
        }
    }

    // MARK: - previews / screenshots

    /// Sample answers so previews and `TAPPED_MOCK_ONBOARDING_STEP` screenshots show a filled-in step. The location
    /// step shows the current-city button above a typed search instead of a picked city.
    func fillSampleAnswers() {
        artistName = "Nova Waves"
        usernameStatus = .available(username)
        role = .performer
        genres = [.electronic, .dance, .pop]
        if step == .location {
            placeQuery = "Rich"
        } else {
            selectedPlace = MockPlacesRepository.places.first
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
