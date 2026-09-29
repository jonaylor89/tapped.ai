import Foundation
import Observation
import TappedData

/// Asks for full notification permission only after a confirmation the user cares about ("application sent",
/// "request sent"). "not now" is remembered per confirmation type; nothing shows once alerts are allowed.
@Observable
@MainActor
final class NotificationsPromptModel {
    enum Context: String, Sendable {
        case application
        case requestToPerform
    }

    private(set) var isVisible = false
    private(set) var venueName: String?

    let context: Context
    private let notifications: any NotificationRepository
    private let database: any DatabaseRepository
    private let defaults: UserDefaults
    private let venueId: String?
    private let userId: String?

    init(
        context: Context,
        dependencies: Dependencies,
        userId: String?,
        venueName: String? = nil,
        venueId: String? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.context = context
        notifications = dependencies.notifications
        database = dependencies.database
        self.defaults = defaults
        self.userId = userId
        self.venueName = venueName
        self.venueId = venueId
    }

    static func dismissedKey(_ context: Context) -> String { "notificationsPrompt.dismissed.\(context.rawValue)" }

    var message: String {
        "know the moment \(venueName ?? "the venue") replies — only bookings, replies and gigs that match your genres"
    }

    func load() async {
        guard !defaults.bool(forKey: Self.dismissedKey(context)) else { return }
        switch await notifications.authorizationStatus() {
        case .notDetermined, .provisional:
            break
        case .authorized, .denied:
            return
        }
        if venueName == nil, let venueId {
            venueName = try? await database.getUserById(venueId)?.displayName
        }
        isVisible = true
    }

    func turnOn() async {
        isVisible = false
        do {
            if try await notifications.requestAuthorization(), let userId {
                try await notifications.saveDeviceToken(userId: userId)
            }
        } catch {
            FirebaseBootstrap.record(error: error)
        }
    }

    func notNow() {
        defaults.set(true, forKey: Self.dismissedKey(context))
        isVisible = false
    }
}
