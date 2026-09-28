import Foundation
import TappedDomain
import Testing
@testable import TappedData

@Suite("Typesense request building")
struct TypesenseSearchRepositoryTests {
    let repository = TypesenseSearchRepository(config: TappedConfig(typesenseSearchAPIKey: "key"), database: MockDatabaseRepository())

    @Test func venueFilterMatchesFlutterClauses() {
        let clauses = TypesenseSearchRepository.filterClauses(.venues(genres: ["rock", "pop"], capacity: 0...1000))
        #expect(clauses == [
            "deleted:=false",
            "occupations:=['Venue', 'venue']",
            "venueInfo.genres:=['rock', 'pop']",
            "venueInfo.capacity:>=0",
            "venueInfo.capacity:<=1000",
        ])
    }

    @Test func emptyGenresAreDropped() {
        #expect(!TypesenseSearchRepository.filterClauses(.venues(genres: [])).contains { $0.hasPrefix("venueInfo.genres") })
    }

    @Test func boundingBoxPolygonOrder() {
        let bounds = GeoBounds(swLatitude: 1, swLongitude: 2, neLatitude: 3, neLongitude: 4)
        #expect(TypesenseSearchRepository.polygon(bounds) == "location:(1.0, 2.0, 1.0, 4.0, 3.0, 4.0, 3.0, 2.0)")
    }

    @Test func searchURL() throws {
        let url = try repository.searchURL(collection: "users", params: ["q": "*", "per_page": "20"])
        #expect(url.absoluteString == "https://search.tapped.ai:443/collections/users/documents/search?per_page=20&q=*")
    }

    @Test func decodesTypesenseUserDocument() throws {
        let document: [String: Any] = [
            "id": "venue-1",
            "username": "thecamel",
            "timestamp": 1_719_878_400_000,
            "occupations": "Venue",
            "location": [37.5, -77.4],
            "placeId": "abc",
            "venueInfo": ["genres": "rock", "capacity": 250],
        ]
        let user = try TypesenseSearchRepository.decodeUser(document)
        #expect(user.location == Location(placeId: "abc", lat: 37.5, lng: -77.4))
        #expect(user.occupations == ["Venue"])
        #expect(user.venueInfo?.genres == ["rock"])
        #expect(user.timestamp == Date(timeIntervalSince1970: 1_719_878_400))
    }
}
