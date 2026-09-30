import SwiftUI
import TappedUI

/// Port of `lib/ui/image_view.dart`: full-screen, pinch-to-zoom image.
struct ImageViewerView: View {
    let url: URL
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(max(1, scale * pinch))
                    .gesture(
                        MagnifyGesture()
                            .updating($pinch) { value, state, _ in state = value.magnification }
                            .onEnded { value in scale = min(4, max(1, scale * value.magnification)) }
                    )
                    .onTapGesture(count: 2) { withAnimation(GlassMotion.spring) { scale = scale > 1 ? 1 : 2 } }
                    .accessibilityLabel("image")
            case .failure:
                ErrorView("couldn't load image")
            default:
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ImageViewerView(url: URL(string: "https://picsum.photos/800/1200")!)
    }
}
