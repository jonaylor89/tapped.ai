import Foundation
import Synchronization
import TappedDomain
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

/// Serves canned responses for `TappedAPIPlacesRepository` and records the paths it requested.
final class StubPlacesURLProtocol: URLProtocol {
    struct State {
        var responses: [String: (status: Int, body: String)] = [:]
        var requestedPaths: [String] = []
    }

    static let state = Mutex(State())

    static func session(responses: [String: (status: Int, body: String)]) -> URLSession {
        state.withLock { $0 = State(responses: responses) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubPlacesURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static var requestedPaths: [String] { state.withLock { $0.requestedPaths } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let response = Self.state.withLock { state in
            state.requestedPaths.append(url.path())
            return state.responses[url.path()] ?? (404, "{}")
        }
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite("Tapped API places: locality for a coordinate", .serialized)
struct TappedAPIPlacesLocalityTests {
    private let baseURL = URL(string: "https://api.tapped.ai")!

    @Test func resolvesTheLocalityInOneRequestAndCachesItsDetails() async throws {
        let session = StubPlacesURLProtocol.session(responses: [
            "/app/v1/places/locality": (200, #"{"placeId":"ChIJrva","name":"Richmond","shortFormattedAddress":"Richmond, VA, USA","lat":37.54,"lng":-77.43,"locality":"Richmond"}"#),
        ])
        let repository = TappedAPIPlacesRepository(baseURL: baseURL, session: session, idToken: { "token" }, cache: GooglePlacesCache())

        let place = try #require(try await repository.getPlaceByLatLng(lat: 37.5407, lng: -77.436))
        #expect(place == PlaceData(placeId: "ChIJrva", name: "Richmond", shortFormattedAddress: "Richmond, VA, USA", lat: 37.54, lng: -77.43, locality: "Richmond"))

        #expect(try await repository.getPlaceByLatLng(lat: 37.5407, lng: -77.436) == place)
        #expect(try await repository.getPlaceIdByLatLng(lat: 37.5407, lng: -77.436) == "ChIJrva")
        #expect(try await repository.getPlaceById("ChIJrva") == place)
        #expect(StubPlacesURLProtocol.requestedPaths == ["/app/v1/places/locality"])
    }

    @Test func noLocalityIsNilAndCached() async throws {
        let session = StubPlacesURLProtocol.session(responses: [:])
        let repository = TappedAPIPlacesRepository(baseURL: baseURL, session: session, idToken: { "token" }, cache: GooglePlacesCache())

        #expect(try await repository.getPlaceByLatLng(lat: 0, lng: 0) == nil)
        #expect(try await repository.getPlaceByLatLng(lat: 0, lng: 0) == nil)
        #expect(StubPlacesURLProtocol.requestedPaths == ["/app/v1/places/locality"])
    }

    @Test func mockResolvesRichmond() async throws {
        let place = try await MockPlacesRepository().getPlaceByLatLng(lat: 37.5, lng: -77.4)
        #expect(place?.placeId == Location.rva.placeId)
    }
}
