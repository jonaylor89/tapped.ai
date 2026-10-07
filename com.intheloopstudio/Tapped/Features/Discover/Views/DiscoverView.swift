import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `lib/ui/discover/discover_view.dart`: the full-bleed map behind the shell sheet, with the floating
/// gigs/venues switch, filters and map controls. The sheet itself is owned by `ShellView`.
struct DiscoverView: View {
    @Bindable var model: DiscoverViewModel
    let collapsedHeight: CGFloat
    let open: (Route) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var topChromeBottom: CGFloat = 0
    @State private var controlsHeight: CGFloat = 0
    @State private var mapLink = MapViewLink()

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            let collapsedTop = frame.maxY - collapsedHeight
            let sheetTop = model.sheetTop > 0 ? min(model.sheetTop, collapsedTop) : collapsedTop
            let recede = MapsStyleSheet<EmptyView>.recede(model.sheetProgress)
            let room = sheetTop - TappedSpacing.md - topChromeBottom - TappedSpacing.md - controlsHeight
            let roomOpacity = min(max(room / 40, 0), 1)
            let chromeOpacity = min(MapsStyleSheet<EmptyView>.chromeOpacity(model.sheetProgress), roomOpacity)

            ZStack(alignment: .top) {
                DiscoverMapView(
                    items: model.annotations,
                    initialCenter: model.home,
                    initialSpanDegrees: DiscoverViewModel.defaultSpanDegrees,
                    cameraRequest: model.cameraRequest,
                    onRegionChange: { bounds in Task { await model.mapRegionChanged(to: bounds) } },
                    onSelect: { id in model.route(forAnnotation: id).map(open) },
                    link: mapLink
                )
                .ignoresSafeArea()

                DiscoverTopChrome(model: model, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize, push: open)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { topChromeBottom = $0 }
                    .opacity(MapsStyleSheet<EmptyView>.chromeOpacity(model.sheetProgress))

                DiscoverMapControls(model: model, mapView: mapLink.mapView)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
                    .opacity(chromeOpacity)
                    .offset(y: -8 * recede)
                    .allowsHitTesting(chromeOpacity >= 0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, GlassMetrics.edgeInset)
                    .padding(.bottom, max(frame.maxY - sheetTop, 0) + TappedSpacing.md)
            }
        }
        .task {
            await FirstFrame.rendered()
            await model.start()
        }
        .task(id: model.isPremium) { await model.observeQuota() }
    }
}
