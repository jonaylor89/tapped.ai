import SwiftUI

// Ported from `com.intheloopstudio/lib/ui/design/glass/glass_tokens.dart`.
// Blur values are kept for parity; SwiftUI's `glassEffect` owns the actual blur.

public enum GlassBlur {
    public static let regular: CGFloat = 24
    public static let thin: CGFloat = 14
    public static let thick: CGFloat = 40
}

public enum GlassRadius {
    public static let control: CGFloat = 22
    public static let card: CGFloat = 26
    public static let sheet: CGFloat = 38
    public static let capsule: CGFloat = 999
}

public enum GlassMetrics {
    public static let iconControl: CGFloat = 44
    public static let control: CGFloat = 50
    /// Gap between floating chrome and the screen edge.
    public static let edgeInset: CGFloat = 16
    public static let bottomBarClearance: CGFloat = 96
    public static let navBarInline: CGFloat = 52
    public static let navBarLargeTitle: CGFloat = 56
}

public enum GlassMotion {
    public static let press: Duration = .milliseconds(120)
    public static let release: Duration = .milliseconds(320)
    public static let reveal: Duration = .milliseconds(260)
    public static let sheet: Duration = .milliseconds(335)
    public static let pressedScale: CGFloat = 0.96

    public static let spring = Animation.spring(duration: 0.335, bounce: 0.15)
    public static let ease = Animation.easeOut(duration: 0.26)
}
