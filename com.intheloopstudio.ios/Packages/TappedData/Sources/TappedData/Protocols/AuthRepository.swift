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
}

/// Snapshot of the Firebase `User` safe to pass across actors.
public struct AuthUser: Sendable, Hashable, Identifiable {
    public var uid: String
    public var email: String?
    public var displayName: String?
    public var isEmailVerified: Bool

    public var id: String { uid }

    public init(uid: String, email: String? = nil, displayName: String? = nil, isEmailVerified: Bool = false) {
        self.uid = uid
        self.email = email
        self.displayName = displayName
        self.isEmailVerified = isEmailVerified
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
    case underlying(String)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: "you're not signed in"
        case .invalidCredentials: "invalid email or password"
        case .missingIdentityToken: "couldn't get an identity token"
        case .noPresentingWindow: "couldn't present sign in"
        case let .underlying(message): message.lowercased()
        }
    }
}
