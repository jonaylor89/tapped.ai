import Foundation
import TappedDomain
import Testing
@testable import TappedData

@Suite("Mock repositories + dependency resolution")
struct MockRepositoryTests {
    @Test func mockAuthEmitsStateChanges() async throws {
        let auth = MockAuthRepository()
        var iterator = auth.authStateChanges().makeAsyncIterator()
        #expect(await iterator.next() == .some(nil))
        _ = try await auth.signInWithCredentials(email: "a@b.com", password: "pw")
        let signedIn = await iterator.next()
        #expect(signedIn??.email == "a@b.com")
        try await auth.logout()
        #expect(await iterator.next() == .some(nil))
    }

    @Test func mockAuthRejectsWrongPassword() async {
        await #expect(throws: AuthError.invalidCredentials) {
            _ = try await MockAuthRepository().signInWithCredentials(email: "a@b.com", password: "wrong")
        }
    }

    @Test func deleteUserRemovesTheUser() async throws {
        let database = MockDatabaseRepository()
        let userId = Samples.performer.id
        #expect(try await database.getUserById(userId) != nil)
        try await database.deleteUser(userId)
        #expect(try await database.getUserById(userId) == nil)
    }

    @Test func classifyPerformerWeighsBookedVenueCapacities() async throws {
        let now = Date.now
        let performer = Samples.performer
        var bigVenue = Samples.venues[0]
        bigVenue.venueInfo?.capacity = 2000
        var noCapacityVenue = Samples.venues[1]
        noCapacityVenue.venueInfo?.capacity = nil
        func booking(_ id: String, requesterId: String?) -> Booking {
            var booking = Samples.bookings[0]
            booking.id = id
            booking.requesteeId = performer.id
            booking.requesterId = requesterId
            booking.startTime = now.addingTimeInterval(-24 * 60 * 60)
            return booking
        }
        let database = MockDatabaseRepository(
            users: [performer, bigVenue, noCapacityVenue],
            bookings: [
                booking("big", requesterId: bigVenue.id),
                booking("no-capacity", requesterId: noCapacityVenue.id),
                booking("no-requester", requesterId: nil),
            ]
        )
        let expected = PerformerClassification.categorizeWithWeightedDate(
            audience: performer.socialFollowing.audienceSize,
            capacities: [.init(capacity: 2000, startTime: now)],
            now: now
        )
        #expect(expected == .mainstream)
        #expect(try await database.classifyPerformer(performer.id) == expected)
        #expect(try await MockDatabaseRepository(users: [performer], bookings: []).classifyPerformer(performer.id) == .undiscovered)
        #expect(try await database.classifyPerformer("missing") == nil)
    }

    @Test func mockFunctionsRecordsVenueNotifications() async throws {
        let functions = MockFunctionsRepository()
        try await functions.notifyVenueOfInterestedOpportunities(opportunityIds: ["a", "b"], userId: "me", note: "hi")
        #expect(await functions.venueNotifications == [.init(opportunityIds: ["a", "b"], userId: "me", note: "hi")])
    }

    @Test func mockSearchFiltersVenuesByBoundsAndGenre() async throws {
        let search = MockSearchRepository()
        let bounds = GeoBounds(swLatitude: 37.4, swLongitude: -77.6, neLatitude: 37.7, neLongitude: -77.3)
        let all = try await search.queryUsersInBoundingBox("", bounds: bounds, filters: .venues())
        #expect(all.count == Samples.venues.count)
        let jazz = try await search.queryUsersInBoundingBox("", bounds: bounds, filters: .venues(genres: [Genre.jazz.rawValue]))
        #expect(!jazz.isEmpty)
        #expect(jazz.allSatisfy { $0.venueInfo?.genres.contains(Genre.jazz.rawValue) == true })
        let nowhere = GeoBounds(swLatitude: 0, swLongitude: 0, neLatitude: 1, neLongitude: 1)
        #expect(try await search.queryUsersInBoundingBox("", bounds: nowhere, filters: .venues()).isEmpty)
    }

    @Test func modeResolution() {
        #expect(Dependencies.resolveMode(environment: ["TAPPED_MOCK": "1"], hasFirebaseConfig: true) == .mock)
        #expect(Dependencies.resolveMode(environment: [:], hasFirebaseConfig: false) == .mock)
        #expect(Dependencies.resolveMode(environment: [:], hasFirebaseConfig: true) == .live)
    }

    @Test func mockPurchasesGrantPremium() async throws {
        let purchases = MockPurchasesRepository()
        #expect(await !purchases.isPremium())
        #expect(try await purchases.purchase(productId: "x") == .purchased)
        #expect(await purchases.isPremium())
    }

    @Test func mockSignUpCreatesUnverifiedAccount() async throws {
        let auth = MockAuthRepository()
        await #expect(throws: AuthError.weakPassword) {
            try await auth.signUpWithCredentials(email: "new@example.com", password: "123")
        }
        _ = try await auth.signUpWithCredentials(email: "new@example.com", password: "secret1")
        let user = try #require(await auth.getAuthUser())
        #expect(user.requiresEmailVerification)
        try await auth.sendEmailVerification()
        #expect(await auth.verificationEmailsSent == 1)
        #expect(try await auth.reloadUser()?.isEmailVerified == true)
    }

    @Test func providerDrivenVerificationAndReauth() {
        #expect(AuthUser(uid: "a", providerIds: ["password"]).requiresEmailVerification)
        #expect(!AuthUser(uid: "a", providerIds: ["apple.com"]).requiresEmailVerification)
        #expect(!AuthUser(uid: "a", isEmailVerified: true, providerIds: ["password"]).requiresEmailVerification)
        #expect(AuthUser(uid: "a", providerIds: ["google.com", "apple.com"]).reauthMethods == [.apple, .google])
        #expect(AuthUser(uid: "a").reauthMethods == [.password])
    }

    @Test func mockDeviceTokensUseFlutterPath() async throws {
        let notifications = MockNotificationRepository()
        _ = try await notifications.requestAuthorization()
        try await notifications.saveDeviceToken(userId: "u1")
        #expect(await notifications.savedTokens == ["u1": [MockNotificationRepository.sampleToken: "ios"]])
        let denied = MockNotificationRepository(grantsPermission: false)
        try await denied.saveDeviceToken(userId: "u1")
        #expect(await denied.savedTokens.isEmpty)
    }

    @Test func mockWaitlist() async throws {
        let database = MockDatabaseRepository()
        #expect(try await !database.isOnPremiumWailist("u1"))
        try await database.joinPremiumWaitlist("u1")
        #expect(try await database.isOnPremiumWailist("u1"))
    }
}
