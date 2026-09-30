import Foundation
import Observation
import TappedData
import TappedDomain

/// Port of `interested_users_view.dart`.
@Observable
@MainActor
final class InterestedUsersViewModel {
    let opportunity: Opportunity
    private(set) var users: [UserModel] = []
    private(set) var isLoading = true
    private(set) var failed = false

    private let database: any DatabaseRepository

    init(dependencies: Dependencies, opportunity: Opportunity) {
        self.opportunity = opportunity
        database = dependencies.database
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            users = try await database.getInterestedUsers(opportunity)
            failed = false
        } catch {
            failed = true
        }
    }
}
