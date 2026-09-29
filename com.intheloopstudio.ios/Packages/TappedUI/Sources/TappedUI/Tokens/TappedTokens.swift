import SwiftUI
import UIKit

// Ported 1:1 from `com.intheloopstudio/lib/ui/design/app_tokens.dart`.

public enum TappedSpacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 24
    public static let xxxl: CGFloat = 32
}

public enum TappedRadius {
    public static let sm: CGFloat = 6
    public static let md: CGFloat = 10
    public static let lg: CGFloat = 15
    public static let xl: CGFloat = 20
    public static let full: CGFloat = 999
}

public enum TappedSizing {
    public static let minTapTarget: CGFloat = 44
}

public enum TappedColors {
    /// Brand accent. Use as tint/outline, not large fills. Darkens to `accentTextLight` under Increase Contrast.
    public static let accent = Color(light: Color(hex: 0x0086CC), dark: Color(hex: 0x0086CC), highContrastLight: accentTextLight, highContrastDark: Color(hex: 0x4DB8F0))
    /// ≈5.8:1 on white; small light-mode text and links.
    public static let accentTextLight = Color(hex: 0x006BA3)
    /// Accent for small text/links: `#006BA3` in light mode (AA on white), brand accent in dark mode.
    public static let accentText = Color(light: accentTextLight, dark: Color(hex: 0x0086CC), highContrastLight: Color(hex: 0x005580), highContrastDark: Color(hex: 0x4DB8F0))
    public static let success = Color(hex: 0x34C759)
    public static let error = Color(hex: 0xFF3B30)
    public static let warning = Color(hex: 0xFF9500)

    public static let backgroundLight = Color(hex: 0xF8F6FB)
    public static let backgroundDark = Color(hex: 0x010F16)
    public static let surfaceLight = Color.white
    public static let surfaceDark = Color(hex: 0x1C2B33)

    public static let textOnImage = Color.white
    public static let textOnImageMuted = Color.white.opacity(0.8)
    public static let scrim = Color.black.opacity(0.5)
    public static let scrimLight = Color.black.opacity(0.2)

    /// `themes.dart` scaffold background, light/dark adaptive.
    public static let background = Color(light: backgroundLight, dark: backgroundDark)
    /// Card / sheet surface, light/dark adaptive.
    public static let surface = Color(light: surfaceLight, dark: surfaceDark)
}

/// `TappedTypography`, mapped onto the system font (SF Pro) so Dynamic Type still applies.
public enum TappedTypography {
    public static let displayLg = Font.system(.largeTitle, weight: .heavy)
    public static let displayMd = Font.system(.title, weight: .heavy)
    public static let headingLg = Font.system(.title, weight: .bold)
    public static let headingMd = Font.system(.title2, weight: .bold)
    public static let headingSm = Font.system(.title3, weight: .semibold)
    public static let headingXs = Font.system(.headline, weight: .semibold)
    public static let bodyLg = Font.body
    public static let bodyMd = Font.subheadline
    public static let bodySm = Font.footnote
    public static let label = Font.system(.footnote, weight: .medium)
    public static let caption = Font.caption2
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    /// Adaptive colour that also honours Increase Contrast (`colorSchemeContrast == .increased`).
    init(light: Color, dark: Color, highContrastLight: Color, highContrastDark: Color) {
        self.init(uiColor: UIColor { traits in
            let high = traits.accessibilityContrast == .high
            return switch (traits.userInterfaceStyle == .dark, high) {
            case (true, true): UIColor(highContrastDark)
            case (true, false): UIColor(dark)
            case (false, true): UIColor(highContrastLight)
            case (false, false): UIColor(light)
            }
        })
    }
}
