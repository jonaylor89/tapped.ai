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
        now: Date = Date(timeIntervalSince1970: 1_700_000_123.456)
    ) -> OnboardingViewModel {
        let dependencies = Dependencies(
            mode: .mock,
            auth: MockAuthRepository(signedInAs: MockAuthRepository.newUser),
            database: database,
            search: MockSearchRepository(),
            places: MockPlacesRepository(),
            purchases: MockPurchasesRepository(),
            analytics: MockAnalytics(),
            remoteConfig: MockRemoteConfigRepository(),
            storage: MockStorageRepository(),
            location: location
        )
        return OnboardingViewModel(dependencies: dependencies, now: { now })
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

    @Test func fourStepsInOrder() {
        #expect(OnboardingViewModel.Step.allCases == [.name, .occupation, .genres, .location])
        #expect(OnboardingViewModel.stepCount == 4)
        #expect(OnboardingViewModel.Step.location.isLast)
        #expect(OnboardingViewModel.Step.allCases.allSatisfy { !$0.subtitle.isEmpty })
        #expect(OnboardingViewModel.Step.genres.subtitle == "we use these to match you with gigs and venues.")
    }

    @Test func defaults() {
        let model = makeModel()
        #expect(model.step == .name)
        #expect(model.stepNumber == 1)
        #expect(model.progress == 0.25)
        #expect(model.role == .performer)
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
        #expect(model.step == .occupation)
        #expect(model.canContinue, "performer is pre-selected")
        model.next()
        #expect(model.step == .genres)
        #expect(!model.canContinue)

        model.toggle(genre: .electronic)
        #expect(model.skip() == false)
        #expect(model.genres.isEmpty)
        #expect(model.step == .location)
        #expect(model.stepNumber == 4)
        #expect(model.skip() == true, "skipping the last step finishes")
        model.back()
        #expect(model.step == .genres)
        #expect(model.progress == 3.0 / 4.0)
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

    @Test(arguments: [
        (OnboardingViewModel.Role.performer, "Performer"),
        (.venue, "Venue"),
        (.promoter, "Concert Promoter"),
    ])
    func roleWritesOccupation(role: OnboardingViewModel.Role, occupation: String) async throws {
        let model = makeModel()
        model.artistName = "Nova"
        model.role = role
        let user = try #require(await model.finish())
        #expect(user.occupations == [occupation])
    }

    @Test func skippedStepsWriteDefaults() async throws {
        let model = makeModel()
        model.artistName = "Nova"
        model.next()
        model.next()
        model.skip()
        #expect(model.skip())
        let user = try #require(await model.finish())
        #expect(user.location == nil)
        #expect(user.performerInfo?.genres == [])
    }
}
