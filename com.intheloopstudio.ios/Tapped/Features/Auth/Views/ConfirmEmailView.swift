import SwiftUI
import TappedData
import TappedUI

struct ConfirmEmailView: View {
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: ConfirmEmailViewModel

    init(dependencies: Dependencies, authUser: AuthUser) {
        _model = State(initialValue: ConfirmEmailViewModel(dependencies: dependencies, authUser: authUser))
    }

    var body: some View {
        Form {
            AuthHeader("verify your email", subtitle: "we sent a link to \(model.email). tap it, then come back here to finish setting up.")

            Section {
                AuthSubmitButton(title: "i've verified my email", isLoading: model.isChecking, isEnabled: !model.isChecking) {
                    Task { await model.checkVerification(session: session) }
                }
            } footer: {
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(TappedColors.error)
                }
            }

            Section {
                Button {
                    Task { await model.resend() }
                } label: {
                    Label(model.didResend ? "email sent" : "resend email", systemImage: model.didResend ? "checkmark" : "envelope")
                }
                .disabled(model.isResending || model.didResend)
                Button("use a different account", role: .destructive) {
                    Task { await session?.signOut() }
                }
            } footer: {
                Text("can't find it? check your spam folder.")
            }
        }
        .navigationTitle("confirm email")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            // Coming back from Mail: check silently.
            if phase == .active { Task { await model.checkVerification(session: session) } }
        }
        .task(id: model.didResend) {
            guard model.didResend else { return }
            try? await Task.sleep(for: ConfirmEmailViewModel.resendCooldown)
            model.resetResendCooldown()
        }
    }
}

#Preview {
    NavigationStack {
        ConfirmEmailView(dependencies: .mock(onboarding: true, emailVerified: false), authUser: MockAuthRepository.newUser)
    }
}

#Preview("dark") {
    NavigationStack {
        ConfirmEmailView(dependencies: .mock(onboarding: true, emailVerified: false), authUser: MockAuthRepository.newUser)
    }
    .preferredColorScheme(.dark)
}
