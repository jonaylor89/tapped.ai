import SwiftUI
import TappedData
import TappedUI

/// Profile setup leads into premium activation, the fourth and final onboarding step.
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
                Button(model.step.isLastProfileStep ? "skip for now" : "skip", action: skip)
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
                            Text(model.step.isLastProfileStep ? "skip for now" : "skip").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .disabled(model.isSubmitting)
                    }
                    Button(action: primaryAction) {
                        Group {
                            if model.isSubmitting {
                                ProgressView()
                            } else {
                                Text("continue")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!model.canContinue)
                }
                .controlSize(.large)
            }
            if model.step.isLastProfileStep {
                Text("next: choose your premium plan. your profile will be saved.")
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
        guard model.step.isLastProfileStep else {
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

/// One segment per step, filled up to the current step.
struct OnboardingProgress: View {
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
