import Foundation

/// `lib/data/storage_repository.dart` (profile-picture subset).
public protocol StorageRepository: Sendable {
    /// Uploads an already-compressed JPEG to `images/users/{userId}/userProfile_{uuid}.jpg` and returns its download URL.
    func uploadProfilePicture(userId: String, imageData: Data) async throws -> URL
}
