import Foundation
import TappedData
import TappedDomain
import Testing
@testable import Tapped

@MainActor
@Suite("Onboarding")
struct OnboardingViewModelTests {
    private func makeModel(
        database: MockDatabaseRepository = MockDatabaseRepository(),
        location: MockLocationRepository = MockLocationRepository(),
        places: any PlacesRepository = MockPlacesRepository(),
        storage: MockStorageRepository = MockStorageRepository(),
        now: Date = Date(timeIntervalSince1970: 1_700_000_123.456),
        downloadImage: @escaping @Sendable (URL) async throws -> Data = { _ in Data([0xFF, 0xD8]) }
    ) -> OnboardingViewModel {
        let dependencies = Dependencies(
            mode: .mock,
            auth: MockAuthRepository(signedInAs: MockAuthRepository.newUser),
            database: database,
            search: MockSearchRepository(),
            places: places,
            purchases: MockPurchasesRepository(),
            analytics: MockAnalytics(),
            remoteConfig: MockRemoteConfigRepository(),
            storage: storage,
            location: location,
            spotify: MockSpotifyRepository()
        )
        return OnboardingViewModel(dependencies: dependencies, now: { now }, downloadImage: downloadImage)
    }

    @Test(arguments: [
        ("DJ Nova", "dj_nova"),
        ("  Nova   Waves ", "nova_waves"),
        ("Beyoncé & Jay-Z!", "beyonc__jayz"),
        ("A.B_c 1", "ab_c_1"),
        ("🎸", ""),
    ])
    func sanitizesUsernamesLikeFlutter(input: String, expected: String) {
        #expect(OnboardingViewModel.sanitizeUsername(input) == expected)
    }

    @Test func threeStepsInOrder() {
        #expect(OnboardingViewModel.Step.allCases == [.name, .genres, .location])
        #expect(OnboardingViewModel.stepCount == 3)
        #expect(OnboardingViewModel.Step.location.isLast)
        #expect(OnboardingViewModel.Step.allCases.allSatisfy { !$0.subtitle.isEmpty })
        #expect(OnboardingViewModel.Step.genres.subtitle == "we use these to match you with gigs and venues.")
    }

    @Test func defaults() {
        let model = makeModel()
        #expect(model.step == .name)
        #expect(model.stepNumber == 1)
        #expect(model.progress == 1.0 / 3.0)
        #expect(model.genres.isEmpty)
        #expect(model.selectedPlace == nil)
        #expect(!model.isUsernameCustom)
        #expect(!model.canGoBack)
    }

    @Test func requiredStepsBlockContinueAndOptionalStepsSkip() {
        let model = makeModel()
        #expect(!model.canContinue)
        #expect(!model.step.isSkippable)
        model.skip()
        #expect(model.step == .name)

        model.artistName = "!!!"
        #expect(model.nameError == "use at least one letter or number")
        model.artistName = "Nova Waves"
        #expect(model.canContinue)
        model.next()
        #expect(model.step == .genres)
        #expect(!model.canContinue)

        model.toggle(genre: .electronic)
        #expect(model.skip() == false)
        #expect(model.genres.isEmpty)
        #expect(model.step == .location)
        #expect(model.stepNumber == 3)
        #expect(model.skip() == true, "skipping the last step finishes")
        model.back()
        #expect(model.step == .genres)
        #expect(model.progress == 2.0 / 3.0)
    }

    @Test func usernameFollowsNameUntilTyped() async {
        let model = makeModel()
        model.artistName = "Nova Waves"
        #expect(model.username == "nova_waves")
        model.customUsername = "Nova.Waves "
        #expect(model.customUsername == "novawaves_")
        #expect(model.isUsernameCustom)
        model.artistName = "Someone Else"
        #expect(model.username == "novawaves_")
        await model.checkUsername()
        #expect(model.usernameStatus == .available("novawaves_"))
    }

