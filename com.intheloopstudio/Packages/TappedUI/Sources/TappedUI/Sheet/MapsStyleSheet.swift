import MapKit
import SwiftUI

/// The three Discover detents (`DraggableSheet.collapsed / mid / expanded` in Flutter).
public enum MapsSheetDetent: CaseIterable, Sendable, Hashable {
    case collapsed
    case medium
    case large

    public static let collapsedFraction: CGFloat = 0.12

    public var presentationDetent: PresentationDetent {
        switch self {
        case .collapsed: .fraction(Self.collapsedFraction)
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

/// Apple Maps style persistent sheet.
///
/// - At `.collapsed` and `.medium` iOS 26 renders the sheet as an inset, rounded, floating Liquid Glass card
///   and the map behind stays interactive.
/// - Between `.medium` and `.large` the content gains an opaque surface (`morph`), matching the Flutter
///   `LiquidGlass(solidity: m)` so it reads as edge-attached and solid at `.large`.
/// - `progress` is 0 at `.collapsed` and 1 at `.large`; use it to fade floating map chrome.
/// - `sheetTop` is the sheet's top edge in global (window) coordinates; use it to float controls above the sheet.
public struct MapsStyleSheet<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var detent: MapsSheetDetent
    @Binding var progress: CGFloat
    @Binding var sheetTop: CGFloat
    let sheetContent: () -> SheetContent

    @State private var containerHeight: CGFloat = 0

    public init(
        isPresented: Binding<Bool>,
        detent: Binding<MapsSheetDetent>,
        progress: Binding<CGFloat>,
        sheetTop: Binding<CGFloat> = .constant(0),
        @ViewBuilder content: @escaping () -> SheetContent
    ) {
        _isPresented = isPresented
        _detent = detent
        _progress = progress
        _sheetTop = sheetTop
        sheetContent = content
    }

    public func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { containerHeight = $0 }
            .sheet(isPresented: $isPresented) {
                sheetContent()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(TappedColors.surface.opacity(Self.morph(progress)))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        progress = Self.progress(sheetHeight: height, containerHeight: containerHeight)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { sheetTop = $0 }
                    .presentationDetents([.fraction(0.12), .medium, .large], selection: selection)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationContentInteraction(.resizes)
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
    }

    private var selection: Binding<PresentationDetent> {
        Binding(
            get: { detent.presentationDetent },
            set: { detent = MapsSheetDetent($0) }
        )
    }

    /// 0 at the collapsed detent, 1 fully expanded.
    public static func progress(sheetHeight: CGFloat, containerHeight: CGFloat) -> CGFloat {
        guard containerHeight > 0 else { return 0 }
        let collapsed = containerHeight * MapsSheetDetent.collapsedFraction
        let expanded = containerHeight
        return min(max((sheetHeight - collapsed) / (expanded - collapsed), 0), 1)
    }

    /// Where `.medium` sits on the `progress` scale.
    public static var mediumProgress: CGFloat {
        (0.5 - MapsSheetDetent.collapsedFraction) / (1 - MapsSheetDetent.collapsedFraction)
    }

    /// Surface solidity: 0 while floating (≤ medium), easing to 1 at `.large`.
    public static func morph(_ progress: CGFloat) -> CGFloat {
        let t = min(max((progress - mediumProgress) / (1 - mediumProgress), 0), 1)
        return t * t * (3 - 2 * t)
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
        progress: Binding<CGFloat> = .constant(0),
        sheetTop: Binding<CGFloat> = .constant(0),
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(MapsStyleSheet(isPresented: isPresented, detent: detent, progress: progress, sheetTop: sheetTop, content: content))
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
