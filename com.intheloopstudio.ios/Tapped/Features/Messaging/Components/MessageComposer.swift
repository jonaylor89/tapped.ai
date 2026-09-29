import SwiftUI
import TappedUI

/// Floating glass composer: growing text field + send button.
struct MessageComposer: View {
    @Binding var text: String
    let canSend: Bool
    let send: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: TappedSpacing.sm) {
            TextField("message", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .focused($isFocused)
                .submitLabel(.send)
                .onSubmit { if canSend { send() } }
                .padding(.horizontal, TappedSpacing.lg)
                .padding(.vertical, TappedSpacing.md)
                .frame(minHeight: GlassMetrics.iconControl)
                .tappedGlass(in: RoundedRectangle(cornerRadius: GlassRadius.control, style: .continuous))
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .frame(width: GlassMetrics.iconControl, height: GlassMetrics.iconControl)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(TappedColors.accent)
            .disabled(!canSend)
            .accessibilityLabel("send")
        }
        .padding(.horizontal, GlassMetrics.edgeInset)
        .padding(.vertical, TappedSpacing.sm)
    }
}

#Preview {
    @Previewable @State var text = "see you friday"
    VStack {
        Spacer()
        MessageComposer(text: $text, canSend: true) {}
    }
    .background(PreviewBackdrop())
}
