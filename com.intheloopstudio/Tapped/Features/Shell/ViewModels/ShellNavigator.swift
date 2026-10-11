import Foundation
import Observation
import TappedUI

/// The five tabs inside the persistent map sheet.
enum ShellTab: String, CaseIterable, Hashable, Sendable {
    case gigs, bookings, messages, profile, search

    var title: String { rawValue }

    var systemImage: String {
        switch self {
        case .gigs: "map"
        case .bookings: "calendar"
        case .messages: "bubble.left.and.bubble.right"
        case .profile: "person.crop.circle"
        case .search: "magnifyingglass"
        }
    }
}

/// Tab selection, sheet height and one `Router` per tab.
///
/// Height policy: Gigs remembers the user's last detent, every other tab snaps to `.large`, and pushing inside
/// Gigs raises the sheet to at least `.medium` so the map stays visible above the pushed screen.
@Observable
@MainActor
final class ShellNavigator {
    struct Destination: Equatable {
        let tab: ShellTab
        let detent: MapsSheetDetent
    }

    private(set) var tab: ShellTab
    private(set) var detent: MapsSheetDetent
    private(set) var gigsDetent: MapsSheetDetent

    let gigs = Router()
    let bookings = Router()
    let messages = Router()
    let profile = Router()
    let search = Router()

    private let currentUserId: String

    init(currentUserId: String, tab: ShellTab = .gigs, detent: MapsSheetDetent? = nil) {
        self.currentUserId = currentUserId
        self.tab = tab
        let initial = detent ?? (tab == .gigs ? .collapsed : .large)
        self.detent = initial
        gigsDetent = tab == .gigs ? initial : .collapsed
        for router in routers {
            router.openInShell = { [weak self] route in self?.open(route) }
        }
    }

    private var routers: [Router] { [gigs, bookings, messages, profile, search] }

    func router(for tab: ShellTab) -> Router {
        switch tab {
        case .gigs: gigs
        case .bookings: bookings
        case .messages: messages
        case .profile: profile
        case .search: search
        }
    }

    func select(_ tab: ShellTab) {
        guard tab != self.tab else { return }
        self.tab = tab
        detent = tab == .gigs ? gigsDetent : .large
    }

    func setDetent(_ detent: MapsSheetDetent) {
        self.detent = detent
        if tab == .gigs { gigsDetent = detent }
    }

    /// Call when the Gigs stack depth changes (pushes via `NavigationLink(value:)` included).
    func gigsPathDidChange(from oldCount: Int, to newCount: Int) {
        guard tab == .gigs, newCount > oldCount, detent == .collapsed else { return }
        setDetent(.medium)
    }

    /// Deep links, notification taps, map pins and `TAPPED_MOCK_ROUTE`: selects the tab that owns `route`,
    /// resets that tab's stack to it and sizes the sheet.
    func open(_ route: Route) {
        open(path: [route])
    }

    func open(path routes: [Route]) {
        guard let first = routes.first else { return }
        if first == .discovery {
            select(.gigs)
            gigs.popToRoot()
            setDetent(.collapsed)
            return
        }
        let destination = Self.destination(for: first, currentUserId: currentUserId)
        if let destination {
            select(destination.tab)
            setDetent(destination.tab == .gigs ? max(gigsDetent, destination.detent) : destination.detent)
        }
        let router = router(for: tab)
        if destination != nil { router.popToRoot() }
        for route in routes.drop(while: { isRoot($0, of: tab) }) {
            router.push(route)
        }
    }

    /// Where `route` lives. `nil` keeps the current tab (takeovers such as `.paywall`, `.image`).
    static func destination(for route: Route, currentUserId: String) -> Destination? {
        switch route {
        case let .profile(userId, _):
            userId == currentUserId ? Destination(tab: .profile, detent: .large) : Destination(tab: .gigs, detent: .medium)
        case let .reviews(userId):
            userId == currentUserId ? Destination(tab: .profile, detent: .large) : Destination(tab: .gigs, detent: .medium)
        case .opportunity, .opportunities, .interestedUsers, .discovery:
            Destination(tab: .gigs, detent: .medium)
        case .bookings, .booking, .bookingConfirmation, .requestToPerform, .requestToPerformConfirmation, .bookingHistory,
             .addPastBooking, .createBooking, .serviceSelection, .service, .addCollaborators:
            Destination(tab: .bookings, detent: .large)
        case .messagingChannelList, .streamChannel, .videoCall:
            Destination(tab: .messages, detent: .large)
        case .settings, .activities, .tasks, .shareProfile, .createService, .admin:
            Destination(tab: .profile, detent: .large)
        case .search, .advancedSearch, .gigSearch, .opportunityFeed, .locationForm:
            Destination(tab: .search, detent: .large)
        case .paywall, .image, .login, .signUp, .forgotPassword, .onboarding:
            nil
        }
    }

    /// The screen a tab already shows at its root, so opening it doesn't push a duplicate.
    private func isRoot(_ route: Route, of tab: ShellTab) -> Bool {
        switch (tab, route) {
        case let (.bookings, .bookings(userId)): userId == currentUserId
        case (.messages, .messagingChannelList): true
        case let (.profile, .profile(userId, _)): userId == currentUserId
        case (.search, .search): true
        default: false
        }
    }
}
