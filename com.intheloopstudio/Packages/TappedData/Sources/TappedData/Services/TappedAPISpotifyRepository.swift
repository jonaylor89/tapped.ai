import FirebaseAuth
import Foundation

/// Live `SpotifyRepository`: the API holds the Spotify client credentials, so the app never sees a Spotify token.
public struct TappedAPISpotifyRepository: SpotifyRepository {
    public typealias IDTokenProvider = @Sendable () async throws -> String?

    private let baseURL: URL
    private let session: URLSession
    private let idToken: IDTokenProvider

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        idToken: @escaping IDTokenProvider = { try await Auth.auth().currentUser?.getIDToken() }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.idToken = idToken
    }

    public func artist(id: String) async throws -> SpotifyArtist? {
        let (data, response) = try await session.data(for: makeArtistRequest(id: id))
        let status = (response as? HTTPURLResponse)?.statusCode
        // The API answers 400 for ids Spotify can't parse and 404 for unknown ones; both mean "no such artist".
        if status == 404 || status == 400 { return nil }
        guard let status, (200..<300).contains(status) else { throw TappedAPIError.requestFailed(statusCode: status) }
        guard let artist = try? JSONDecoder().decode(SpotifyArtist.self, from: data) else {
            throw TappedAPIError.invalidResponse
        }
        return artist
    }

    func makeArtistRequest(id: String) async throws -> URLRequest {
        guard let token = try await idToken(), !token.isEmpty else { throw TappedAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appending(path: "app/v1/spotify/artists").appending(path: id))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}
