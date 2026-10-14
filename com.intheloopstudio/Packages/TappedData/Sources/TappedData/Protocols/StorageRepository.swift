import Foundation

/// Media uploads. Live uploads go to R2 through `POST /app/v1/uploads` (see `TappedAPIStorageRepository`).
public protocol StorageRepository: Sendable {
    /// Uploads an already-compressed image to `users/{userId}/avatar/{sha}.{ext}` and returns its public URL.
    func uploadProfilePicture(userId: String, imageData: Data) async throws -> URL
    /// `opportunities/{opportunityId}/flier/{sha}.{ext}`; returns the public URL.
    func uploadOpportunityFlier(opportunityId: String, jpegData: Data) async throws -> URL
}
