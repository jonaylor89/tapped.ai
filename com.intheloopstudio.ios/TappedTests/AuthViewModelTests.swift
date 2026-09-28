import TappedData
import Testing
@testable import Tapped

@MainActor
@Suite("Auth view models")
struct AuthViewModelTests {
    @Test func loginRequiresValidEmailAndPassword() {
        let model = LoginViewModel(dependencies: .mock())
        #expect(!model.canSubmit)
        model.email = "nova@example"
        model.password = "secret"
        #expect(!model.canSubmit)
        model.email = "nova@example.com"
        #expect(model.canSubmit)
    }

    @Test func loginSignsInThroughRepository() async {
        let dependencies = Dependencies.mock()
        let model = LoginViewModel(dependencies: dependencies)
        model.email = "nova@example.com"
        model.password = "secret"
        await model.signInWithEmail()
        #expect(model.errorMessage == nil)
        #expect(await dependencies.auth.isSignedIn())
    }

    @Test func loginSurfacesLowercaseErrors() async {
        let dependencies = Dependencies.mock()
        let model = LoginViewModel(dependencies: dependencies)
        model.email = "nova@example.com"
        model.password = "wrong"
        await model.signInWithEmail()
        #expect(model.errorMessage == model.errorMessage?.lowercased())
        #expect(model.errorMessage != nil)
        #expect(!(await dependencies.auth.isSignedIn()))
    }

    @Test func signupValidation() {
        let model = SignupViewModel(dependencies: .mock())
        model.email = "new@example.com"
        model.password = "12345"
        #expect(model.validationMessage == "password must be at least 6 characters")
        model.password = "123456"
        model.confirmPassword = "1234567"
        #expect(model.validationMessage == "passwords don't match")
        #expect(!model.canSubmit)
        model.confirmPassword = "123456"
        #expect(model.validationMessage == nil)
        #expect(model.canSubmit)
    }

    @Test func forgotPasswordMarksSent() async {
        let model = ForgotPasswordViewModel(dependencies: .mock())
        model.email = "nova@example.com"
        await model.sendResetLink()
        #expect(model.didSend)
    }
}
