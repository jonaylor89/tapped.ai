import SwiftUI
import TappedUI

/// Count badge overlaid on the messages button.
struct UnreadBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(TappedColors.error, in: Capsule())
                .accessibilityLabel("\(count) unread")
        }
    }
}

#Preview {
    HStack { UnreadBadge(count: 3); UnreadBadge(count: 120) }
}
