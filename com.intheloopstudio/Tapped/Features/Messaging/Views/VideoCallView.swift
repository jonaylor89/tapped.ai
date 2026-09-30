import SwiftUI
import TappedUI

/// Flutter's `VideoCallView` is an empty container (Stream Video was never shipped).
struct VideoCallView: View {
    var body: some View {
        GlassEmptyState("video calls are coming soon", message: "for now, keep it in the chat", systemImage: "video.fill")
            .padding(GlassMetrics.edgeInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TappedColors.background.ignoresSafeArea())
            .navigationTitle(Route.videoCall.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { VideoCallView() }
}
