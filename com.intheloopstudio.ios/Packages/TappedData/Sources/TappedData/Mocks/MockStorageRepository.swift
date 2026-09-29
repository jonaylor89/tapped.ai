import Foundation

/// Profile pictures are written to the temporary directory and returned as `file://` URLs so `AsyncImage`
/// can render them; fliers get a deterministic fake download URL.
public actor MockStorageRepository: StorageRepository {
    /// Uploaded bytes keyed by file path (profile pictures) or opportunity id (fliers).
    public private(set) var uploads: [String: Data] = [:]

    public init() {}

    public func uploadProfilePicture(userId: String, imageData: Data) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "images/users/\(userId)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "userProfile_\(userId)_\(UUID().uuidString.lowercased()).jpg")
        try imageData.write(to: url)
        uploads[url.path] = imageData
        return url
    }

    public func uploadOpportunityFlier(opportunityId: String, jpegData: Data) async throws -> URL {
        uploads[opportunityId] = jpegData
        return URL(string: "https://example.com/images/opportunities/\(opportunityId).jpg")!
    }
}
