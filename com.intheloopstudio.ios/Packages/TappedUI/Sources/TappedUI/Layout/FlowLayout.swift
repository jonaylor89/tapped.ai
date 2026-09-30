import SwiftUI

/// Wrapping row layout for chips and genre pills: fills each line left to right, then wraps.
/// Replaces single-line horizontal scroll rows so every chip stays visible at large text sizes.
public struct FlowLayout: Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat

    public init(spacing: CGFloat = TappedSpacing.sm, lineSpacing: CGFloat? = nil) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing ?? spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return Self.size(of: sizes, maxWidth: proposal.width ?? .infinity, spacing: spacing, lineSpacing: lineSpacing)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let frames = Self.frames(for: sizes, maxWidth: bounds.width, spacing: spacing, lineSpacing: lineSpacing)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    /// Origin + size of each item. Items wider than `maxWidth` get their own line, clamped to it.
    public static func frames(for sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat, lineSpacing: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for size in sizes {
            let width = min(size.width, maxWidth)
            if x > 0, x + width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: width, height: size.height))
            x += width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return frames
    }

    public static func size(of sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat, lineSpacing: CGFloat) -> CGSize {
        let frames = frames(for: sizes, maxWidth: maxWidth, spacing: spacing, lineSpacing: lineSpacing)
        return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }
}

#Preview("FlowLayout") {
    FlowLayout {
        ForEach(["hip hop", "r&b", "electronic", "house", "indie rock", "jazz", "americana", "latin"], id: \.self) {
            GlassChip($0)
        }
    }
    .padding()
    .background(PreviewBackdrop())
}
