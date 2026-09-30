import Foundation
import Observation
import TappedData
import TappedDomain
import UIKit

@Observable
@MainActor
final class ShareProfileViewModel {
    let userId: String
    private(set) var user: UserModel?
    private(set) var errorMessage: String?
    var toast: String?

    private let database: any DatabaseRepository
    private let analytics: any AnalyticsRepository

    init(dependencies: Dependencies, userId: String, user: UserModel?) {
        self.userId = userId
        self.user = user
        database = dependencies.database
        analytics = dependencies.analytics
    }

    func load() async {
        guard user == nil else { return }
        errorMessage = nil
        do {
            user = try await database.getUserById(userId)
            if user == nil { errorMessage = "this profile doesn't exist" }
        } catch {
            errorMessage = "couldn't load profile"
        }
    }

    func copyLink() {
        guard let user else { return }
        UIPasteboard.general.url = user.profileURL
        toast = "link copied"
        Task { await analytics.track("copy_profile_link") }
    }
}
