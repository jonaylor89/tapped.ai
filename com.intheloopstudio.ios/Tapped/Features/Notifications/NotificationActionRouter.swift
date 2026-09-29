import Foundation
import TappedData
import TappedDomain
import UserNotifications

/// Handles notification action buttons without opening the app when possible:
/// **Apply** (`NEW_GIG`) goes through `OpportunityApplication`, **Accept** / **Decline** / **Reply** (`BOOKING_REQUEST`)
/// update the booking or message the booker.
@MainActor
struct NotificationActionRouter {
    enum Outcome: Equatable, Sendable {
        case unhandled
        case applied(opportunityId: String)
        case needsPremium(opportunityId: String)
        case bookingUpdated(bookingId: String, status: BookingStatus)
        case replied(conversationId: String)
        case failed(NotificationPayload)
    }

    let dependencies: Dependencies
    var now: () -> Date = { .now }
    var onBookingConfirmed: @MainActor (Booking) async -> Void = { _ in }

    func handle(_ response: NotificationActionResponse) async -> Outcome {
        guard let action = response.action else { return .unhandled }
        guard let userId = await dependencies.auth.getAuthUser()?.uid else { return .failed(response.payload) }
        switch (action, response.payload.link) {
        case let (.apply, .opportunity(opportunityId)?):
            return await apply(opportunityId: opportunityId, userId: userId, payload: response.payload)
        case let (.accept, .booking(bookingId)?):
            return await respond(bookingId: bookingId, userId: userId, status: .confirmed, payload: response.payload)
        case let (.decline, .booking(bookingId)?):
            return await respond(bookingId: bookingId, userId: userId, status: .canceled, payload: response.payload)
        case let (.reply, .booking(bookingId)?):
            return await reply(bookingId: bookingId, userId: userId, text: response.text, payload: response.payload)
        default:
            return .failed(response.payload)
        }
    }

    private func apply(opportunityId: String, userId: String, payload: NotificationPayload) async -> Outcome {
        do {
            guard let opportunity = try await dependencies.database.getOpportunityById(opportunityId) else { return .failed(payload) }
            let application = OpportunityApplication(dependencies: dependencies, userId: userId, isPremium: await dependencies.purchases.isPremium())
            switch try await application.apply(to: [opportunity], comment: "") {
            case .applied: return .applied(opportunityId: opportunityId)
            case .needsPremium: return .needsPremium(opportunityId: opportunityId)
            }
        } catch {
            return .failed(payload)
        }
    }

    private func respond(bookingId: String, userId: String, status: BookingStatus, payload: NotificationPayload) async -> Outcome {
        do {
            guard var booking = try await dependencies.database.getBookingById(bookingId),
                  booking.requesteeId == userId, booking.isPending, !booking.isExpired(now: now()) else { return .failed(payload) }
            booking.status = status
            try await dependencies.database.updateBooking(booking)
            let event = status == .confirmed ? "booking_confirmed" : "booking_denied"
            await dependencies.analytics.track(event, properties: ["booking_id": .string(bookingId), "source": .string("notification")])
            if status == .confirmed { await onBookingConfirmed(booking) }
            return .bookingUpdated(bookingId: bookingId, status: status)
        } catch {
            return .failed(payload)
        }
    }

    private func reply(bookingId: String, userId: String, text: String?, payload: NotificationPayload) async -> Outcome {
        let message = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !message.isEmpty else { return .failed(payload) }
        do {
            guard let booking = try await dependencies.database.getBookingById(bookingId),
                  let bookerId = booking.requesterId,
                  booking.involves(userId),
                  let user = try await dependencies.database.getUserById(userId) else { return .failed(payload) }
            try await dependencies.chat.connectUser(user)
            let conversationId = try await dependencies.chat.createDirectConversation(with: bookerId == userId ? booking.requesteeId : bookerId)
            try await dependencies.chat.sendMessage(message, conversationId: conversationId)
            return .replied(conversationId: conversationId)
        } catch {
            return .failed(payload)
        }
    }
}

extension NotificationActionRouter {
    /// `AppDelegate.userNotificationCenter(_:didReceive:)` entry point for action buttons.
    static func perform(_ response: NotificationActionResponse) async {
        let router = NotificationActionRouter(dependencies: AppEnvironment.dependencies, onBookingConfirmed: { booking in
            await GigNightCoordinator.shared.bookingConfirmed(booking)
        })
        let outcome = await router.handle(response)
        switch outcome {
        case let .needsPremium(opportunityId):
            NotificationCategories.setApplyOpensApp(true)
            AppEnvironment.inbound.receive(NotificationPayload(link: .opportunity(opportunityId: opportunityId)))
            await postFollowUp(
                title: "you're out of free applications",
                body: "go premium to apply to this gig",
                link: URL(string: "https://app.tapped.ai/opportunity/\(opportunityId)")
            )
        case let .failed(payload):
            await postFollowUp(title: "that didn't go through", body: "open tapped to try again", link: payload.link.flatMap { (link: DeepLink) in link.url })
        case .unhandled:
            AppEnvironment.inbound.receive(response.payload)
        case .applied, .bookingUpdated, .replied:
            break
        }
    }

    private static func postFollowUp(title: String, body: String, link: URL?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let link { content.userInfo = ["url": link.absoluteString] }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

extension DeepLink {
    /// Universal link back to the screen, for follow-up notifications.
    var url: URL? {
        switch self {
        case let .opportunity(opportunityId): URL(string: "https://app.tapped.ai/opportunity/\(opportunityId)")
        case let .booking(bookingId): URL(string: "https://app.tapped.ai/booking/\(bookingId)")
        case let .profile(username): URL(string: "https://app.tapped.ai/u/\(username)")
        default: nil
        }
    }
}
