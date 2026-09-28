import Foundation
import TappedDomain

extension Route {
    /// `TAPPED_MOCK_ROUTE` names for deterministic screenshots. `profile:<userId>` opens another user's profile.
    static func mockLaunch(_ name: String, currentUser: UserModel) -> Route? {
        let parts = name.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first {
        case "profile": return .profile(userId: parts.count > 1 ? parts[1] : currentUser.id, user: parts.count > 1 ? nil : currentUser)
        case "settings": return .settings
        case "activities": return .activities
        case "tasks": return .tasks
        case "shareProfile": return .shareProfile(userId: currentUser.id, user: currentUser)
        default: return nil
        }
    }
}
