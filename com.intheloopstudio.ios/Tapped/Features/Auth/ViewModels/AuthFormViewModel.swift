import Foundation
import Observation
import TappedData

/// Shared submission/error handling for the auth forms. Success is observed by `AppSession`
/// through `AuthRepository.authStateChanges()`, so view models never navigate on their own.
@Observable
@MainActor
class AuthFormViewModel {
    private(set) var isSubmitting = false
    var errorMessage: String?

    let auth: any AuthRepository
    let analytics: any AnalyticsRepository

    init(dependencies: Dependencies) {
        auth = dependencies.auth
        analytics = dependencies.analytics
    }

    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard let at = trimmed.firstIndex(of: "@") else { return false }
        return trimmed[trimmed.index(after: at)...].contains(".") && at != trimmed.startIndex
    }

    func signInWithApple() async {
        await submit(event: "sign_in", method: "apple") { try await self.auth.signInWithApple() }
    }

    func signInWithGoogle() async {
        await submit(event: "sign_in", method: "google") { try await self.auth.signInWithGoogle() }
    }

    func submit(event: String, method: String, _ operation: @escaping @MainActor () async throws -> SignInPayload?) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            if try await operation() != nil {
                await analytics.track(event, properties: ["method": .string(method)])
            }
        } catch {
            errorMessage = error.localizedDescription.lowercased()
        }
    }
}

@Observable
@MainActor
final class LoginViewModel: AuthFormViewModel {
    var email = ""
    var password = ""

    var canSubmit: Bool { Self.isValidEmail(email) && !password.isEmpty && !isSubmitting }

    func signInWithEmail() async {
        guard canSubmit else { return }
        let email = email.trimmingCharacters(in: .whitespaces)
        let password = password
        await submit(event: "sign_in", method: "email") {
            try await self.auth.signInWithCredentials(email: email, password: password)
        }
    }
}

@Observable
@MainActor
final class SignupViewModel: AuthFormViewModel {
    static let minimumPasswordLength = 6

    var email = ""
    var password = ""
    var confirmPassword = ""

    var passwordsMatch: Bool { password == confirmPassword }

    var validationMessage: String? {
        if !email.isEmpty, !Self.isValidEmail(email) { return "enter a valid email" }
        if !password.isEmpty, password.count < Self.minimumPasswordLength { return "password must be at least 6 characters" }
        if !confirmPassword.isEmpty, !passwordsMatch { return "passwords don't match" }
        return nil
    }

    var canSubmit: Bool {
        Self.isValidEmail(email) && password.count >= Self.minimumPasswordLength && passwordsMatch && !isSubmitting
    }

    func createAccount() async {
        guard canSubmit else { return }
        let email = email.trimmingCharacters(in: .whitespaces)
        let password = password
        await submit(event: "sign_up", method: "email") {
            let payload = try await self.auth.signUpWithCredentials(email: email, password: password)
            // `AppSession` holds the new account on the confirm-email gate until this link is tapped.
            try? await self.auth.sendEmailVerification()
            return payload
        }
    }
}

@Observable
@MainActor
final class ForgotPasswordViewModel: AuthFormViewModel {
    var email = ""
    private(set) var didSend = false

    var canSubmit: Bool { Self.isValidEmail(email) && !isSubmitting }

    func sendResetLink() async {
        guard canSubmit else { return }
        let email = email.trimmingCharacters(in: .whitespaces)
        await submit(event: "password_reset", method: "email") {
            try await self.auth.recoverPassword(email: email)
            self.didSend = true
            return nil
        }
    }
}
