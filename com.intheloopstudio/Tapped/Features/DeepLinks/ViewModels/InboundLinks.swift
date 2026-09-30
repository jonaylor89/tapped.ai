import Foundation
import Observation
import TappedData
import TappedDomain
import UIKit

/// Buffers links from `onOpenURL` (universal links, custom scheme) and notification taps until the
/// signed-in shell can route them, so cold-start links survive splash / auth / onboarding.
@Observable
@MainActor
final class InboundLinks {
    private(set) var pending: DeepLink?
    /// Bumped whenever APNs hands us a device token, so the session can (re)save the FCM token.
    private(set) var apnsRegistrations = 0

    private let openExternal: @MainActor (URL) -> Void

    init(openExternal: @escaping @MainActor (URL) -> Void = { UIApplication.shared.open($0) }) {
        self.openExternal = openExternal
    }

    /// Returns whether the URL was an app link.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let link = DeepLink(url: url) else { return false }
        pending = link
        return true
    }

    func receive(_ payload: NotificationPayload) {
        if let link = payload.link {
            pending = link
        } else if let url = payload.externalURL {
            openExternal(url)
        }
    }

    func take() -> DeepLink? {
        defer { pending = nil }
        return pending
    }

    func apnsTokenRegistered() { apnsRegistrations += 1 }
}

/// Resolves a `DeepLink` to a typed `Route` (`deep_link_bloc.dart` `_linkHandler`).
struct DeepLinkResolver {
    struct Resolution: Equatable {
        var route: Route?
        /// Set when the link changed the current user (Stripe Connect return).
        var updatedUser: UserModel?
    }

    let database: any DatabaseRepository

    func resolve(_ link: DeepLink, currentUser: UserModel) async -> Resolution {
        do {
            switch link {
            case let .profile(username):
                guard let user = try await database.getUserByUsername(username) else { return Resolution() }
                return Resolution(route: .profile(userId: user.id, user: user))
            case let .profileId(userId):
                guard let user = try await database.getUserById(userId) else { return Resolution() }
                return Resolution(route: .profile(userId: userId, user: user))
            case let .opportunity(opportunityId):
                let opportunity = try? await database.getOpportunityById(opportunityId)
                return Resolution(route: .opportunity(opportunityId: opportunityId, opportunity: opportunity))
            case let .booking(bookingId):
                guard let booking = try await database.getBookingById(bookingId) else { return Resolution() }
                return Resolution(route: .booking(booking))
            case .settings:
                return Resolution(route: .settings)
            case let .connectPayment(accountId):
                var user = currentUser
                user.stripeConnectedAccountId = accountId
                try await database.updateUserData(user)
                return Resolution(route: .settings, updatedUser: user)
            }
        } catch {
            FirebaseBootstrap.record(error: error)
            return Resolution()
        }
    }
}
