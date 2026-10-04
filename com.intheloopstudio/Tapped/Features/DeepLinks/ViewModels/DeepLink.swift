import Foundation
import TappedDomain

/// Native replacement for `app_links` + `lib/data/prod/uni_link_impl.dart`.
///
/// Accepts universal links on the associated domains (`Tapped.entitlements`) and the
/// `com.intheloopstudio://` custom scheme (host = first path segment), e.g.
/// `https://app.tapped.ai/u/djnova`, `com.intheloopstudio://opportunity/abc`.
enum DeepLink: Hashable, Sendable {
    /// `/u/{username}` or `/{username}`
    case profile(username: String)
    /// `/map?user_id={id}`
    case profileId(userId: String)
    /// `/opportunity/{id}`
    case opportunity(opportunityId: String)
    /// `/booking/{id}`
    case booking(bookingId: String)
    /// `/settings`
    case settings
    /// `/connect_payment?account_id={id}` (Stripe Connect onboarding return URL)
    case connectPayment(accountId: String)
    /// `com.intheloopstudio://gigs?paid=1&when=weekend` (custom scheme only)
    case gigs(GigFilter?)
    /// `com.intheloopstudio://share_profile?qr=1` (custom scheme only)
    case shareProfile(showsQR: Bool)

    static let hosts: Set<String> = [
        "app.tapped.ai", "tapped.ai", "www.tapped.ai", "tappednetwork.page.link", "intheloopstudio.page.link",
    ]
    static let scheme = "com.intheloopstudio"
    /// Paths excluded in `apple-app-site-association`, plus web-only pages.
    static let webOnlyPaths: Set<String> = ["spotify", "venue", "about", "terms", "privacy", "team", "subscribe", "eula"]

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else { return nil }
        var segments = components.path.split(separator: "/").map(String.init)
        switch scheme {
        case "https", "http":
            guard let host = components.host?.lowercased(), Self.hosts.contains(host) else { return nil }
        case Self.scheme:
            if let host = components.host, !host.isEmpty { segments.insert(host, at: 0) }
        default:
            return nil
        }
        let query = Dictionary(
            (components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        guard let first = segments.first?.lowercased(), !Self.webOnlyPaths.contains(first) else { return nil }
        let second = segments.dropFirst().first.flatMap { $0.isEmpty ? nil : $0 }

        if scheme == Self.scheme, let link = Self.appOnly(first, query: query) {
            self = link
            return
        }

        switch first {
        case "u":
            guard let second else { return nil }
            self = .profile(username: second.lowercased())
        case "map":
            guard let userId = query["user_id"], !userId.isEmpty else { return nil }
            self = .profileId(userId: userId)
        case "opportunity":
            guard let second else { return nil }
            self = .opportunity(opportunityId: second)
        case "booking":
            guard let second else { return nil }
            self = .booking(bookingId: second)
        case "settings":
            self = .settings
        case "connect_payment":
            guard let accountId = query["account_id"], !accountId.isEmpty else { return nil }
            self = .connectPayment(accountId: accountId)
        default:
            self = .profile(username: segments[0].lowercased())
        }
    }

    private static func appOnly(_ first: String, query: [String: String]) -> DeepLink? {
        switch first {
        case "gigs":
            let filter = GigFilter(paidOnly: query["paid"] == "1", weekendOnly: query["when"] == "weekend")
            return .gigs(filter == GigFilter() ? nil : filter)
        case "share_profile":
            return .shareProfile(showsQR: query["qr"] == "1")
        default:
            return nil
        }
    }
}

/// Data carried by a tapped push notification. Flutter only reads `url`; the typed keys let
/// Cloud Functions route straight to a screen without building a URL.
struct NotificationPayload: Sendable, Equatable {
    var link: DeepLink?
    /// Non-app URL (e.g. a blog post) opened in the browser, matching Flutter `launchUrl`.
    var externalURL: URL?

    init(link: DeepLink? = nil, externalURL: URL? = nil) {
        self.link = link
        self.externalURL = externalURL
    }

    init(userInfo: [AnyHashable: Any]) {
        func string(_ key: String) -> String? {
            (userInfo[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        if let raw = string("url") ?? string("link"), let url = URL(string: raw) {
            if let link = DeepLink(url: url) {
                self.init(link: link)
            } else if ["http", "https"].contains(url.scheme?.lowercased()) {
                self.init(externalURL: url)
            } else {
                self.init()
            }
        } else if let bookingId = string("bookingId") {
            self.init(link: .booking(bookingId: bookingId))
        } else if let opportunityId = string("opportunityId") {
            self.init(link: .opportunity(opportunityId: opportunityId))
        } else if let username = string("username") {
            self.init(link: .profile(username: username))
        } else if let userId = string("userId") {
            self.init(link: .profileId(userId: userId))
        } else {
            self.init()
        }
    }
}
