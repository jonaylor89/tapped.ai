import SwiftUI
import TappedUI

/// Stand-in destination for routes owned by follow-up sessions.
struct PlaceholderScreen: View {
    let title: String
    var owner: Int?

    init(title: String, owner: Int? = nil) {
        self.title = title
        self.owner = owner
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "hammer")
        } description: {
            if let owner {
                Text("coming soon · session \(owner)")
            } else {
                Text("coming soon")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .background(TappedColors.background.ignoresSafeArea())
    }
}

#Preview {
    NavigationStack { PlaceholderScreen(title: "settings", owner: 2) }
}
