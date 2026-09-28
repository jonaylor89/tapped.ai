import SwiftUI
import TappedData
import TappedUI

/// Stepped onboarding after sign up (`lib/ui/onboarding/onboarding_view.dart`).
/// Forms per step; floating glass chrome for progress and the back / skip / continue controls.
struct OnboardingView: View {
    @Environment(AppSession.self) private var session: AppSession?
    @State private var model: OnboardingViewModel

    init(dependencies: Dependencies, initialStep: OnboardingViewModel.Step? = nil) {
        let model = OnboardingViewModel(dependencies: dependencies, initialStep: initialStep ?? .name)
        if initialStep != nil { model.fillSampleAnswers() }
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            OnboardingStepContent(model: model)
                .id(model.step)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .navigationTitle("step \(model.stepIndex + 1) of \(OnboardingViewModel.Step.allCases.count)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .safeAreaInset(edge: .bottom) { controls }
        }
        .animation(GlassMotion.ease, value: model.step)
        .alert("uh oh", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("ok", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.canGoBack {
            ToolbarItem(placement: .topBarLeading) {
                Button("back", systemImage: "chevron.backward") { model.back() }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await session?.signOut() }
                }
            } label: {
                Label("more", systemImage: "ellipsis")
            }
        }
    }

    private var controls: some View {
        VStack(spacing: TappedSpacing.md) {
            ProgressView(value: model.progress)
                .tint(TappedColors.accent)
                .accessibilityLabel("onboarding progress")
                .accessibilityValue("step \(model.stepIndex + 1) of \(OnboardingViewModel.Step.allCases.count)")
            GlassEffectContainer(spacing: TappedSpacing.md) {
                HStack(spacing: TappedSpacing.md) {
                    if model.step.isSkippable {
                        Button { model.skip() } label: {
                            Text("skip").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                    Button(action: primaryAction) {
                        Group {
                            if model.isSubmitting {
                                ProgressView()
                            } else {
                                Text(model.step == .complete ? "let's go" : "continue")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!model.canContinue)
                }
                .controlSize(.large)
            }
        }
        .padding(.horizontal, GlassMetrics.edgeInset)
        .padding(.bottom, TappedSpacing.sm)
    }

    private func primaryAction() {
        guard model.step == .complete else {
            model.next()
            return
        }
        Task {
            if let user = await model.finish() {
                await session?.completeOnboarding(user)
            }
        }
    }
}

#Preview("name") {
    OnboardingView(dependencies: .mock(onboarding: true))
}

#Preview("genres dark") {
    OnboardingView(dependencies: .mock(onboarding: true), initialStep: .genres)
        .preferredColorScheme(.dark)
}

#Preview("complete") {
    OnboardingView(dependencies: .mock(onboarding: true), initialStep: .complete)
}
