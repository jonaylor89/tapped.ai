import SwiftUI

/// Full-width prominent glass submit button for the bottom of a form (`GlassButton.primary(expand: true)`).
/// Shows a spinner while `isSubmitting` and is disabled until `isEnabled`.
public struct GlassSubmitButton: View {
    let title: String
    let isSubmitting: Bool
    let isEnabled: Bool
    let role: ButtonRole?
    let action: () -> Void

    public init(_ title: String, isSubmitting: Bool = false, isEnabled: Bool = true, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isSubmitting = isSubmitting
        self.isEnabled = isEnabled
        self.role = role
        self.action = action
    }

    public var body: some View {
        Button(role: role, action: action) {
            ZStack {
                Text(title).opacity(isSubmitting ? 0 : 1)
                if isSubmitting { ProgressView().tint(.white) }
            }
            .font(TappedTypography.headingXs)
            .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!isEnabled || isSubmitting)
        .padding(.horizontal, GlassMetrics.edgeInset)
        .padding(.bottom, TappedSpacing.sm)
        .accessibilityValue(isSubmitting ? "sending" : "")
    }
}

#Preview("GlassSubmitButton") {
    VStack(spacing: TappedSpacing.lg) {
        GlassSubmitButton("send request") {}
        GlassSubmitButton("send request", isEnabled: false) {}
        GlassSubmitButton("send request", isSubmitting: true) {}
    }
    .padding(.vertical)
    .background(PreviewBackdrop())
}
