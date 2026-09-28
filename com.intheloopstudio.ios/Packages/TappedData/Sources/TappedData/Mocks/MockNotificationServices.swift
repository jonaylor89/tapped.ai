import Foundation

/// Records permission prompts, saved tokens and badge updates so tests can assert on them.
public actor MockNotificationRepository: NotificationRepository {
    public static let sampleToken = "mock-fcm-token"

    private let grantsPermission: Bool
    public private(set) var authorizationRequests = 0
    /// `device_tokens/{userId}/tokens/{token}` → `platform`.
    public private(set) var savedTokens: [String: [String: String]] = [:]
    public private(set) var badgeCount = 0

    public init(grantsPermission: Bool = true) {
        self.grantsPermission = grantsPermission
    }

    public func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        return grantsPermission
    }

    public func saveDeviceToken(userId: String) async throws {
        guard grantsPermission else { return }
        savedTokens[userId, default: [:]][Self.sampleToken] = "ios"
    }

    public func setBadgeCount(_ count: Int) async { badgeCount = count }
}

public actor MockStorageRepository: StorageRepository {
    public private(set) var uploads: [String: Data] = [:]

    public init() {}

    public func uploadProfilePicture(userId: String, imageData: Data) async throws -> URL {
        let path = "images/users/\(userId)/userProfile_\(uploads.count).jpg"
        uploads[path] = imageData
        return URL(string: "https://storage.example.com/\(path)")!
    }
}
