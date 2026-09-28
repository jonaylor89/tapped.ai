import SwiftUI

/// One chat message. Outgoing bubbles use the accent colour; incoming use the adaptive surface.
public struct ChatBubble: View {
    public enum Status: Sendable {
        case sent, sending, failed
    }

    let text: String
    let authorName: String
    let timestamp: Date
    let isOutgoing: Bool
    let status: Status
    let showsAuthor: Bool

    public init(text: String, authorName: String, timestamp: Date, isOutgoing: Bool, status: Status = .sent, showsAuthor: Bool = false) {
        self.text = text
        self.authorName = authorName
        self.timestamp = timestamp
        self.isOutgoing = isOutgoing
        self.status = status
        self.showsAuthor = showsAuthor
    }

    public var body: some View {
        HStack {
            if isOutgoing { Spacer(minLength: TappedSpacing.xxxl) }
            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 2) {
                if showsAuthor && !isOutgoing {
                    Text(authorName).font(TappedTypography.caption).foregroundStyle(.secondary)
                }
                Text(text)
                    .font(TappedTypography.bodyLg)
                    .foregroundStyle(isOutgoing ? Color.white : Color.primary)
                    .padding(.horizontal, TappedSpacing.md)
                    .padding(.vertical, TappedSpacing.sm)
                    .background(
                        isOutgoing ? AnyShapeStyle(TappedColors.accent) : AnyShapeStyle(TappedColors.surface),
                        in: RoundedRectangle(cornerRadius: TappedRadius.xl, style: .continuous)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                    .opacity(status == .sending ? 0.6 : 1)
                HStack(spacing: 4) {
                    if status == .failed {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(TappedColors.error)
                        Text("not sent")
                    }
                    Text(timestamp, style: .time)
                }
                .font(TappedTypography.caption)
                .foregroundStyle(.secondary)
            }
            if !isOutgoing { Spacer(minLength: TappedSpacing.xxxl) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let who = isOutgoing ? "you" : authorName
        let suffix = status == .failed ? ", not sent" : status == .sending ? ", sending" : ""
        return "\(who): \(text), \(timestamp.formatted(date: .omitted, time: .shortened))\(suffix)"
    }
}

#Preview {
    VStack(spacing: TappedSpacing.sm) {
        ChatBubble(text: "hey! saw your application", authorName: "the camel", timestamp: .now, isOutgoing: false, showsAuthor: true)
        ChatBubble(text: "hi! yes — we'd love to play", authorName: "you", timestamp: .now, isOutgoing: true)
        ChatBubble(text: "sending…", authorName: "you", timestamp: .now, isOutgoing: true, status: .sending)
        ChatBubble(text: "offline", authorName: "you", timestamp: .now, isOutgoing: true, status: .failed)
    }
    .padding()
    .background(TappedColors.background)
}
