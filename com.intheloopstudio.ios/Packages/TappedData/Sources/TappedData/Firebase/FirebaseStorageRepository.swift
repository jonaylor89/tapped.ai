import Foundation
@preconcurrency import FirebaseStorage

/// `lib/data/prod/firebase_storage_impl.dart` → `uploadProfilePicture`. Callers compress to JPEG first.
public struct FirebaseStorageRepository: StorageRepository {
    public init() {}

    public func uploadProfilePicture(userId: String, imageData: Data) async throws -> URL {
        let prefix = userId.isEmpty ? "images/users" : "images/users/\(userId)"
        let reference = Storage.storage().reference().child("\(prefix)/userProfile_\(UUID().uuidString.lowercased()).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await reference.putDataAsync(imageData, metadata: metadata)
        return try await reference.downloadURL()
    }
}
