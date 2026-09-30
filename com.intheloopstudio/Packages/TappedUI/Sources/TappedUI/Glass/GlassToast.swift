import SwiftUI

/// Transient glass capsule at the bottom of the screen ("link copied", "user blocked").
public struct GlassToast: View {
    let message: String
    let systemImage: String

    public init(_ message: String, systemImage: String = "checkmark.circle.fill") {
        self.message = message
        self.systemImage = systemImage
    }

    public var body: some View {
        Label(message, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, TappedSpacing.lg)
            .padding(.vertical, TappedSpacing.md)
            .glassEffect(.regular, in: Capsule())
            .accessibilityAddTraits(.isStaticText)
    }
}

public extension View {
    /// Shows `message` as a `GlassToast` above the bottom safe area, clearing it after `duration`.
    func glassToast(_ message: Binding<String?>, duration: Duration = .seconds(2)) -> some View {
        overlay(alignment: .bottom) {
            if let text = message.wrappedValue {
                GlassToast(text)
                    .padding(.bottom, TappedSpacing.xxxl * 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: text) {
                        try? await Task.sleep(for: duration)
                        withAnimation(GlassMotion.ease) { message.wrappedValue = nil }
                    }
            }
        }
        .animation(GlassMotion.ease, value: message.wrappedValue)
    }
}

#Preview("GlassToast") {
    ZStack {
        PreviewBackdrop()
        GlassToast("link copied")
    }
}
