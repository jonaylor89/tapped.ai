import Foundation

/// Records permission prompts, saved tokens and badge updates so tests can assert on them.
public actor MockNotificationRepository: NotificationRepository {
    public static let sampleToken = "mock-fcm-token"

    private let grantsPermission: Bool
    /// Explicit (prompting) requests.
    public private(set) var authorizationRequests = 0
    /// Silent provisional requests.
    public private(set) var provisionalRequests = 0
    public private(set) var status: NotificationAuthorizationStatus
    /// `device_tokens/{userId}/tokens/{token}` → `platform`.
    public private(set) var savedTokens: [String: [String: String]] = [:]
    public private(set) var badgeCount = 0

    public init(grantsPermission: Bool = true, status: NotificationAuthorizationStatus = .notDetermined) {
        self.grantsPermission = grantsPermission
        self.status = status
    }

    public func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        status = grantsPermission ? .authorized : .denied
        return grantsPermission
    }

    public func requestProvisionalAuthorization() async throws -> Bool {
        provisionalRequests += 1
        if status == .notDetermined, grantsPermission { status = .provisional }
        return grantsPermission
    }

    public func authorizationStatus() async -> NotificationAuthorizationStatus { status }

    public func saveDeviceToken(userId: String) async throws {
        guard grantsPermission else { return }
        savedTokens[userId, default: [:]][Self.sampleToken] = "ios"
    }

    public func setBadgeCount(_ count: Int) async { badgeCount = count }
}
