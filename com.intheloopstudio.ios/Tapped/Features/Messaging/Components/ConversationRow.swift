import SwiftUI
import TappedDomain
import TappedUI

/// `ChannelPreview`: avatar, name, last message, timestamp and unread badge.
struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: TappedSpacing.md) {
            UserAvatar(url: conversation.imageURL, name: conversation.name, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.name)
                        .font(conversation.unreadCount > 0 ? TappedTypography.headingXs : .headline.weight(.regular))
                        .lineLimit(1)
                    Spacer(minLength: TappedSpacing.sm)
                    if let date = conversation.lastMessageAt {
                        Text(date, format: .relative(presentation: .named))
                            .font(TappedTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .top) {
                    Text(conversation.lastMessageText ?? "no messages yet")
                        .font(TappedTypography.bodyMd)
                        .foregroundStyle(conversation.unreadCount > 0 ? .primary : .secondary)
                        .lineLimit(2)
                    Spacer(minLength: TappedSpacing.sm)
                    UnreadBadge(count: conversation.unreadCount)
                }
            }
        }
        .padding(.vertical, TappedSpacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [conversation.name]
        if conversation.unreadCount > 0 { parts.append("\(conversation.unreadCount) unread") }
        if let text = conversation.lastMessageText { parts.append(text) }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    List(Samples.conversations) { ConversationRow(conversation: $0) }
        .listStyle(.plain)
}
