import Foundation

/// `social_following.dart`
public struct SocialFollowing: Codable, Sendable, Hashable {
    public var youtubeChannelId: String?
    public var youtubeHandle: String?
    public var tiktokHandle: String?
    public var tiktokFollowers: Int
    public var instagramHandle: String?
    public var instagramFollowers: Int
    public var twitterHandle: String?
    public var twitterFollowers: Int
    public var facebookHandle: String?
    public var facebookFollowers: Int
    public var spotifyId: String?
    public var spotifyMonthlyListeners: Int
    public var soundcloudHandle: String?
    public var soundcloudFollowers: Int
    public var audiusHandle: String?
    public var audiusFollowers: Int
    public var twitchHandle: String?
    public var twitchFollowers: Int

    public init(
        youtubeChannelId: String? = nil, youtubeHandle: String? = nil,
        tiktokHandle: String? = nil, tiktokFollowers: Int = 0,
        instagramHandle: String? = nil, instagramFollowers: Int = 0,
        twitterHandle: String? = nil, twitterFollowers: Int = 0,
        facebookHandle: String? = nil, facebookFollowers: Int = 0,
        spotifyId: String? = nil, spotifyMonthlyListeners: Int = 0,
        soundcloudHandle: String? = nil, soundcloudFollowers: Int = 0,
        audiusHandle: String? = nil, audiusFollowers: Int = 0,
        twitchHandle: String? = nil, twitchFollowers: Int = 0
    ) {
        self.youtubeChannelId = youtubeChannelId
        self.youtubeHandle = youtubeHandle
        self.tiktokHandle = tiktokHandle
        self.tiktokFollowers = tiktokFollowers
        self.instagramHandle = instagramHandle
        self.instagramFollowers = instagramFollowers
        self.twitterHandle = twitterHandle
        self.twitterFollowers = twitterFollowers
        self.facebookHandle = facebookHandle
        self.facebookFollowers = facebookFollowers
        self.spotifyId = spotifyId
        self.spotifyMonthlyListeners = spotifyMonthlyListeners
        self.soundcloudHandle = soundcloudHandle
        self.soundcloudFollowers = soundcloudFollowers
        self.audiusHandle = audiusHandle
        self.audiusFollowers = audiusFollowers
        self.twitchHandle = twitchHandle
        self.twitchFollowers = twitchFollowers
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        youtubeChannelId = c.decodeLossy(String.self, forKey: .youtubeChannelId)
        youtubeHandle = c.decodeLossy(String.self, forKey: .youtubeHandle)
        tiktokHandle = c.decodeLossy(String.self, forKey: .tiktokHandle)
        tiktokFollowers = try c.decode(Int.self, forKey: .tiktokFollowers, default: 0)
        instagramHandle = c.decodeLossy(String.self, forKey: .instagramHandle)
        instagramFollowers = try c.decode(Int.self, forKey: .instagramFollowers, default: 0)
        twitterHandle = c.decodeLossy(String.self, forKey: .twitterHandle)
        twitterFollowers = try c.decode(Int.self, forKey: .twitterFollowers, default: 0)
        facebookHandle = c.decodeLossy(String.self, forKey: .facebookHandle)
        facebookFollowers = try c.decode(Int.self, forKey: .facebookFollowers, default: 0)
        spotifyId = c.decodeLossy(String.self, forKey: .spotifyId)
        spotifyMonthlyListeners = try c.decode(Int.self, forKey: .spotifyMonthlyListeners, default: 0)
        soundcloudHandle = c.decodeLossy(String.self, forKey: .soundcloudHandle)
        soundcloudFollowers = try c.decode(Int.self, forKey: .soundcloudFollowers, default: 0)
        audiusHandle = c.decodeLossy(String.self, forKey: .audiusHandle)
        audiusFollowers = try c.decode(Int.self, forKey: .audiusFollowers, default: 0)
        twitchHandle = c.decodeLossy(String.self, forKey: .twitchHandle)
        twitchFollowers = try c.decode(Int.self, forKey: .twitchFollowers, default: 0)
    }

    public static let empty = SocialFollowing()

    /// `SocialFollowingHelper.audienceSize`
    public var audienceSize: Int {
        tiktokFollowers + instagramFollowers + twitterFollowers + facebookFollowers
    }
}
