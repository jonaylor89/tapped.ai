import MapKit
import SwiftUI

/// The three map-sheet detents (`DraggableSheet.collapsed / mid / expanded` in Flutter).
public enum MapsSheetDetent: CaseIterable, Sendable, Hashable, Comparable {
    case collapsed
    case medium
    case large

    /// Used until the collapsed content has been measured.
    public static let defaultCollapsedHeight: CGFloat = 160

    public var presentationDetent: PresentationDetent {
        presentationDetent(collapsedHeight: Self.defaultCollapsedHeight)
    }

    public func presentationDetent(collapsedHeight: CGFloat) -> PresentationDetent {
        switch self {
        case .collapsed: .height(collapsedHeight)
        case .medium: .medium
        case .large: .large
        }
    }

    public init(_ detent: PresentationDetent) {
        switch detent {
        case .large: self = .large
        case .medium: self = .medium
        default: self = .collapsed
        }
    }
}

/// Apple Maps style persistent, non-dismissable sheet over a full-bleed map.
///
/// - The sheet has a solid `TappedColors.surface` background; the map behind stays interactive up to `.medium`.
/// - `collapsedHeight` is supplied by the caller (measured header + tab bar), not a screen fraction.
/// - `progress` is 0 at `.collapsed`, 0.5 at `.medium` and 1 at `.large`; use it to fade floating map chrome.
/// - `sheetTop` is the sheet's top edge in global (window) coordinates; use it to float controls above the sheet.
public struct MapsStyleSheet<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var detent: MapsSheetDetent
    @Binding var progress: CGFloat
    @Binding var sheetTop: CGFloat
    let collapsedHeight: CGFloat
    let sheetContent: () -> SheetContent

    @State private var containerHeight: CGFloat = 0

    public init(
        isPresented: Binding<Bool>,
        detent: Binding<MapsSheetDetent>,
        collapsedHeight: CGFloat = MapsSheetDetent.defaultCollapsedHeight,
        progress: Binding<CGFloat>,
        sheetTop: Binding<CGFloat> = .constant(0),
        @ViewBuilder content: @escaping () -> SheetContent
    ) {
        _isPresented = isPresented
        _detent = detent
        _progress = progress
        _sheetTop = sheetTop
        self.collapsedHeight = collapsedHeight
        sheetContent = content
    }

    public func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { containerHeight = $0 }
            .sheet(isPresented: $isPresented) {
                sheetContent()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        progress = Self.progress(sheetHeight: height, containerHeight: containerHeight, collapsedHeight: collapsedHeight)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { sheetTop = $0 }
                    .presentationDetents(
                        Set(MapsSheetDetent.allCases.map { $0.presentationDetent(collapsedHeight: collapsedHeight) }),
                        selection: selection
                    )
                    .presentationBackground(TappedColors.surface)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationContentInteraction(.resizes)
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
    }

    private var selection: Binding<PresentationDetent> {
        Binding(
            get: { detent.presentationDetent(collapsedHeight: collapsedHeight) },
            set: { detent = MapsSheetDetent($0) }
        )
    }

    /// Where `.medium` sits on the `progress` scale.
    public static var mediumProgress: CGFloat { 0.5 }

    /// 0 at the collapsed height, 0.5 at `.medium` (half the container), 1 fully expanded.
    public static func progress(
        sheetHeight: CGFloat,
        containerHeight: CGFloat,
        collapsedHeight: CGFloat = MapsSheetDetent.defaultCollapsedHeight
    ) -> CGFloat {
        guard containerHeight > 0 else { return 0 }
        let medium = containerHeight / 2
        func clamp(_ value: CGFloat) -> CGFloat { min(max(value, 0), 1) }
        if sheetHeight <= medium {
            return mediumProgress * clamp((sheetHeight - collapsedHeight) / max(medium - collapsedHeight, 1))
        }
        return mediumProgress + (1 - mediumProgress) * clamp((sheetHeight - medium) / max(containerHeight - medium, 1))
    }

    /// Fraction (0…1) of the way from `.medium` to `.large`.
    public static func recede(_ progress: CGFloat) -> CGFloat {
        min(max((progress - mediumProgress) / (1 - mediumProgress), 0), 1)
    }

    /// Opacity for floating map controls (`_Receding` in Flutter): fully visible up to `.medium`,
    /// ease-in fade to 0 at `.large`.
    public static func chromeOpacity(_ progress: CGFloat) -> CGFloat {
        let t = recede(progress)
        return 1 - t * t
    }
}

public extension View {
    func mapsStyleSheet<Content: View>(
        isPresented: Binding<Bool>,
        detent: Binding<MapsSheetDetent>,
        collapsedHeight: CGFloat = MapsSheetDetent.defaultCollapsedHeight,
        progress: Binding<CGFloat> = .constant(0),
        sheetTop: Binding<CGFloat> = .constant(0),
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(MapsStyleSheet(
            isPresented: isPresented,
            detent: detent,
            collapsedHeight: collapsedHeight,
            progress: progress,
            sheetTop: sheetTop,
            content: content
        ))
    }
}

#Preview("MapsStyleSheet") {
    @Previewable @State var isPresented = true
    @Previewable @State var detent = MapsSheetDetent.medium
    @Previewable @State var progress: CGFloat = 0
    Map()
        .overlay(alignment: .topTrailing) {
            GlassIconButton("location", accessibilityLabel: "locate") {}
                .padding()
                .opacity(MapsStyleSheet<EmptyView>.chromeOpacity(progress))
        }
        .mapsStyleSheet(isPresented: $isPresented, detent: $detent, progress: $progress) {
            ScrollView {
                VStack(alignment: .leading, spacing: TappedSpacing.md) {
                    Text("10 venues").font(TappedTypography.headingMd)
                    Text("progress \(progress, format: .number.precision(.fractionLength(2)))")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(TappedSpacing.xl)
            }
        }
}
