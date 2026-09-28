import SwiftUI

/// Colourful backdrop so glass is visible in previews.
public struct PreviewBackdrop: View {
    public init() {}

    public var body: some View {
        LinearGradient(
            colors: [TappedColors.accent.opacity(0.6), .purple.opacity(0.4), .orange.opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
