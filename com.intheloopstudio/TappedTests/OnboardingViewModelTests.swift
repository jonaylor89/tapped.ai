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
        storage: MockStorageRepository = MockStorageRepository(),
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
            storage: storage
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

    @Test func requiredStepsBlockContinueAndOptionalStepsSkip() {
        let model = makeModel()
        #expect(model.step == .name)
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
        #expect(!model.canContinue)
        model.toggle(occupation: "DJ")
        model.next()
        #expect(model.step == .genres)

        model.toggle(genre: .electronic)
        model.skip()
        #expect(model.genres.isEmpty)
        #expect(model.step == .location)
        model.back()
        #expect(model.step == .genres)
        #expect(model.progress == 3.0 / 7.0)
    }

    @Test func socialsValidation() {
        let model = makeModel()
        model.tiktokHandle = "@nova waves"
        #expect(model.socialsError == "handles can't contain spaces")
        model.tiktokHandle = "@novawaves"
        model.instagramFollowers = "12k"
        #expect(model.socialsError == "follower counts must be whole numbers")
        model.instagramFollowers = "12000"
        #expect(model.socialsError == nil)
        #expect(OnboardingViewModel.sanitizeHandle("@@novawaves ") == "novawaves")
    }

    @Test func finishRequiresEula() async {
        let model = makeModel()
        model.artistName = "Nova Waves"
        #expect(await model.finish() == nil)
        #expect(model.errorMessage == "you must accept the eula to continue")
    }

    @Test func finishWritesUserModel() async throws {
        let database = MockDatabaseRepository()
        let storage = MockStorageRepository()
        let model = makeModel(database: database, storage: storage)
        model.artistName = "  Nova Waves "
        model.toggle(occupation: "Music Producer")
        model.toggle(occupation: "DJ")
        model.toggle(genre: .pop)
        model.toggle(genre: .electronic)
        model.placeQuery = "rich"
        await model.searchPlaces()
        await model.select(try #require(model.placePredictions.first))
        model.tiktokHandle = "@novawaves"
        model.tiktokFollowers = "12400"
        model.instagramHandle = "nova.waves"
        model.setAvatar(Data([0xFF, 0xD8]))
        model.eulaAccepted = true

        let user = try #require(await model.finish())
        let saved = try #require(try await database.getUserById(MockAuthRepository.newUser.uid))
        #expect(saved == user)
        #expect(user.username.username == "nova_waves")
        #expect(user.artistName == "Nova Waves")
        #expect(user.email == MockAuthRepository.newUser.email)
        #expect(user.occupations == ["DJ", "Music Producer"])
        #expect(user.performerInfo?.genres == ["pop", "electronic"])
        #expect(user.location == Location.rva)
        #expect(user.socialFollowing.tiktokHandle == "novawaves")
        #expect(user.socialFollowing.tiktokFollowers == 12400)
        #expect(user.socialFollowing.instagramHandle == "nova.waves")
        #expect(user.socialFollowing.instagramFollowers == 0)
        #expect(user.profilePicture?.contains("images/users/\(MockAuthRepository.newUser.uid)/userProfile_") == true)
        #expect(await storage.uploads.count == 1)
    }

    @Test func takenUsernameGetsEpochSuffix() async throws {
        let model = makeModel()
        model.artistName = "DJNova"
        await model.checkUsername()
        #expect(model.usernameStatus == .taken("djnova"))
        // 1_700_000_123_456 ms → last four digits "3456".
        #expect(await model.resolveUsername() == "djnova3456")
    }
}
