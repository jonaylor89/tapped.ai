import Foundation
import UserNotifications

/// Actionable push categories. The server selects one with `aps.category`
/// and passes the target in the top-level `bookingId` / `opportunityId` / `url` payload keys.
enum NotificationCategories {
    static let newGig = "NEW_GIG"
    static let bookingRequest = "BOOKING_REQUEST"

    enum Action: String, Sendable {
        case apply = "APPLY"
        case accept = "ACCEPT"
        case decline = "DECLINE"
        case reply = "REPLY"
    }

    static let applyOpensAppKey = "notifications.applyOpensApp"

    /// Can foreground Apply when interaction is needed; access is checked by the shared subscription boundary.
    static func make(applyOpensApp: Bool) -> Set<UNNotificationCategory> {
        let apply = UNNotificationAction(
            identifier: Action.apply.rawValue,
            title: "Apply",
            options: applyOpensApp ? [.foreground] : [.authenticationRequired],
            icon: UNNotificationActionIcon(systemImageName: "paperplane.fill")
        )
        let accept = UNNotificationAction(
            identifier: Action.accept.rawValue,
            title: "Accept",
            options: [.authenticationRequired],
            icon: UNNotificationActionIcon(systemImageName: "checkmark.circle.fill")
        )
        let decline = UNNotificationAction(
            identifier: Action.decline.rawValue,
            title: "Decline",
            options: [.authenticationRequired, .destructive],
            icon: UNNotificationActionIcon(systemImageName: "xmark.circle.fill")
        )
        let reply = UNTextInputNotificationAction(
            identifier: Action.reply.rawValue,
            title: "Reply",
            options: [.authenticationRequired],
            icon: UNNotificationActionIcon(systemImageName: "bubble.left.fill"),
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Message"
        )
        return [
            UNNotificationCategory(identifier: newGig, actions: [apply], intentIdentifiers: []),
            UNNotificationCategory(identifier: bookingRequest, actions: [accept, decline, reply], intentIdentifiers: []),
        ]
    }

    static func register(defaults: UserDefaults = .standard) {
        UNUserNotificationCenter.current().setNotificationCategories(make(applyOpensApp: defaults.bool(forKey: applyOpensAppKey)))
        #if DEBUG
        if ProcessInfo.processInfo.environment["TAPPED_MOCK_PUSH_AUTH"] == "1" {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        }
        #endif
    }

    static func setApplyOpensApp(_ opensApp: Bool, defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: applyOpensAppKey) != opensApp else { return }
        defaults.set(opensApp, forKey: applyOpensAppKey)
        register(defaults: defaults)
    }
}

/// The parts of a `UNNotificationResponse` the router needs, safe to hand to the main actor.
struct NotificationActionResponse: Sendable, Equatable {
    var categoryIdentifier: String
    var actionIdentifier: String
    var payload: NotificationPayload
    var text: String?

    init(categoryIdentifier: String, actionIdentifier: String, userInfo: [AnyHashable: Any], text: String? = nil) {
        self.categoryIdentifier = categoryIdentifier
        self.actionIdentifier = actionIdentifier
        payload = NotificationPayload(userInfo: userInfo)
        self.text = text
    }

    init(_ response: UNNotificationResponse) {
        let content = response.notification.request.content
        self.init(
            categoryIdentifier: content.categoryIdentifier,
            actionIdentifier: response.actionIdentifier,
            userInfo: content.userInfo,
            text: (response as? UNTextInputNotificationResponse)?.userText
        )
    }

    var action: NotificationCategories.Action? { NotificationCategories.Action(rawValue: actionIdentifier) }
    /// Custom action buttons; a plain tap (`UNNotificationDefaultActionIdentifier`) keeps the existing deep-link routing.
    var isAction: Bool { action != nil }
}
