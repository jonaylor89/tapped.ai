import SwiftUI

public enum GlassVariant: Sendable {
    /// Floating chrome: nav, search capsule, map controls.
    case regular
    /// Sheets and prominent surfaces.
    case prominent
    /// Selected / primary control with a subtle accent tint.
    case tinted
}

public extension View {
    /// Apple-Maps-style Liquid Glass surface. Use for floating chrome only — forms and lists stay native.
    func tappedGlass(
        _ variant: GlassVariant = .regular,
        in shape: some Shape = Capsule(),
        interactive: Bool = false
    ) -> some View {
        let glass: Glass = switch variant {
        case .regular: .regular
        case .prominent: .regular
        case .tinted: .regular.tint(TappedColors.accent.opacity(0.25))
        }
        return glassEffect(interactive ? glass.interactive() : glass, in: shape)
    }

    /// Subtle floating shadow used under glass chrome.
    func tappedShadow() -> some View {
        shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    /// Horizontal inset used by all floating chrome.
    func tappedFloatingInset() -> some View {
        padding(.horizontal, GlassMetrics.edgeInset)
    }
}

/// Press feedback for custom glass controls: scale to `GlassMotion.pressedScale`.
public struct GlassPressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? GlassMotion.pressedScale : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.12) : GlassMotion.spring, value: configuration.isPressed)
    }
}
