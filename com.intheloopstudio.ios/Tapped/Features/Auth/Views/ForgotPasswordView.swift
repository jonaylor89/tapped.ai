import SwiftUI
import TappedData
import TappedUI

struct ForgotPasswordView: View {
    @State private var model: ForgotPasswordViewModel

    init(dependencies: Dependencies) {
        _model = State(initialValue: ForgotPasswordViewModel(dependencies: dependencies))
    }

    var body: some View {
        Form {
            if model.didSend {
                AuthHeader("check your inbox", subtitle: "we sent a password reset link to \(model.email)")
            } else {
                AuthHeader("reset password", subtitle: "enter your email and we'll send you a reset link")
                Section {
                    TextField("email", text: $model.email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .onSubmit { Task { await model.sendResetLink() } }
                } footer: {
                    if let error = model.errorMessage {
                        Text(error).foregroundStyle(TappedColors.error)
                    }
                }
                Section {
                    AuthSubmitButton(title: "send reset link", isLoading: model.isSubmitting, isEnabled: model.canSubmit) {
                        Task { await model.sendResetLink() }
                    }
                }
            }
        }
        .navigationTitle("forgot password")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { ForgotPasswordView(dependencies: .mock()) }
}
