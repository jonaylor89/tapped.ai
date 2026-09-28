import Foundation

/// In-memory auth. Any email/password signs in except password `wrong`.
public actor MockAuthRepository: AuthRepository {
    private var user: AuthUser?
    private var claims: [CustomClaim]
    private var continuations: [UUID: AsyncStream<AuthUser?>.Continuation] = [:]

    public static let sampleUser = AuthUser(uid: "performer-nova", email: "nova@example.com", displayName: "DJ Nova", isEmailVerified: true)

    public init(signedInAs user: AuthUser? = nil, claims: [CustomClaim] = []) {
        self.user = user
        self.claims = claims
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
        let signedIn = AuthUser(uid: Self.sampleUser.uid, email: email, displayName: Self.sampleUser.displayName, isEmailVerified: true)
        set(signedIn)
        return SignInPayload(uid: signedIn.uid, displayName: signedIn.displayName ?? "", email: email)
    }

    public func reauthenticateWithCredentials(email: String, password: String) async throws {
        guard password != "wrong" else { throw AuthError.invalidCredentials }
    }

    public func signUpWithCredentials(email: String, password: String) async throws -> SignInPayload? {
        try await signInWithCredentials(email: email, password: password)
    }

    public func signInWithGoogle() async throws -> SignInPayload? {
        try await signInWithCredentials(email: Self.sampleUser.email ?? "", password: "google")
    }

    public func reauthenticateWithGoogle() async throws {}

    public func signInWithApple() async throws -> SignInPayload? {
        try await signInWithCredentials(email: Self.sampleUser.email ?? "", password: "apple")
    }

    public func reauthenticateWithApple() async throws {}
    public func logout() async throws { set(nil) }
    public func recoverPassword(email: String) async throws {}
    public func deleteUser() async throws { set(nil) }
}