    @Test func takenUsernameGetsEpochSuffix() async throws {
        let model = makeModel()
        model.artistName = "DJNova"
        await model.checkUsername()
        #expect(model.usernameStatus == .taken("djnova"))
        #expect(model.usernameError == nil, "a derived username is suffixed, not blocked")
        // 1_700_000_123_456 ms → last four digits "3456".
        #expect(await model.resolveUsername() == "djnova3456")
    }

    @Test func takenCustomUsernameBlocksContinue() async {
        let model = makeModel()
        model.artistName = "Nova"
        model.customUsername = "djnova"
        await model.checkUsername()
        #expect(model.usernameError == "@djnova is taken")
        #expect(!model.canContinue)
        #expect(await model.resolveUsername() == nil)
    }

    @Test func currentCityReverseGeocodesToPlace() async {
        let model = makeModel()
        await model.useCurrentCity()
        #expect(model.selectedPlace?.placeId == Location.rva.placeId)
        #expect(model.selectedPlace?.name == "Richmond")
        #expect(model.errorMessage == nil)
        #expect(!model.isLocating)
    }

    @Test func currentCityMakesOneLocalityLookup() async {
        let places = RecordingPlacesRepository(locality: MockPlacesRepository.places[0])
        let model = makeModel(places: places)
        await model.useCurrentCity()
        #expect(model.selectedPlace == MockPlacesRepository.places[0])
        #expect(places.calls == ["getPlaceByLatLng"])
    }

    @Test func currentCityWithoutLocalityFallsBackToSearch() async {
        let model = makeModel(places: RecordingPlacesRepository(locality: nil))
        await model.useCurrentCity()
        #expect(model.selectedPlace == nil)
        #expect(model.errorMessage == "couldn't find your city. search for it instead")
        #expect(!model.isLocating)
    }

    @Test func currentCityDeniedFallsBackToSearch() async {
        let model = makeModel(location: MockLocationRepository(result: .failure(.denied)))
        await model.useCurrentCity()
        #expect(model.selectedPlace == nil)
        #expect(model.errorMessage == "location access is off. search for your city instead")
    }

