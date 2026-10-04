import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// `_TopChrome`: gigs/venues switch + filters, setup banner, "search this area". Profile, search and messages
/// are shell tabs. At accessibility sizes the switch becomes a menu and the banner moves into the sheet.
struct DiscoverTopChrome: View {
    @Bindable var model: DiscoverViewModel
    let isAccessibilitySize: Bool
    let push: (Route) -> Void

    private var overlay: Binding<MapOverlay> {
        Binding(get: { model.overlay }, set: { overlay in Task { await model.select(overlay) } })
    }

    var body: some View {
        VStack(spacing: TappedSpacing.md) {
            HStack(spacing: TappedSpacing.sm) {
                if isAccessibilitySize {
                    overlayMenu
                } else {
                    GlassSegmentedPicker(selection: overlay, options: MapOverlay.allCases, title: \.rawValue)
                        .frame(width: 220)
                }
                if model.overlay == .venues {
                    GlassIconButton(
                        "slider.horizontal.3",
                        accessibilityLabel: "filters",
                        isActive: !model.genreFilters.isEmpty
                    ) { model.modal = .filters }
                    .transition(.scale.combined(with: .opacity))
                }
            }

            if !isAccessibilitySize, let message = model.tasksBannerMessage {
                GlassBanner(
                    "finish setting up",
                    message: message,
                    systemImage: "checkmark.circle",
                    action: { push(.tasks) },
                    onDismiss: { withAnimation(GlassMotion.ease) { model.isTasksBannerDismissed = true } }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if model.resultsExpired {
                GlassCapsuleButton("search this area", systemImage: "arrow.clockwise", style: .accent) {
                    Task { await model.searchThisArea() }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, GlassMetrics.edgeInset)
        .padding(.top, TappedSpacing.sm)
        .animation(GlassMotion.ease, value: model.resultsExpired)
        .animation(GlassMotion.ease, value: model.overlay)
    }

    private var overlayMenu: some View {
        Menu {
            Picker("show on map", selection: overlay) {
                ForEach(MapOverlay.allCases, id: \.self) { overlay in
                    Label(overlay.rawValue, systemImage: overlay.systemImage).tag(overlay)
                }
            }
        } label: {
            Label(model.overlay.rawValue, systemImage: model.overlay.systemImage)
                .font(TappedTypography.headingXs)
                .foregroundStyle(.primary)
                .padding(.horizontal, TappedSpacing.lg)
                .frame(minHeight: GlassMetrics.control)
                .tappedGlass(in: Capsule(), interactive: true)
        }
        .accessibilityLabel("show on map")
        .accessibilityValue(model.overlay.rawValue)
    }
}
