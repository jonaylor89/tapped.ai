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

    @Test func unimplementedMethodsThrowNotImplemented() async {
        let database = MockDatabaseRepository()
        await #expect(throws: NotImplemented.self) { try await database.deleteUser("x") }
        await #expect(throws: NotImplemented.self) { try await FirestoreDatabaseRepository().createBooking(Samples.bookings[0]) }
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
