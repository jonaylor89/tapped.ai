import Foundation
@preconcurrency import FirebaseStorage

/// `lib/data/prod/firebase_storage_impl.dart`.
public struct FirebaseStorageRepository: StorageRepository {
    public init() {}

    public func uploadProfilePicture(userId: String, imageData: Data) async throws -> URL {
        let prefix = userId.isEmpty ? "images/users" : "images/users/\(userId)"
        let ref = Storage.storage().reference().child("\(prefix)/userProfile_\(UUID().uuidString.lowercased()).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        return try await ref.downloadURL()
    }

    public func uploadOpportunityFlier(opportunityId: String, jpegData: Data) async throws -> URL {
        let ref = Storage.storage().reference().child("images/opportunities/\(opportunityId).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(jpegData, metadata: metadata)
        return try await ref.downloadURL()
    }
}