    @Test func finishWritesUserModel() async throws {
        let database = MockDatabaseRepository()
        let model = makeModel(database: database)
        model.artistName = "  Nova Waves "
        model.toggle(genre: .pop)
        model.toggle(genre: .electronic)
        model.placeQuery = "rich"
        await model.searchPlaces()
        await model.select(try #require(model.placePredictions.first))

        let user = try #require(await model.finish())
        let saved = try #require(try await database.getUserById(MockAuthRepository.newUser.uid))
        #expect(saved == user)
        #expect(user.id == MockAuthRepository.newUser.uid)
        #expect(user.username.username == "nova_waves")
        #expect(user.artistName == "Nova Waves")
        #expect(user.email == MockAuthRepository.newUser.email)
        #expect(user.timestamp == Date(timeIntervalSince1970: 1_700_000_123.456))
        #expect(user.occupations == ["Performer"])
        #expect(user.performerInfo?.genres == ["pop", "electronic"])
        #expect(user.location == Location.rva)
        // Photo and socials moved to the "finish setting up" checklist: Flutter's defaults.
        #expect(user.profilePicture == nil)
        #expect(user.socialFollowing == .empty)
        #expect(user.socialFollowing.tiktokHandle == nil)
        #expect(user.socialFollowing.tiktokFollowers == 0)
        #expect(user.socialFollowing.instagramHandle == nil)
        #expect(user.socialFollowing.instagramFollowers == 0)
    }

    @Test func skippedStepsWriteDefaults() async throws {
        let model = makeModel()
        model.artistName = "Nova"
        model.next()
        model.skip()
        #expect(model.skip())
        let user = try #require(await model.finish())
        #expect(user.location == nil)
        #expect(user.performerInfo?.genres == [])
    }

    // MARK: - spotify

    private static let artistLink = "https://open.spotify.com/intl-de/artist/4Z8W4fKeB5YxbusRsdQVPb?si=abc123"

    @Test func spotifyImportFillsNameAndMatchingGenres() async {
        let model = makeModel()
        model.toggle(genre: .rock)
        model.spotifyLink = Self.artistLink
        await model.importFromSpotify()
        #expect(model.spotifyArtist?.id == "4Z8W4fKeB5YxbusRsdQVPb")
        #expect(model.artistName == "Nova Waves")
        #expect(model.username == "nova_waves")
        #expect(model.genres == [.rock, .electronic], "keeps picked genres and adds the ones Tapped has")
        #expect(model.spotifyLink.isEmpty)
        #expect(model.spotifyError == nil)
        #expect(!model.isImportingSpotify)

        model.clearSpotify()
        #expect(model.spotifyArtist == nil)
        #expect(model.artistName == "Nova Waves")
    }

    @Test(arguments: [
        ("not a link", "paste the link to your artist page on spotify"),
        ("https://open.spotify.com/track/4Z8W4fKeB5YxbusRsdQVPb", "paste the link to your artist page on spotify"),
        ("https://open.spotify.com/artist/0000000000000000000000", "couldn't find that artist on spotify"),
    ])
    func spotifyImportErrors(link: String, error: String) async {
        let model = makeModel()
        model.spotifyLink = link
        await model.importFromSpotify()
        #expect(model.spotifyArtist == nil)
        #expect(model.spotifyError == error)
        #expect(model.artistName.isEmpty)
    }

    @Test func spotifyGenreMatchingIgnoresCaseAndSpacing() {
        #expect(OnboardingViewModel.genres(fromSpotify: ["Hip Hop", "r&b", "ELECTRONIC", "indietronica"]) == [.hipHop, .rnb, .electronic])
        #expect(OnboardingViewModel.genres(fromSpotify: []).isEmpty)
    }

    @Test func finishSavesSpotifyIdAndPhoto() async throws {
        let storage = MockStorageRepository()
        let model = makeModel(storage: storage)
        model.spotifyLink = Self.artistLink
        await model.importFromSpotify()

        let user = try #require(await model.finish())
        #expect(user.socialFollowing.spotifyId == "4Z8W4fKeB5YxbusRsdQVPb")
        #expect(user.socialFollowing.spotifyMonthlyListeners == 0)
        let picture = try #require(user.profilePicture.flatMap(URL.init(string:)))
        #expect(await storage.uploads[picture.path] == Data([0xFF, 0xD8]))
    }

    @Test func spotifyPhotoFailureStillFinishes() async throws {
        let model = makeModel(downloadImage: { _ in throw URLError(.notConnectedToInternet) })
        model.spotifyLink = Self.artistLink
        await model.importFromSpotify()
        let user = try #require(await model.finish())
        #expect(user.profilePicture == nil)
        #expect(user.socialFollowing.spotifyId == "4Z8W4fKeB5YxbusRsdQVPb")
    }
}

/// Records which `PlacesRepository` calls a view model makes.
private final class RecordingPlacesRepository: PlacesRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private let locality: PlaceData?

    init(locality: PlaceData?) { self.locality = locality }

    var calls: [String] { lock.withLock { recorded } }

    private func record(_ call: String) { lock.withLock { recorded.append(call) } }

    func searchPlace(_ query: String) async throws -> [AutocompletePrediction] { record("searchPlace"); return [] }
    func getPlaceById(_ placeId: String) async throws -> PlaceData? { record("getPlaceById"); return locality }
    func getPhotoUrl(photoName: String, maxHeightPx: Int) async throws -> URL? { record("getPhotoUrl"); return nil }
    func getPlaceIdByLatLng(lat: Double, lng: Double) async throws -> String? { record("getPlaceIdByLatLng"); return locality?.placeId }
    func getPlaceByLatLng(lat: Double, lng: Double) async throws -> PlaceData? { record("getPlaceByLatLng"); return locality }
}
