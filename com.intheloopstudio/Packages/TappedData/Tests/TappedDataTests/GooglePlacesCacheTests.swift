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
