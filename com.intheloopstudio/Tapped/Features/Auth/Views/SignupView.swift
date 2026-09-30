import SwiftUI
import TappedData
import TappedUI

struct SignupView: View {
    @State private var model: SignupViewModel
    @FocusState private var focus: Field?

    private enum Field { case email, password, confirm }

    init(dependencies: Dependencies) {
        _model = State(initialValue: SignupViewModel(dependencies: dependencies))
    }

    var body: some View {
        Form {
            AuthHeader("create an account", subtitle: "first, create an account to get you set up")

            Section {
                SocialSignInButtons(
                    isDisabled: model.isSubmitting,
                    apple: { Task { await model.signInWithApple() } },
                    google: { Task { await model.signInWithGoogle() } }
                )
            }

            Section {
                TextField("email", text: $model.email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                SecureField("password", text: $model.password)
                    .textContentType(.newPassword)
                    .focused($focus, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focus = .confirm }
                SecureField("confirm password", text: $model.confirmPassword)
                    .textContentType(.newPassword)
                    .focused($focus, equals: .confirm)
                    .submitLabel(.join)
                    .onSubmit { Task { await model.createAccount() } }
            } header: {
                Text("or sign up with email")
            } footer: {
                if let message = model.errorMessage ?? model.validationMessage {
                    Text(message).foregroundStyle(TappedColors.error)
                }
            }

            Section {
                AuthSubmitButton(title: "create account", isLoading: model.isSubmitting, isEnabled: model.canSubmit) {
                    Task { await model.createAccount() }
                }
            } footer: {
                Text("by continuing you agree to our [terms of service](https://tapped.ai/terms) and [privacy policy](https://tapped.ai/privacy)")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("sign up")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SignupView(dependencies: .mock()) }
}
