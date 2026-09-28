import Foundation

/// `user_model.dart`. Field names are the Firestore keys in `users/{id}`.
public struct UserModel: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var timestamp: Date?
    public var username: Username
    public var email: String
    public var phoneNumber: String?
    public var website: String?
    public var unclaimed: Bool
    public var artistName: String
    public var profilePicture: String?
    public var bio: String
    public var occupations: [String]
    public var location: Location?
    public var badgesCount: Int
    public var performerInfo: PerformerInfo?
    public var bookerInfo: BookerInfo?
    public var venueInfo: VenueInfo?
    public var socialFollowing: SocialFollowing
    public var emailNotifications: EmailNotifications
    public var pushNotifications: PushNotifications
    public var deleted: Bool
    public var stripeConnectedAccountId: String?
    public var stripeCustomerId: String?
    public var latestAppVersion: String?

    public init(
        id: String,
        timestamp: Date? = nil,
        username: Username,
        email: String = "",
        phoneNumber: String? = nil,
        website: String? = nil,
        unclaimed: Bool = false,
        artistName: String = "",
        profilePicture: String? = nil,
        bio: String = "",
        occupations: [String] = [],
        location: Location? = nil,
        badgesCount: Int = 0,
        performerInfo: PerformerInfo? = nil,
        bookerInfo: BookerInfo? = nil,
        venueInfo: VenueInfo? = nil,
        socialFollowing: SocialFollowing = .empty,
        emailNotifications: EmailNotifications = .empty,
        pushNotifications: PushNotifications = .empty,
        deleted: Bool = false,
        stripeConnectedAccountId: String? = nil,
        stripeCustomerId: String? = nil,
        latestAppVersion: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.username = username
        self.email = email
        self.phoneNumber = phoneNumber
        self.website = website
        self.unclaimed = unclaimed
        self.artistName = artistName
        self.profilePicture = profilePicture
        self.bio = bio
        self.occupations = occupations
        self.location = location
        self.badgesCount = badgesCount
        self.performerInfo = performerInfo
        self.bookerInfo = bookerInfo
        self.venueInfo = venueInfo
        self.socialFollowing = socialFollowing
        self.emailNotifications = emailNotifications
        self.pushNotifications = pushNotifications
        self.deleted = deleted
        self.stripeConnectedAccountId = stripeConnectedAccountId
        self.stripeCustomerId = stripeCustomerId
        self.latestAppVersion = latestAppVersion
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        timestamp = c.decodeLossy(Date.self, forKey: .timestamp)
        username = try c.decode(Username.self, forKey: .username, default: .empty)
        email = try c.decode(String.self, forKey: .email, default: "")
        phoneNumber = c.decodeLossy(String.self, forKey: .phoneNumber)
        website = c.decodeLossy(String.self, forKey: .website)
        unclaimed = try c.decode(Bool.self, forKey: .unclaimed, default: false)
        artistName = try c.decode(String.self, forKey: .artistName, default: "")
        profilePicture = c.decodeLossy(String.self, forKey: .profilePicture)
        bio = try c.decode(String.self, forKey: .bio, default: "")
        occupations = try c.decodeList(String.self, forKey: .occupations)
        location = c.decodeLossy(Location.self, forKey: .location)
        badgesCount = try c.decode(Int.self, forKey: .badgesCount, default: 0)
        performerInfo = try c.decodeIfPresent(PerformerInfo.self, forKey: .performerInfo)
        bookerInfo = try c.decodeIfPresent(BookerInfo.self, forKey: .bookerInfo)
        venueInfo = try c.decodeIfPresent(VenueInfo.self, forKey: .venueInfo)
        socialFollowing = try c.decode(SocialFollowing.self, forKey: .socialFollowing, default: .empty)
        emailNotifications = try c.decode(EmailNotifications.self, forKey: .emailNotifications, default: .empty)
        pushNotifications = try c.decode(PushNotifications.self, forKey: .pushNotifications, default: .empty)
        deleted = try c.decode(Bool.self, forKey: .deleted, default: false)
        stripeConnectedAccountId = c.decodeLossy(String.self, forKey: .stripeConnectedAccountId)
        stripeCustomerId = c.decodeLossy(String.self, forKey: .stripeCustomerId)
        latestAppVersion = c.decodeLossy(String.self, forKey: .latestAppVersion)
    }

    /// `UserModel.displayName`
    public var displayName: String { artistName.isEmpty ? username.username : artistName }
    public var isVenue: Bool { venueInfo != nil }
    public var isPerformer: Bool { performerInfo != nil }

    /// `UserModel.empty()`
    public static let empty = UserModel(id: "", username: .empty)
    public var isEmpty: Bool { self == .empty }

    /// Mirrors `isNew` in `user_tile.dart`: joined within the last 7 days.
    public func isNew(now: Date = .now) -> Bool {
        guard let timestamp else { return false }
        return timestamp > now.addingTimeInterval(-7 * 24 * 60 * 60)
    }
}
