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
}
