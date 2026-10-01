import Foundation
import Observation
import TappedData
import TappedDomain

/// `onboarding_flow_cubit.dart` + `onboarding_bloc`: collects the profile a new account needs and writes
/// `users/{uid}`. Steps after `occupation` are optional and can be skipped, like the Flutter flow.
@Observable
@MainActor
final class OnboardingViewModel {
    enum Step: String, CaseIterable, Hashable, Sendable {
        case name, occupation, genres, location, socials, avatar, complete

        var title: String {
            switch self {
            case .name: "what should we call you?"
            case .occupation: "what do you do?"
            case .genres: "what do you play?"
            case .location: "where are you based?"
            case .socials: "where do fans find you?"
            case .avatar: "add a profile photo"
            case .complete: "you're all set"
            }
        }

        var subtitle: String {
            switch self {
            case .name: "your artist name is how bookers and venues see you. we'll make your username from it."
            case .occupation: "pick everything that fits. you can change this later."
            case .genres: "venues use genres to find acts for their shows."
            case .location: "we'll show you venues and gigs nearby."
            case .socials: "follower counts help venues gauge your draw."
            case .avatar: "profiles with a photo get more bookings."
            case .complete: "review your profile and accept the eula to get started."
            }
        }

        var isSkippable: Bool {
            switch self {
            case .name, .occupation, .complete: false
            case .genres, .location, .socials, .avatar: true
            }
        }
    }

    enum UsernameStatus: Equatable {
        case idle, checking
        case available(String)
        /// Taken; onboarding will append a 4-digit suffix like Flutter.
        case taken(String)
    }

    static let eulaURL = URL(string: "https://tapped.ai/eula")!
    static let artistNameLimit = 50

    private(set) var step: Step
    var artistName = ""
    private(set) var usernameStatus: UsernameStatus = .idle
    private(set) var occupations: Set<String> = []
    private(set) var genres: Set<Genre> = []
    var genreQuery = ""
    var placeQuery = ""
    private(set) var placePredictions: [AutocompletePrediction] = []
    private(set) var selectedPlace: PlaceData?
    var tiktokHandle = ""
    var tiktokFollowers = ""
    var instagramHandle = ""
    var instagramFollowers = ""
    private(set) var avatarData: Data?
    var eulaAccepted = false
    private(set) var isSubmitting = false
    var errorMessage: String?

    private let auth: any AuthRepository
    private let database: any DatabaseRepository
    private let placesSessionToken = UUID().uuidString
    private let places: any PlacesRepository
    private let storage: any StorageRepository
    private let analytics: any AnalyticsRepository
    private let now: @Sendable () -> Date

    init(dependencies: Dependencies, initialStep: Step = .name, now: @escaping @Sendable () -> Date = { .now }) {
        auth = dependencies.auth
        database = dependencies.database
        places = dependencies.places
        storage = dependencies.storage
        analytics = dependencies.analytics
        step = initialStep
        self.now = now
    }

    // MARK: - progress

    var stepIndex: Int { Step.allCases.firstIndex(of: step) ?? 0 }
    var progress: Double { Double(stepIndex + 1) / Double(Step.allCases.count) }
    var canGoBack: Bool { stepIndex > 0 && !isSubmitting }

    var canContinue: Bool {
        guard !isSubmitting else { return false }
        return switch step {
        case .name: nameError == nil && !username.isEmpty
        case .occupation: !occupations.isEmpty
        case .genres: !genres.isEmpty
        case .location: selectedPlace != nil
        case .socials: socialsError == nil
        case .avatar: avatarData != nil
        case .complete: eulaAccepted
        }
    }

    func next() {
        guard canContinue, let next = Step.allCases[safe: stepIndex + 1] else { return }
        step = next
    }

    func back() {
        guard canGoBack else { return }
        step = Step.allCases[stepIndex - 1]
    }

    /// Skipping discards anything half-entered on the step so it isn't saved.
    func skip() {
        guard step.isSkippable, let next = Step.allCases[safe: stepIndex + 1] else { return }
        switch step {
        case .genres: genres = []
        case .location: selectedPlace = nil; placeQuery = ""; placePredictions = []
        case .socials: tiktokHandle = ""; tiktokFollowers = ""; instagramHandle = ""; instagramFollowers = ""
        case .avatar: avatarData = nil
        case .name, .occupation, .complete: break
        }
        step = next
    }

