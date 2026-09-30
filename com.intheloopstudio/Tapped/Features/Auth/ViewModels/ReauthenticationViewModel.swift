import Foundation
import Observation
import TappedData

/// Confirms the user's identity before destructive actions (delete account, change email). Firebase rejects
/// those with `requiresRecentLogin` otherwise. Methods come from the account's linked providers.
@Observable
@MainActor
final class ReauthenticationViewModel {
    private(set) var methods: [ReauthMethod] = [.password]
    private(set) var email = ""
    var password = ""
    private(set) var isSubmitting = false
    var errorMessage: String?

    private let auth: any AuthRepository

    init(dependencies: Dependencies) {
        auth = dependencies.auth
    }

    var canSubmitPassword: Bool { !password.isEmpty && !isSubmitting }

    func load() async {
        guard let user = await auth.getAuthUser() else { return }
        methods = user.reauthMethods
        email = user.email ?? ""
    }

    /// Returns true when the user re-authenticated and the destructive action may proceed.
    func reauthenticate(with method: ReauthMethod) async -> Bool {
        guard !isSubmitting else { return false }
        if method == .password, password.isEmpty { return false }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            switch method {
            case .password: try await auth.reauthenticateWithCredentials(email: email, password: password)
            case .apple: try await auth.reauthenticateWithApple()
            case .google: try await auth.reauthenticateWithGoogle()
            }
            return true
        } catch AuthError.cancelled {
            return false
        } catch {
            errorMessage = error.localizedDescription.lowercased()
            return false
        }
    }
}
