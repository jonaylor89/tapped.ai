import SwiftUI

/// Compact "you're offline" capsule. Mount with `.offlineBanner(isOffline:)`.
public struct OfflineBanner: View {
    public init() {}

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TappedSpacing.sm) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(TappedColors.warning)
            VStack(alignment: .leading, spacing: 0) {
                Text("you're offline").font(TappedTypography.headingXs)
                Text("changes will sync when you reconnect")
                    .font(TappedTypography.bodySm)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TappedSpacing.lg)
        .padding(.vertical, TappedSpacing.sm)
        .tappedGlass(in: RoundedRectangle(cornerRadius: GlassRadius.control, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

public extension View {
    /// Pins `OfflineBanner` under the navigation bar while `isOffline`.
    func offlineBanner(isOffline: Bool) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if isOffline {
                OfflineBanner()
                    .tappedFloatingInset()
                    .padding(.bottom, TappedSpacing.xs)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(GlassMotion.spring, value: isOffline)
    }
}

#Preview("OfflineBanner") {
    NavigationStack {
        List { Text("bookings") }
            .navigationTitle("bookings")
            .offlineBanner(isOffline: true)
    }
}
