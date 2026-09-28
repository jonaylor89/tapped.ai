import Foundation

/// Writes uploads to the temporary directory and returns a `file://` URL so `AsyncImage` can render them.
public actor MockStorageRepository: StorageRepository {
    public private(set) var uploads: [URL] = []

    public init() {}

    public func uploadProfilePicture(userId: String, imageData: Data) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "images/users/\(userId)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "userProfile_\(userId)_\(UUID().uuidString.lowercased()).jpg")
        try imageData.write(to: url)
        uploads.append(url)
        return url
    }
}
