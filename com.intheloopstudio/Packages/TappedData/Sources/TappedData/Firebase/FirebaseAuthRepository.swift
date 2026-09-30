import AuthenticationServices
import CryptoKit
import Foundation
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseCore
@preconcurrency import GoogleSignIn
import UIKit

/// `lib/data/prod/firebase_auth_impl.dart`
public struct FirebaseAuthRepository: AuthRepository {
    public init() {}

    private var auth: Auth { Auth.auth() }

    public func authStateChanges() -> AsyncStream<AuthUser?> {
        AsyncStream { continuation in
            let handle = Auth.auth().addStateDidChangeListener { _, user in
                continuation.yield(user.map(AuthUser.init))
            }
            let box = ListenerBox(handle)
            continuation.onTermination = { _ in Auth.auth().removeStateDidChangeListener(box.value) }
        }
    }

    public func userChanges() -> AsyncStream<AuthUser?> {
        AsyncStream { continuation in
            let handle = Auth.auth().addIDTokenDidChangeListener { _, user in
                continuation.yield(user.map(AuthUser.init))
            }
            let box = ListenerBox(handle)
            continuation.onTermination = { _ in Auth.auth().removeIDTokenDidChangeListener(box.value) }
        }
    }

    public func isSignedIn() async -> Bool { auth.currentUser != nil }

    public func getAuthUserId() async throws -> String {
        guard let uid = auth.currentUser?.uid else { throw AuthError.notSignedIn }
        return uid
    }

    public func getAuthUser() async -> AuthUser? { auth.currentUser.map(AuthUser.init) }

    public func getAdminClaim() async throws -> Bool {
        try await getCustomClaims().contains(.admin)
    }

    public func getCustomClaims() async throws -> [CustomClaim] {
        guard let user = auth.currentUser else { return [] }
        let claims = try await user.getIDTokenResult().claims
        return CustomClaim.allCases.filter { (claims[$0.rawValue] as? Bool) == true }
    }

    public func signInWithCredentials(email: String, password: String) async throws -> SignInPayload? {
        let result = try await mapAuthErrors { try await auth.signIn(withEmail: email, password: password) }
        return SignInPayload(result.user)
    }

    public func reauthenticateWithCredentials(email: String, password: String) async throws {
        guard let user = auth.currentUser else { throw AuthError.notSignedIn }
        _ = try await mapAuthErrors { try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: email, password: password)) }
    }

    public func signUpWithCredentials(email: String, password: String) async throws -> SignInPayload? {
        let result = try await mapAuthErrors { try await auth.createUser(withEmail: email, password: password) }
        return SignInPayload(result.user)
    }

    public func signInWithGoogle() async throws -> SignInPayload? {
        let tokens = try await mapAuthErrors { try await GoogleSignInFlow.run() }
        let credential = GoogleAuthProvider.credential(withIDToken: tokens.idToken, accessToken: tokens.accessToken)
        let result = try await mapAuthErrors { try await auth.signIn(with: credential) }
        return SignInPayload(result.user)
    }

    public func reauthenticateWithGoogle() async throws {
        guard let user = auth.currentUser else { throw AuthError.notSignedIn }
        let tokens = try await mapAuthErrors { try await GoogleSignInFlow.run() }
        let credential = GoogleAuthProvider.credential(withIDToken: tokens.idToken, accessToken: tokens.accessToken)
        _ = try await mapAuthErrors { try await user.reauthenticate(with: credential) }
    }

    public func signInWithApple() async throws -> SignInPayload? {
        let nonce = AppleNonce.random()
        let apple = try await mapAuthErrors { try await AppleSignInFlow.run(hashedNonce: AppleNonce.sha256(nonce)) }
        let credential = OAuthProvider.appleCredential(withIDToken: apple.idToken, rawNonce: nonce, fullName: apple.fullName)
        let result = try await mapAuthErrors { try await auth.signIn(with: credential) }
        return SignInPayload(result.user)
    }

    public func reauthenticateWithApple() async throws {
        guard let user = auth.currentUser else { throw AuthError.notSignedIn }
        let nonce = AppleNonce.random()
        let apple = try await mapAuthErrors { try await AppleSignInFlow.run(hashedNonce: AppleNonce.sha256(nonce)) }
        let credential = OAuthProvider.appleCredential(withIDToken: apple.idToken, rawNonce: nonce, fullName: apple.fullName)
        _ = try await mapAuthErrors { try await user.reauthenticate(with: credential) }
    }

    public func logout() async throws {
        try auth.signOut()
        await MainActor.run { GIDSignIn.sharedInstance.signOut() }
    }

    public func recoverPassword(email: String) async throws {
        try await mapAuthErrors { try await auth.sendPasswordReset(withEmail: email) }
    }

    public func deleteUser() async throws {
        guard let user = auth.currentUser else { throw AuthError.notSignedIn }
        try await mapAuthErrors { try await user.delete() }
    }

    public func sendEmailVerification() async throws {
        guard let user = auth.currentUser else { throw AuthError.notSignedIn }
        try await mapAuthErrors { try await user.sendEmailVerification() }
    }

    public func reloadUser() async throws -> AuthUser? {
        guard let user = auth.currentUser else { return nil }
        try await mapAuthErrors { try await user.reload() }
        return auth.currentUser.map(AuthUser.init)
    }
}

