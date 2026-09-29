import SwiftUI

/// Floating glass banner, e.g. "finish setting up" on Discover.
public struct GlassBanner: View {
    let title: String
    let message: String?
    let systemImage: String
    let action: (() -> Void)?
    let onDismiss: (() -> Void)?

    public init(
        _ title: String,
        message: String? = nil,
        systemImage: String = "sparkles",
        action: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.action = action
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: TappedSpacing.md) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(TappedColors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(TappedTypography.headingXs)
                if let message {
                    Text(message).font(TappedTypography.bodySm).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("dismiss")
            }
        }
        .padding(.horizontal, TappedSpacing.lg)
        .padding(.vertical, TappedSpacing.md)
        .contentShape(RoundedRectangle(cornerRadius: GlassRadius.control))
        .onTapGesture { action?() }
        .tappedGlass(in: RoundedRectangle(cornerRadius: GlassRadius.control, style: .continuous), interactive: action != nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(action != nil ? .isButton : [])
    }
}

#Preview("GlassBanner") {
    VStack(spacing: TappedSpacing.lg) {
        GlassBanner("finish setting up", message: "add a photo and genres to get booked", action: {}, onDismiss: {})
        GlassBanner("you're offline", systemImage: "wifi.slash")
    }
    .padding()
    .background(PreviewBackdrop())
}
