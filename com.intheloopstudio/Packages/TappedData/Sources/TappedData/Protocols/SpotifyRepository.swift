import Foundation

/// `lib/data/spotify_repository.dart`, served by the Tapped API's `/app/v1/spotify` proxy.
public protocol SpotifyRepository: Sendable {
    /// `nil` when Spotify has no artist with that id.
    func artist(id: String) async throws -> SpotifyArtist?
}

/// The fields of Spotify's artist object that onboarding uses.
public struct SpotifyArtist: Sendable, Hashable, Identifiable, Decodable {
    public var id: String
    public var name: String
    public var genres: [String]
    public var followers: Int
    /// Largest image first, as Spotify returns them.
    public var imageURL: URL?

    public init(id: String, name: String, genres: [String] = [], followers: Int = 0, imageURL: URL? = nil) {
        self.id = id
        self.name = name
        self.genres = genres
        self.followers = followers
        self.imageURL = imageURL
    }

    private enum CodingKeys: String, CodingKey { case id, name, genres, followers, images }
    private struct Followers: Decodable { let total: Int? }
    private struct Image: Decodable { let url: String }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        genres = try c.decodeIfPresent([String].self, forKey: .genres) ?? []
        followers = try c.decodeIfPresent(Followers.self, forKey: .followers)?.total ?? 0
        imageURL = try c.decodeIfPresent([Image].self, forKey: .images)?.first.flatMap { URL(string: $0.url) }
    }

    /// The artist id in an `open.spotify.com/artist/{id}` link (any locale prefix or query), a
    /// `spotify:artist:{id}` URI, or a bare id. `nil` for anything else.
    public static func artistId(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: Substring?
        if trimmed.hasPrefix("spotify:artist:") {
            candidate = trimmed.dropFirst("spotify:artist:".count)
        } else if let url = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)"),
                  let host = url.host(), host == "open.spotify.com" {
            let segments = url.pathComponents.filter { $0 != "/" }
            candidate = segments.firstIndex(of: "artist").flatMap { segments[safe: $0 + 1] }.map { Substring($0) }
        } else {
            candidate = Substring(trimmed)
        }
        guard let id = candidate, isValidId(id) else { return nil }
        return String(id)
    }

    /// Spotify ids are base-62; the API rejects anything else.
    static func isValidId(_ id: Substring) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
