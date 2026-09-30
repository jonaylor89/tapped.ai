import SwiftUI

/// "🔒 premium" capsule shown on gated rows before the user taps them.
public struct PremiumBadge: View {
    public init() {}

    public var body: some View {
        HStack(spacing: TappedSpacing.xs) {
            Image(systemName: "lock.fill")
            Text(Self.title)
        }
            .font(TappedTypography.label)
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .foregroundStyle(TappedColors.accentText)
            .padding(.horizontal, TappedSpacing.sm)
            .padding(.vertical, 3)
            .background(TappedColors.accent.opacity(0.12), in: Capsule())
            .accessibilityLabel("premium")
    }

    public static let title = "premium"
}

#Preview("PremiumBadge") {
    PremiumBadge().padding()
}
