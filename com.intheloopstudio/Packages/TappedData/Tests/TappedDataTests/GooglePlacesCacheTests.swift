import Foundation
import Testing
@testable import TappedData

@Suite("Google Places response cache")
struct GooglePlacesCacheTests {
    @Test func cachesAutocompleteResponsesByQuery() async {
        let cache = GooglePlacesCache()
        let prediction = AutocompletePrediction(placeId: "place-1", fullText: "The Venue", primaryText: "The Venue", secondaryText: "Austin")

        await cache.storeAutocomplete([prediction], for: "the venue")

        let cached = await cache.autocomplete(for: "the venue")
        let missing = await cache.autocomplete(for: "another venue")
        #expect(cached == [prediction])
        #expect(missing == nil)
    }

    @Test func cachesMissingPlaceDetails() async {
        let cache = GooglePlacesCache()

        await cache.storePlace(nil, for: "missing-place")

        let cached = await cache.place(for: "missing-place")
        #expect(cached != nil)
        #expect(cached! == nil)
    }
}

@Suite("Tapped API places proxy")
struct TappedAPIPlacesRepositoryTests {
    @Test func requestsGoThroughTheTappedApiWithFirebaseToken() async throws {
        let repository = TappedAPIPlacesRepository(baseURL: URL(string: "https://api.tapped.ai")!, idToken: { "token" })
        let request = try await repository.makeRequest(
            "app/v1/places/autocomplete",
            queryItems: [URLQueryItem(name: "query", value: "the camel")]
        )
        #expect(request.url?.absoluteString == "https://api.tapped.ai/app/v1/places/autocomplete?query=the%20camel")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    }

    @Test func requiresToken() async {
        let repository = TappedAPIPlacesRepository(baseURL: URL(string: "https://api.tapped.ai")!, idToken: { nil })
        await #expect(throws: PlacesAPIError.notSignedIn) {
            try await repository.searchPlace("richmond")
        }
    }
}
