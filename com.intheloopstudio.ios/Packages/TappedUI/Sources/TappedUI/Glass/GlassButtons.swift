import SwiftUI

/// Capsule-shaped glass button, e.g. "filters", "search this area", quick actions.
public struct GlassCapsuleButton: View {
    public enum Style: Sendable {
        case regular
        /// Accent-outlined; use for the primary action in floating chrome.
        case accent
    }

    let title: String
    let systemImage: String?
    let style: Style
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, style: Style = .regular, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: TappedSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                }
                Text(title)
                    .font(TappedTypography.label)
                    .lineLimit(1)
            }
            .foregroundStyle(style == .accent ? TappedColors.accent : .primary)
            .padding(.horizontal, TappedSpacing.lg)
            .frame(minHeight: GlassMetrics.iconControl)
            .contentShape(Capsule())
        }
        .buttonStyle(GlassPressStyle())
        .tappedGlass(style == .accent ? .tinted : .regular, in: Capsule(), interactive: true)
        .overlay {
            if style == .accent {
                Capsule().strokeBorder(TappedColors.accent.opacity(0.5), lineWidth: 1)
            }
        }
    }
}

/// Circular 44pt glass icon control (map controls, profile/messages in top chrome).
public struct GlassIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let isActive: Bool
    let action: () -> Void

    public init(_ systemImage: String, accessibilityLabel: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isActive ? TappedColors.accent : .primary)
                .frame(width: GlassMetrics.iconControl, height: GlassMetrics.iconControl)
                .contentShape(Circle())
        }
        .buttonStyle(GlassPressStyle())
        .tappedGlass(isActive ? .tinted : .regular, in: Circle(), interactive: true)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Selectable glass chip with an optional count badge (genre chips on the Discover sheet).
public struct GlassChip: View {
    let title: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    public init(_ title: String, count: Int? = nil, isSelected: Bool = false, action: @escaping () -> Void = {}) {
        self.title = title
        self.count = count
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: TappedSpacing.xs) {
                Text(title)
                if let count {
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .font(TappedTypography.label)
            .foregroundStyle(isSelected ? TappedColors.accent : .primary)
            .padding(.horizontal, TappedSpacing.md)
            .padding(.vertical, TappedSpacing.sm)
            .contentShape(Capsule())
        }
        .buttonStyle(GlassPressStyle())
        .tappedGlass(isSelected ? .tinted : .regular, in: Capsule(), interactive: true)
        .overlay {
            Capsule().strokeBorder(isSelected ? TappedColors.accent.opacity(0.6) : .clear, lineWidth: 1)
        }
    }
}

#Preview("GlassCapsuleButton") {
    VStack(spacing: TappedSpacing.lg) {
        GlassCapsuleButton("filters", systemImage: "line.3.horizontal.decrease") {}
        GlassCapsuleButton("search this area", style: .accent) {}
    }
    .padding()
    .background(PreviewBackdrop())
}

#Preview("GlassIconButton") {
    HStack(spacing: TappedSpacing.lg) {
        GlassIconButton("location", accessibilityLabel: "locate") {}
        GlassIconButton("location.fill", accessibilityLabel: "locate", isActive: true) {}
        GlassIconButton("person.crop.circle", accessibilityLabel: "profile") {}
    }
    .padding()
    .background(PreviewBackdrop())
}

#Preview("GlassChip") {
    HStack {
        GlassChip("rock", count: 12)
        GlassChip("jazz", count: 4, isSelected: true)
        GlassChip("pop")
    }
    .padding()
    .background(PreviewBackdrop())
}
