import Foundation
@preconcurrency import FirebaseFunctions

/// `StreamImpl.getToken`: the Stream user token minted by the `auth-chat` Firebase extension.
public enum FirebaseStreamToken {
    static let callableName = "ext-auth-chat-getStreamUserToken"

    @Sendable
    public static func fetch() async throws -> String {
        let result = try await Functions.functions().httpsCallable(callableName).call()
        guard let token = result.data as? String, !token.isEmpty else { throw ChatError.invalidToken }
        return token
    }
}
