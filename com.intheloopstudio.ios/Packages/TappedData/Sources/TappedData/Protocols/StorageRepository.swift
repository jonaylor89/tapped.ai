import Foundation

/// `lib/data/storage_repository.dart`. Only the calls native features use so far.
public protocol StorageRepository: Sendable {
    /// `images/opportunities/{uuid}.jpg`; returns the download URL.
    func uploadOpportunityFlier(opportunityId: String, jpegData: Data) async throws -> URL
}
