import SwiftUI

/// Glass capsule segmented control ("venues" / "gigs").
public struct GlassSegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    @Namespace private var namespace

    public init(selection: Binding<Value>, options: [Value], title: @escaping (Value) -> String) {
        _selection = selection
        self.options = options
        self.title = title
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(GlassMotion.spring) { selection = option }
                } label: {
                    Text(title(option))
                        .font(TappedTypography.label)
                        .foregroundStyle(isSelected ? TappedColors.accent : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(.background.opacity(0.6))
                                    .overlay(Capsule().strokeBorder(TappedColors.accent.opacity(0.35), lineWidth: 1))
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(TappedSpacing.xs)
        .tappedGlass(in: Capsule())
    }
}

#Preview("GlassSegmentedPicker") {
    @Previewable @State var selection = "venues"
    GlassSegmentedPicker(selection: $selection, options: ["venues", "gigs"]) { $0 }
        .frame(width: 220)
        .padding()
        .background(PreviewBackdrop())
}
