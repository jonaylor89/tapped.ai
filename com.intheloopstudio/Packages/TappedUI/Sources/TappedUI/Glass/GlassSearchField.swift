import SwiftUI

/// Floating glass search capsule. Editable (`text:` init) or a tap target that opens search (`action:` init),
/// which is how Discover uses it.
public struct GlassSearchField<Trailing: View>: View {
    private enum Mode {
        case editable(Binding<String>, onSubmit: () -> Void)
        case button(() -> Void)
    }

    private let mode: Mode
    private let placeholder: String
    private let trailing: Trailing
    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        placeholder: String = "search tapped",
        onSubmit: @escaping () -> Void = {},
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        mode = .editable(text, onSubmit: onSubmit)
        self.placeholder = placeholder
        self.trailing = trailing()
    }

    public init(
        placeholder: String = "search tapped",
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        mode = .button(action)
        self.placeholder = placeholder
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: TappedSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            switch mode {
            case let .editable(text, onSubmit):
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isFocused)
                    .onSubmit(onSubmit)
                if !text.wrappedValue.isEmpty {
                    Button {
                        text.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("clear")
                }
            case let .button(action):
                Button(action: action) {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            trailing
        }
        .font(TappedTypography.bodyLg)
        .padding(.leading, TappedSpacing.lg)
        .padding(.trailing, TappedSpacing.xs)
        .frame(height: GlassMetrics.control)
        .tappedGlass(in: Capsule(), interactive: true)
    }
}

#Preview("GlassSearchField") {
    @Previewable @State var text = ""
    VStack(spacing: TappedSpacing.lg) {
        GlassSearchField(action: {}) {
            GlassIconButton("person.crop.circle", accessibilityLabel: "profile") {}
        }
        GlassSearchField(text: $text, placeholder: "search a city")
    }
    .padding()
    .background(PreviewBackdrop())
}
