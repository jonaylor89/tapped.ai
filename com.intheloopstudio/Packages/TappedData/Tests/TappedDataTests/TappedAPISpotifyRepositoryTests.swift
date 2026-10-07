import Foundation
import Testing
@testable import TappedData

@Suite("Tapped API Spotify repository")
struct TappedAPISpotifyRepositoryTests {
    @Test(arguments: [
        ("https://open.spotify.com/artist/4Z8W4fKeB5YxbusRsdQVPb", "4Z8W4fKeB5YxbusRsdQVPb"),
        ("https://open.spotify.com/intl-de/artist/4Z8W4fKeB5YxbusRsdQVPb?si=abc", "4Z8W4fKeB5YxbusRsdQVPb"),
        ("open.spotify.com/artist/4Z8W4fKeB5YxbusRsdQVPb", "4Z8W4fKeB5YxbusRsdQVPb"),
        ("  spotify:artist:4Z8W4fKeB5YxbusRsdQVPb ", "4Z8W4fKeB5YxbusRsdQVPb"),
        ("4Z8W4fKeB5YxbusRsdQVPb", "4Z8W4fKeB5YxbusRsdQVPb"),
    ])
    func parsesArtistLinks(input: String, expected: String) {
        #expect(SpotifyArtist.artistId(from: input) == expected)
    }

    @Test(arguments: [
        "",
        "https://open.spotify.com/track/4Z8W4fKeB5YxbusRsdQVPb",
        "https://example.com/artist/4Z8W4fKeB5YxbusRsdQVPb",
        "../stream-token",
        "nova waves",
    ])
    func rejectsOtherInput(input: String) {
        #expect(SpotifyArtist.artistId(from: input) == nil)
    }

    @Test func decodesSpotifyArtistJSON() throws {
        let json = """
        {"id":"abc","name":"Nova","genres":["pop"],"followers":{"href":null,"total":42},
         "images":[{"url":"https://i.scdn.co/image/big","height":640,"width":640},
                   {"url":"https://i.scdn.co/image/small","height":64,"width":64}],
         "popularity":10,"type":"artist","uri":"spotify:artist:abc"}
        """
        let artist = try JSONDecoder().decode(SpotifyArtist.self, from: Data(json.utf8))
        #expect(artist == SpotifyArtist(id: "abc", name: "Nova", genres: ["pop"], followers: 42, imageURL: URL(string: "https://i.scdn.co/image/big")))

        let minimal = try JSONDecoder().decode(SpotifyArtist.self, from: Data(#"{"id":"abc"}"#.utf8))
        #expect(minimal == SpotifyArtist(id: "abc", name: ""))
    }

    @Test func artistRequestUsesBearerAuthentication() async throws {
        let repository = TappedAPISpotifyRepository(baseURL: URL(string: "https://api.example.com/base/")!, idToken: { "firebase-token" })
        let request = try await repository.makeArtistRequest(id: "abc123")
        #expect(request.url == URL(string: "https://api.example.com/base/app/v1/spotify/artists/abc123"))
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer firebase-token")
        #expect(UUID(uuidString: request.value(forHTTPHeaderField: "X-Request-Id") ?? "") != nil)
    }

    @Test func rejectsMissingFirebaseToken() async {
        let repository = TappedAPISpotifyRepository(baseURL: URL(string: "https://api.example.com/")!, idToken: { nil })
        await #expect(throws: TappedAPIError.notSignedIn) { _ = try await repository.makeArtistRequest(id: "abc") }
    }

    @Test func mockServesKnownArtists() async throws {
        let mock = MockSpotifyRepository()
        let known = try #require(MockSpotifyRepository.artists.first)
        #expect(try await mock.artist(id: known.id) == known)
        #expect(try await mock.artist(id: "missing") == nil)
    }
}
