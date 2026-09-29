import SwiftUI
import TappedData
import TappedUI

/// Four-step onboarding after sign up (`lib/ui/onboarding/onboarding_view.dart`): name → what you do → genres →
/// location. Forms per step; floating glass chrome for progress and the back / skip / continue controls.
struct OnboardingView: View {
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: OnboardingViewModel

    init(dependencies: Dependencies, initialStep: OnboardingViewModel.Step? = nil) {
        let model = OnboardingViewModel(dependencies: dependencies, initialStep: initialStep ?? .name)
        if initialStep != nil { model.fillSampleAnswers() }
        _model = State(initialValue: model)
    }

    private var stepLabel: String { "step \(model.stepNumber) of \(OnboardingViewModel.stepCount)" }

    var body: some View {
        NavigationStack {
            OnboardingStepContent(model: model)
                .id(model.step)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .navigationTitle(stepLabel)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .safeAreaBar(edge: .bottom) { controls }
                .scrollEdgeEffectStyle(.hard, for: .bottom)
        }
        .animation(GlassMotion.ease, value: model.step)
        .alert("Something Went Wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
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
        if dynamicTypeSize.isAccessibilitySize, model.step.isSkippable {
            ToolbarItem(placement: .topBarTrailing) {
                Button(model.step.isLast ? "skip for now" : "skip", action: skip)
                    .disabled(model.isSubmitting)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await session?.signOut() }
                }
            } label: {
                Label("more", systemImage: "ellipsis")
            }
        }
    }

    private var controls: some View {
        VStack(spacing: TappedSpacing.md) {
            OnboardingProgress(step: model.stepNumber, count: OnboardingViewModel.stepCount)
            GlassEffectContainer(spacing: TappedSpacing.md) {
                HStack(spacing: TappedSpacing.md) {
                    if model.step.isSkippable, !dynamicTypeSize.isAccessibilitySize {
                        Button(action: skip) {
                            Text(model.step.isLast ? "skip for now" : "skip").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .disabled(model.isSubmitting)
                    }
                    Button(action: primaryAction) {
                        Group {
                            if model.isSubmitting {
                                ProgressView()
                            } else {
                                Text(model.step.isLast ? "let's go" : "continue")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!model.canContinue)
                }
                .controlSize(.large)
            }
            if model.step.isLast {
                Text("by tapping let's go you agree to the [eula](\(OnboardingViewModel.eulaURL.absoluteString)) and [privacy policy](\(OnboardingViewModel.privacyURL.absoluteString)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .tint(TappedColors.accent)
            }
        }
        .padding(.horizontal, GlassMetrics.edgeInset)
        .padding(.bottom, TappedSpacing.sm)
        // Pinned chrome stops growing at AX2 so the step itself keeps most of the screen; skip moves to the toolbar.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private func primaryAction() {
        guard model.step.isLast else {
            model.next()
            return
        }
        finish()
    }

    private func skip() {
        if model.skip() { finish() }
    }

    private func finish() {
        Task {
            if let user = await model.finish() {
                await session?.completeOnboarding(user)
            }
        }
    }
}

/// Four segments, filled up to the current step.
private struct OnboardingProgress: View {
    let step: Int
    let count: Int

    var body: some View {
        HStack(spacing: TappedSpacing.xs) {
            ForEach(1...count, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? AnyShapeStyle(TappedColors.accent) : AnyShapeStyle(.quaternary))
                    .frame(height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("onboarding progress")
        .accessibilityValue("step \(step) of \(count)")
    }
}

#Preview("name") {
    OnboardingView(dependencies: .mock(onboarding: true))
}

#Preview("genres dark") {
    OnboardingView(dependencies: .mock(onboarding: true), initialStep: .genres)
        .preferredColorScheme(.dark)
}

#Preview("location") {
    OnboardingView(dependencies: .mock(onboarding: true), initialStep: .location)
}