    // MARK: - name

    var trimmedArtistName: String { artistName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var username: String { Self.sanitizeUsername(artistName) }

    var nameError: String? {
        if trimmedArtistName.isEmpty { return nil }
        if trimmedArtistName.count > Self.artistNameLimit { return "keep it under \(Self.artistNameLimit) characters" }
        if username.isEmpty { return "use at least one letter or number" }
        return nil
    }

    /// `sanitize_username.dart`: lowercase, whitespace → `_`, drop anything outside `[a-z0-9_]`.
    nonisolated static func sanitizeUsername(_ input: String) -> String {
        let lowered = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
    func resolveUsername() async -> String {
        let candidate = username
        if await isAvailable(candidate) { return candidate }
        let millis = String(Int64(now().timeIntervalSince1970 * 1000))
        return candidate + millis.suffix(4)
    }

    // MARK: - occupation / genres

    func toggle(occupation: String) {
        if occupations.contains(occupation) { occupations.remove(occupation) } else { occupations.insert(occupation) }
    }

    func toggle(genre: Genre) {
        if genres.contains(genre) { genres.remove(genre) } else { genres.insert(genre) }
    }

    var filteredGenres: [Genre] {
        let query = genreQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Genre.allCases }
        return Genre.allCases.filter { $0.formattedName.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - location

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

    // MARK: - socials

    nonisolated static func sanitizeHandle(_ handle: String) -> String {
        var trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("@") { trimmed.removeFirst() }
        return trimmed
    }

    var socialsError: String? {
        for handle in [tiktokHandle, instagramHandle] where Self.sanitizeHandle(handle).contains(where: \.isWhitespace) {
            return "handles can't contain spaces"
        }
        for followers in [tiktokFollowers, instagramFollowers] where !followers.isEmpty && Int(followers) == nil {
            return "follower counts must be whole numbers"
        }
        return nil
    }

    // MARK: - avatar

    func setAvatar(_ data: Data?) { avatarData = data }

    // MARK: - finish

    /// `finishOnboarding`: requires the EULA, then writes `users/{uid}`. Returns the saved user.
    func finish() async -> UserModel? {
        guard eulaAccepted else {
            errorMessage = "you must accept the eula to continue"
            return nil
        }
        guard !isSubmitting else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            guard let authUser = await auth.getAuthUser() else { throw AuthError.notSignedIn }
            let username = await resolveUsername()
            var profilePicture: String?
            if let avatarData {
                profilePicture = try await storage.uploadProfilePicture(userId: authUser.uid, imageData: avatarData).absoluteString
            }
            let user = UserModel(
                id: authUser.uid,
                timestamp: now(),
                username: Username(username),
                email: authUser.email ?? "",
                artistName: trimmedArtistName,
                profilePicture: profilePicture,
                occupations: Occupation.all.map(\.rawValue).filter(occupations.contains),
                location: selectedPlace.map { Location(placeId: $0.placeId, lat: $0.lat, lng: $0.lng) },
                performerInfo: PerformerInfo(genres: Genre.allCases.filter(genres.contains).map(\.rawValue)),
                socialFollowing: SocialFollowing(
                    tiktokHandle: Self.sanitizeHandle(tiktokHandle).nilIfEmpty,
                    tiktokFollowers: Int(tiktokFollowers) ?? 0,
                    instagramHandle: Self.sanitizeHandle(instagramHandle).nilIfEmpty,
                    instagramFollowers: Int(instagramFollowers) ?? 0
                )
            )
            try await database.createUser(user)
            await analytics.track("onboarding_complete", properties: [
                "username": .string(username),
                "occupations": .string(user.occupations.joined(separator: ",")),
            ])
            return user
        } catch {
            errorMessage = "couldn't save your profile. \(error.localizedDescription.lowercased())"
            return nil
        }
    }

    // MARK: - previews / screenshots

    /// Sample answers so previews and `TAPPED_MOCK_ONBOARDING_STEP` screenshots show a filled-in step.
    func fillSampleAnswers() {
        artistName = "Nova Waves"
        usernameStatus = .available(username)
        occupations = ["DJ", "Music Producer"]
        genres = [.electronic, .dance, .pop]
        selectedPlace = MockPlacesRepository.places.first
        tiktokHandle = "novawaves"
        tiktokFollowers = "12400"
        instagramHandle = "nova.waves"
        instagramFollowers = "8300"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
