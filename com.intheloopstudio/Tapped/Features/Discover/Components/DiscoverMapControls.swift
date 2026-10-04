import MapKit
import SwiftUI
import TappedUI

/// `_MapControls`: compass (only while the map is rotated) above a clear glass locate button.
struct DiscoverMapControls: View {
    let model: DiscoverViewModel
    let mapView: MKMapView?

    var body: some View {
        VStack(spacing: TappedSpacing.sm) {
            if let mapView {
                DiscoverCompass(mapView: mapView)
                    .frame(width: GlassMetrics.iconControl, height: GlassMetrics.iconControl)
            }
            GlassEffectContainer {
                Button { model.locate() } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: GlassMetrics.iconControl, height: GlassMetrics.iconControl)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GlassPressStyle())
                .accessibilityLabel("my location")
                .padding(4)
                .tappedGlass(in: Capsule())
            }
            .tappedShadow()
        }
    }
}
