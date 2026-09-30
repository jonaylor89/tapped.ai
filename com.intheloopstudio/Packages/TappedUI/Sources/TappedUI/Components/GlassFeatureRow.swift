import SwiftUI

/// Icon + title + detail on a glass card. Paywall feature list; reusable for any benefit list.
public struct GlassFeatureRow: View {
    let title: String
    let detail: String
    let systemImage: String

    public init(_ title: String, detail: String, systemImage: String) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(alignment: .top, spacing: TappedSpacing.md) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(TappedColors.accent)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(TappedTypography.headingXs)
                Text(detail)
                    .font(TappedTypography.bodyMd)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
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
