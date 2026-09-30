import Foundation
import Observation
import TappedData

/// `confirm_email_bloc`: email/password sign-ups verify their address before onboarding.
@Observable
@MainActor
final class ConfirmEmailViewModel {
    static let resendCooldown: Duration = .seconds(30)

    let email: String
    private(set) var isChecking = false
    private(set) var isResending = false
    private(set) var didResend = false
    var errorMessage: String?

    private let auth: any AuthRepository

    init(dependencies: Dependencies, authUser: AuthUser) {
        auth = dependencies.auth
        email = authUser.email ?? ""
    }

    func resend() async {
        guard !isResending, !didResend else { return }
        isResending = true
        errorMessage = nil
        defer { isResending = false }
        do {
            try await auth.sendEmailVerification()
            didResend = true
        } catch {
            errorMessage = error.localizedDescription.lowercased()
        }
    }

    /// Reloads the Firebase user; `AppSession` moves on to onboarding once `isEmailVerified` flips.
    /// Returns whether the email is now verified.
    @discardableResult
    func checkVerification(session: AppSession?) async -> Bool {
        guard !isChecking else { return false }
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }
        do {
            let user = try await auth.reloadUser()
            guard user?.isEmailVerified == true else {
                errorMessage = "we couldn't confirm your email yet. tap the link in your inbox first"
                return false
            }
            try await session?.reloadAuthUser()
            return true
        } catch {
            errorMessage = error.localizedDescription.lowercased()
            return false
        }
    }

    func resetResendCooldown() { didResend = false }
}
