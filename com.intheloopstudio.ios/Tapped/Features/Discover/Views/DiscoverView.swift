import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `lib/ui/discover/discover_view.dart`: full-bleed map, floating glass chrome, Maps-style sheet.
struct DiscoverView: View {
    @State private var model: DiscoverViewModel
    @Environment(Router.self) private var router
    @Environment(ShellViewModel.self) private var shell
    @Environment(\.scenePhase) private var scenePhase
    @State private var topChromeBottom: CGFloat = 0
    @State private var controlsHeight: CGFloat = 0

    init(
        dependencies: Dependencies,
        currentUser: UserModel,
        isPremium: Bool,
        claims: [CustomClaim],
        initialDetent: MapsSheetDetent? = nil
    ) {
        _model = State(initialValue: DiscoverViewModel(
            dependencies: dependencies,
            currentUser: currentUser,
            isPremium: isPremium,
            claims: claims,
            initialDetent: initialDetent ?? .collapsed
        ))
    }

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            let screenBottom = frame.maxY + proxy.safeAreaInsets.bottom
            let collapsedTop = screenBottom - (frame.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom) * MapsSheetDetent.collapsedFraction
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
                    onSelect: { id in model.route(forAnnotation: id).map(router.push) }
                )
                .ignoresSafeArea()

                DiscoverTopChrome(model: model, unreadMessages: shell.unreadMessages, push: router.push)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { topChromeBottom = $0 }

                DiscoverMapControls(model: model)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
                    .opacity(chromeOpacity)
                    .offset(y: -8 * recede)
                    .allowsHitTesting(chromeOpacity >= 0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, GlassMetrics.edgeInset)
                    .padding(.bottom, max(frame.maxY - sheetTop, 0) + TappedSpacing.md)
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .mapsStyleSheet(
            isPresented: Binding(get: { router.isAtRoot && scenePhase != .background }, set: { _ in }),
            detent: $model.sheetDetent,
            progress: $model.sheetProgress,
            sheetTop: $model.sheetTop
        ) {
            DiscoverSheetContent(model: model, push: router.push)
        }
        .task { await model.load() }
    }
}

#Preview {
    let dependencies = Dependencies.mock(signedIn: true)
    NavigationStack {
        DiscoverView(dependencies: dependencies, currentUser: Samples.performer, isPremium: false, claims: [.booker])
            .tappedRouteDestinations()
    }
    .environment(\.dependencies, dependencies)
    .environment(Router())
    .environment(ShellViewModel(currentUser: Samples.performer))
}
