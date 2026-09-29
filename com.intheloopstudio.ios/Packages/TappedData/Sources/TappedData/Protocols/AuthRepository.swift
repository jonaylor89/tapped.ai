import Foundation

/// `lib/data/auth_repository.dart`
public protocol AuthRepository: Sendable {
    /// `authStateChanges`: emits on sign in / sign out.
    func authStateChanges() -> AsyncStream<AuthUser?>
    /// `userChanges`: also emits on token refresh and profile updates.
    func userChanges() -> AsyncStream<AuthUser?>
    func isSignedIn() async -> Bool
    func getAuthUserId() async throws -> String
    func getAuthUser() async -> AuthUser?
    func getAdminClaim() async throws -> Bool
    func getCustomClaims() async throws -> [CustomClaim]
    func signInWithCredentials(email: String, password: String) async throws -> SignInPayload?
    func reauthenticateWithCredentials(email: String, password: String) async throws
    func signUpWithCredentials(email: String, password: String) async throws -> SignInPayload?
    func signInWithGoogle() async throws -> SignInPayload?
    func reauthenticateWithGoogle() async throws
    func signInWithApple() async throws -> SignInPayload?
    func reauthenticateWithApple() async throws
    func logout() async throws
    func recoverPassword(email: String) async throws
    func deleteUser() async throws
    /// `confirm_email_bloc`: sends the Firebase verification email to the current user.
    func sendEmailVerification() async throws
    /// Refreshes the current user from the server (e.g. after they tap the verification link).
    func reloadUser() async throws -> AuthUser?
}

/// Snapshot of the Firebase `User` safe to pass across actors.
public struct AuthUser: Sendable, Hashable, Identifiable {
    public var uid: String
    public var email: String?
    public var displayName: String?
    public var isEmailVerified: Bool
    /// Firebase `providerData[].providerID`: `password`, `google.com`, `apple.com`.
    public var providerIds: [String]

    public var id: String { uid }

    public init(uid: String, email: String? = nil, displayName: String? = nil, isEmailVerified: Bool = false, providerIds: [String] = []) {
        self.uid = uid
        self.email = email
        self.displayName = displayName
        self.isEmailVerified = isEmailVerified
        self.providerIds = providerIds
    }

    /// Email/password accounts must verify their address; Apple/Google accounts are verified by the provider.
    public var requiresEmailVerification: Bool {
        !isEmailVerified && providerIds.allSatisfy { $0 == ReauthMethod.password.providerId }
    }

    /// Ways this user can re-authenticate before a destructive action, in display order.
    public var reauthMethods: [ReauthMethod] {
        let methods = ReauthMethod.allCases.filter { providerIds.contains($0.providerId) }
        return methods.isEmpty ? [.password] : methods
    }
}

public enum ReauthMethod: String, Sendable, CaseIterable, Hashable, Identifiable {
    case password
    case apple
    case google

    public var id: String { rawValue }

    public var providerId: String {
        switch self {
        case .password: "password"
        case .apple: "apple.com"
        case .google: "google.com"
        }
    }
}

public struct SignInPayload: Sendable, Hashable {
    public var uid: String
    public var displayName: String
    public var email: String

    public init(uid: String, displayName: String, email: String) {
        self.uid = uid
        self.displayName = displayName
        self.email = email
    }
}

public enum CustomClaim: String, Sendable, CaseIterable, Hashable {
    case admin
    case booker
}

public enum AuthError: LocalizedError, Sendable, Equatable {
    case notSignedIn
    case invalidCredentials
    case missingIdentityToken
    case noPresentingWindow
    case emailAlreadyInUse
    case invalidEmail
    case weakPassword
    case userNotFound
    case userDisabled
    case tooManyRequests
    case network
    case requiresRecentLogin
    case cancelled
    case underlying(String)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: "you're not signed in"
        case .invalidCredentials: "invalid email or password"
        case .missingIdentityToken: "couldn't get an identity token"
        case .noPresentingWindow: "couldn't present sign in"
        case .emailAlreadyInUse: "an account already exists with that email"
        case .invalidEmail: "enter a valid email"
        case .weakPassword: "password must be at least 6 characters"
        case .userNotFound: "no account found with that email"
        case .userDisabled: "this account has been disabled"
        case .tooManyRequests: "too many attempts. try again in a few minutes"
        case .network: "you're offline. check your connection and try again"
        case .requiresRecentLogin: "please confirm it's you to continue"
        case .cancelled: "sign in was cancelled"
        case let .underlying(message): message.lowercased()
        }
    }
}
