import SwiftUI

/// One chat message. Outgoing bubbles use the accent colour; incoming use the adaptive surface.
/// `showsTimestamp` puts a centred time above the bubble; pass it only where a new cluster starts.
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
    let showsTimestamp: Bool

    public init(
        text: String, authorName: String, timestamp: Date, isOutgoing: Bool, status: Status = .sent,
        showsAuthor: Bool = false, showsTimestamp: Bool = true
    ) {
        self.showsTimestamp = showsTimestamp
        self.text = text
        self.authorName = authorName
        self.timestamp = timestamp
        self.isOutgoing = isOutgoing
        self.status = status
        self.showsAuthor = showsAuthor
    }

    public var body: some View {
        VStack(spacing: TappedSpacing.xs) {
            if showsTimestamp {
                Text(Self.clusterLabel(for: timestamp))
                    .font(TappedTypography.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, TappedSpacing.sm)
            }
            bubble
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// "9:41 AM" today, "Yesterday 9:41 AM", otherwise "Tue, Oct 6 9:41 AM".
    static func clusterLabel(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(time)"
        }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) \(time)"
    }

    private var bubble: some View {
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
                if status == .failed {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(TappedColors.error)
                        Text("not sent")
                    }
                    .font(TappedTypography.caption)
                    .foregroundStyle(.secondary)
                }
            }
            if !isOutgoing { Spacer(minLength: TappedSpacing.xxxl) }
        }
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
        ChatBubble(text: "sending…", authorName: "you", timestamp: .now, isOutgoing: true, status: .sending, showsTimestamp: false)
        ChatBubble(text: "offline", authorName: "you", timestamp: .now, isOutgoing: true, status: .failed, showsTimestamp: false)
    }
    .padding()
    .background(TappedColors.background)
}
