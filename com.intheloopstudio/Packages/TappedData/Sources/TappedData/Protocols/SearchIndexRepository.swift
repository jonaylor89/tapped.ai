/// Keeps the signed-in user's search document in step with `users/{uid}`.
public protocol SearchIndexRepository: Sendable {
    func syncCurrentUser() async throws
}
