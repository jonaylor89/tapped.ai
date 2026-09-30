import Foundation

/// `lib/data/storage_repository.dart` (the uploads native features use).
public protocol StorageRepository: Sendable {
    /// Uploads an already-compressed JPEG to `images/users/{userId}/userProfile_{uuid}.jpg` and returns its download URL.
    func uploadProfilePicture(userId: String, imageData: Data) async throws -> URL
    /// `images/opportunities/{opportunityId}.jpg`; returns the download URL.
    func uploadOpportunityFlier(opportunityId: String, jpegData: Data) async throws -> URL
}
