import Foundation

/// `email_notifications.dart`
public struct EmailNotifications: Codable, Sendable, Hashable {
    public var appReleases: Bool
    public var tappedUpdates: Bool
    public var bookingRequests: Bool
    public var directMessages: Bool

    public init(appReleases: Bool = true, tappedUpdates: Bool = true, bookingRequests: Bool = true, directMessages: Bool = true) {
        self.appReleases = appReleases
        self.tappedUpdates = tappedUpdates
        self.bookingRequests = bookingRequests
        self.directMessages = directMessages
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appReleases = try c.decode(Bool.self, forKey: .appReleases, default: true)
        tappedUpdates = try c.decode(Bool.self, forKey: .tappedUpdates, default: true)
        bookingRequests = try c.decode(Bool.self, forKey: .bookingRequests, default: true)
        directMessages = try c.decode(Bool.self, forKey: .directMessages, default: true)
    }

    public static let empty = EmailNotifications()
}

/// `push_notifications.dart`
public struct PushNotifications: Codable, Sendable, Hashable {
    public var appReleases: Bool
    public var tappedUpdates: Bool
    public var bookingRequests: Bool
    public var directMessages: Bool

    public init(appReleases: Bool = true, tappedUpdates: Bool = true, bookingRequests: Bool = true, directMessages: Bool = true) {
        self.appReleases = appReleases
        self.tappedUpdates = tappedUpdates
        self.bookingRequests = bookingRequests
        self.directMessages = directMessages
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appReleases = try c.decode(Bool.self, forKey: .appReleases, default: true)
        tappedUpdates = try c.decode(Bool.self, forKey: .tappedUpdates, default: true)
        bookingRequests = try c.decode(Bool.self, forKey: .bookingRequests, default: true)
        directMessages = try c.decode(Bool.self, forKey: .directMessages, default: true)
    }

    public static let empty = PushNotifications()
}