/// Maps Firebase / Apple / Google errors onto `AuthError` so every surface shows the same lowercase copy.
private func mapAuthErrors<T>(_ operation: () async throws -> T) async throws -> T {
    do {
        return try await operation()
    } catch let error as AuthError {
        throw error
    } catch {
        throw AuthError(error)
    }
}

extension AuthError {
    init(_ error: any Error) {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain, nsError.code == ASAuthorizationError.canceled.rawValue {
            self = .cancelled
            return
        }
        if nsError.domain == kGIDSignInErrorDomain, nsError.code == GIDSignInError.canceled.rawValue {
            self = .cancelled
            return
        }
        guard nsError.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: nsError.code) else {
            self = .underlying(error.localizedDescription)
            return
        }
        self = switch code {
        case .wrongPassword, .invalidCredential, .userMismatch: .invalidCredentials
        case .emailAlreadyInUse, .credentialAlreadyInUse, .accountExistsWithDifferentCredential: .emailAlreadyInUse
        case .invalidEmail: .invalidEmail
        case .weakPassword: .weakPassword
        case .userNotFound: .userNotFound
        case .userDisabled: .userDisabled
        case .tooManyRequests: .tooManyRequests
        case .networkError: .network
        case .requiresRecentLogin: .requiresRecentLogin
        default: .underlying(error.localizedDescription)
        }
    }
}

private extension AuthUser {
    init(_ user: User) {
        self.init(
            uid: user.uid,
            email: user.email,
            displayName: user.displayName,
            isEmailVerified: user.isEmailVerified,
            providerIds: user.providerData.map(\.providerID)
        )
    }
}

private extension SignInPayload {
    init(_ user: User) {
        self.init(uid: user.uid, displayName: user.displayName ?? "", email: user.email ?? "")
    }
}

// MARK: - Google

private struct GoogleTokens: Sendable {
    let idToken: String
    let accessToken: String
}

@MainActor
private enum GoogleSignInFlow {
    static func run() async throws -> GoogleTokens {
        if GIDSignIn.sharedInstance.configuration == nil, let clientId = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        }
        guard let presenter = UIApplication.shared.topViewController else { throw AuthError.noPresentingWindow }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else { throw AuthError.missingIdentityToken }
        return GoogleTokens(idToken: idToken, accessToken: result.user.accessToken.tokenString)
    }
}

extension UIApplication {
    @MainActor
    var topViewController: UIViewController? {
        let scene = connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - Apple

private struct AppleCredential: Sendable {
    let idToken: String
    let fullName: PersonNameComponents?
}

private enum AppleNonce {
    static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
private final class AppleSignInFlow: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleCredential, any Error>?

    static func run(hashedNonce: String) async throws -> AppleCredential {
        let flow = AppleSignInFlow()
        return try await withCheckedThrowingContinuation { continuation in
            flow.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = flow
            controller.presentationContextProvider = flow
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            continuation?.resume(throwing: AuthError.missingIdentityToken)
            continuation = nil
            return
        }
        continuation?.resume(returning: AppleCredential(idToken: token, fullName: credential.fullName))
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.topViewController?.view.window ?? ASPresentationAnchor()
    }
}
