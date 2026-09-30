import SwiftUI

/// Icon + title + detail on a glass card. Paywall feature list; reusable for any benefit list.
public struct GlassFeatureRow: View {
    let title: String
    let detail: String
    let systemImage: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(_ title: String, detail: String, systemImage: String) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
    }

    public var body: some View {
        let stacks = dynamicTypeSize.isAccessibilitySize
        let layout = stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: TappedSpacing.sm))
            : AnyLayout(HStackLayout(alignment: .top, spacing: TappedSpacing.md))
        layout {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(TappedColors.accent)
                .frame(minWidth: 32, minHeight: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TappedTypography.headingXs)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(TappedTypography.bodyMd)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !stacks { Spacer(minLength: 0) }
        }
        .padding(TappedSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tappedGlass(in: RoundedRectangle(cornerRadius: GlassRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: TappedSpacing.md) {
        GlassFeatureRow("unlimited gig opportunities", detail: "apply to every gig on the map, no daily cap", systemImage: "infinity")
        GlassFeatureRow("venue intel", detail: "exclusive info on venues actively looking for performers", systemImage: "building.2.fill")
    }
    .padding()
    .background(PreviewBackdrop())
}
