import Foundation

/// In-memory auth. Any email/password signs in except password `wrong`.
/// Sign up creates a fresh, unverified account with no `users/{uid}` document (→ confirm email → onboarding).
public actor MockAuthRepository: AuthRepository {
    private var user: AuthUser?
    private var claims: [CustomClaim]
    private var continuations: [UUID: AsyncStream<AuthUser?>.Continuation] = [:]
    /// When true, `reloadUser()` marks the email verified, as if the user tapped the link.
    private let verifiesOnReload: Bool
    public private(set) var verificationEmailsSent = 0
    public private(set) var reauthentications: [ReauthMethod] = []
    public private(set) var passwordResets: [String] = []

    public static let sampleUser = AuthUser(uid: "performer-nova", email: "nova@example.com", displayName: "DJ Nova", isEmailVerified: true, providerIds: ["password"])
    /// Signed in but not onboarded yet (no `users/{uid}` document in `MockDatabaseRepository`).
    public static let newUser = AuthUser(uid: "new-artist", email: "new@example.com", isEmailVerified: true, providerIds: ["password"])

    public init(signedInAs user: AuthUser? = nil, claims: [CustomClaim] = [], verifiesOnReload: Bool = true) {
        self.user = user
        self.claims = claims
        self.verifiesOnReload = verifiesOnReload
    }

    public nonisolated func authStateChanges() -> AsyncStream<AuthUser?> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(id, continuation) }
            continuation.onTermination = { _ in Task { await self.unregister(id) } }
        }
    }

    public nonisolated func userChanges() -> AsyncStream<AuthUser?> { authStateChanges() }

    private func register(_ id: UUID, _ continuation: AsyncStream<AuthUser?>.Continuation) {
        continuations[id] = continuation
        continuation.yield(user)
    }

    private func unregister(_ id: UUID) { continuations[id] = nil }

    private func set(_ newUser: AuthUser?) {
        user = newUser
        for continuation in continuations.values { continuation.yield(newUser) }
    }

    public func isSignedIn() async -> Bool { user != nil }

    public func getAuthUserId() async throws -> String {
        guard let user else { throw AuthError.notSignedIn }
        return user.uid
    }

    public func getAuthUser() async -> AuthUser? { user }
    public func getAdminClaim() async throws -> Bool { claims.contains(.admin) }
    public func getCustomClaims() async throws -> [CustomClaim] { claims }

    public func signInWithCredentials(email: String, password: String) async throws -> SignInPayload? {
        guard password != "wrong", !email.isEmpty else { throw AuthError.invalidCredentials }
        let signedIn = AuthUser(uid: Self.sampleUser.uid, email: email, displayName: Self.sampleUser.displayName, isEmailVerified: true, providerIds: ["password"])
        set(signedIn)
        return SignInPayload(uid: signedIn.uid, displayName: signedIn.displayName ?? "", email: email)
    }

    public func reauthenticateWithCredentials(email: String, password: String) async throws {
        guard password != "wrong" else { throw AuthError.invalidCredentials }
        reauthentications.append(.password)
    }

    public func signUpWithCredentials(email: String, password: String) async throws -> SignInPayload? {
        guard !email.isEmpty else { throw AuthError.invalidEmail }
        guard password.count >= 6 else { throw AuthError.weakPassword }
        if email == Self.sampleUser.email { throw AuthError.emailAlreadyInUse }
        let created = AuthUser(uid: Self.newUser.uid, email: email, isEmailVerified: false, providerIds: ["password"])
        set(created)
        return SignInPayload(uid: created.uid, displayName: "", email: email)
    }

    public func signInWithGoogle() async throws -> SignInPayload? {
        try await signInWithCredentials(email: Self.sampleUser.email ?? "", password: "google")
    }

    public func reauthenticateWithGoogle() async throws { reauthentications.append(.google) }

    public func signInWithApple() async throws -> SignInPayload? {
        try await signInWithCredentials(email: Self.sampleUser.email ?? "", password: "apple")
    }

    public func reauthenticateWithApple() async throws { reauthentications.append(.apple) }
    public func logout() async throws { set(nil) }

    public func recoverPassword(email: String) async throws {
        guard !email.isEmpty else { throw AuthError.invalidEmail }
        passwordResets.append(email)
    }

    public func deleteUser() async throws { set(nil) }

    public func sendEmailVerification() async throws {
        guard user != nil else { throw AuthError.notSignedIn }
        verificationEmailsSent += 1
    }

    public func reloadUser() async throws -> AuthUser? {
        guard var current = user else { return nil }
        if verifiesOnReload, !current.isEmailVerified {
            current.isEmailVerified = true
            set(current)
        }
        return current
    }
}
