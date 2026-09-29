import SwiftUI
import TappedUI

/// `_MapControls`: filters (venues only), locate, and debug-only zoom in a clear glass capsule.
struct DiscoverMapControls: View {
    let model: DiscoverViewModel

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                if model.overlay == .venues {
                    control("slider.horizontal.3", label: "filters", isActive: !model.genreFilters.isEmpty) {
                        model.modal = .filters
                    }
                }
                control("location.fill", label: "my location") { model.locate() }
                #if DEBUG
                control("plus", label: "zoom in") { model.zoom(by: 0.5) }
                control("minus", label: "zoom out") { model.zoom(by: 2) }
                #endif
            }
            .padding(4)
            .tappedGlass(in: Capsule())
        }
        .tappedShadow()
    }

    private func control(_ systemImage: String, label: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isActive ? TappedColors.accent : .primary)
                .frame(width: GlassMetrics.iconControl, height: GlassMetrics.iconControl)
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(label)
    }
}
