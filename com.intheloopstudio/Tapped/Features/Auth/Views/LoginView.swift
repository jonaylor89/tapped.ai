import SwiftUI
import TappedData
import TappedUI

struct LoginView: View {
    @State private var model: LoginViewModel
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    init(dependencies: Dependencies) {
        _model = State(initialValue: LoginViewModel(dependencies: dependencies))
    }

    var body: some View {
        Form {
            AuthHeader("welcome back", subtitle: "log in to keep getting booked")

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
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await model.signInWithEmail() } }
            } footer: {
                HStack {
                    if let error = model.errorMessage {
                        Text(error).foregroundStyle(TappedColors.error)
                    }
                    Spacer()
                    NavigationLink("forgot password?", value: Route.forgotPassword)
                        .font(TappedTypography.label)
                }
            }

            Section {
                AuthSubmitButton(title: "log in", isLoading: model.isSubmitting, isEnabled: model.canSubmit) {
                    Task { await model.signInWithEmail() }
                }
            }

            Section {
                SocialSignInButtons(
                    isDisabled: model.isSubmitting,
                    apple: { Task { await model.signInWithApple() } },
                    google: { Task { await model.signInWithGoogle() } }
                )
            } header: {
                Text("or").frame(maxWidth: .infinity)
            }

            Section {
                NavigationLink(value: Route.signUp) {
                    Text("new to tapped? **create an account**")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("log in")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { LoginView(dependencies: .mock()).tappedRouteDestinations() }
}
