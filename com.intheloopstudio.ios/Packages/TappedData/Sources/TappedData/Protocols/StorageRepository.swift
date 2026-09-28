import Foundation

/// `lib/data/storage_repository.dart` (profile pictures only; other uploads belong to their feature sessions).
public protocol StorageRepository: Sendable {
    /// Uploads to `images/users/{userId}/userProfile_{uuid}.jpg` and returns the download URL.
    func uploadProfilePicture(userId: String, imageData: Data) async throws -> URL
}
