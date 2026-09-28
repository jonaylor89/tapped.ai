import SwiftUI
import TappedData
import TappedUI

/// Sheet shown before destructive actions. Present with `.reauthenticationSheet(isPresented:reason:onSuccess:)`.
struct ReauthenticationView: View {
    let reason: String
    let onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: ReauthenticationViewModel

    init(dependencies: Dependencies, reason: String, onSuccess: @escaping () -> Void) {
        self.reason = reason
        self.onSuccess = onSuccess
        _model = State(initialValue: ReauthenticationViewModel(dependencies: dependencies))
    }

    var body: some View {
        Form {
            AuthHeader("confirm it's you", subtitle: reason)

            if model.methods.contains(.password) {
                Section {
                    LabeledContent("email", value: model.email)
                    SecureField("password", text: $model.password)
                        .textContentType(.password)
                        .submitLabel(.continue)
                        .onSubmit { submit(.password) }
                } footer: {
                    if let error = model.errorMessage {
                        Text(error).foregroundStyle(TappedColors.error)
                    }
                }
                Section {
                    AuthSubmitButton(title: "continue", isLoading: model.isSubmitting, isEnabled: model.canSubmitPassword) {
                        submit(.password)
                    }
                }
            }

            let social = model.methods.filter { $0 != .password }
            if !social.isEmpty {
                Section {
                    ForEach(social) { method in
                        Button {
                            submit(method)
                        } label: {
                            Label(
                                method == .apple ? "continue with apple" : "continue with google",
                                systemImage: method == .apple ? "apple.logo" : "g.circle.fill"
                            )
                        }
                        .disabled(model.isSubmitting)
                    }
                } footer: {
                    if !model.methods.contains(.password), let error = model.errorMessage {
                        Text(error).foregroundStyle(TappedColors.error)
                    }
                }
            }
        }
        .navigationTitle("confirm it's you")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("cancel", systemImage: "xmark") { dismiss() }
            }
        }
        .task { await model.load() }
    }

    private func submit(_ method: ReauthMethod) {
        Task {
            if await model.reauthenticate(with: method) {
                dismiss()
                onSuccess()
            }
        }
    }
}

extension View {
    /// Re-authenticates before running `onSuccess` (e.g. `auth.deleteUser()`).
    func reauthenticationSheet(isPresented: Binding<Bool>, reason: String, onSuccess: @escaping () -> Void) -> some View {
        modifier(ReauthenticationSheetModifier(isPresented: isPresented, reason: reason, onSuccess: onSuccess))
    }
}

private struct ReauthenticationSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let reason: String
    let onSuccess: () -> Void
    @Environment(\.dependencies) private var dependencies

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            NavigationStack {
                ReauthenticationView(dependencies: dependencies, reason: reason, onSuccess: onSuccess)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

#Preview {
    NavigationStack {
        ReauthenticationView(dependencies: .mock(signedIn: true), reason: "enter your password to delete your account") {}
    }
}

#Preview("dark") {
    NavigationStack {
        ReauthenticationView(dependencies: .mock(signedIn: true), reason: "enter your password to delete your account") {}
    }
    .preferredColorScheme(.dark)
}
