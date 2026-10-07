import SwiftUI
import TappedDomain

public extension EnvironmentValues {
    /// Set from `TappedConfig` at the app root; previews and mocks load original URLs.
    @Entry var imageProxy: ImageProxy = .disabled
}

/// A remote image that fills whatever frame it's given and never affects layout.
///
/// `AsyncImage { $0.resizable().scaledToFill() }` reports the image's overflowing size to its parent,
/// so a wide photo in a fixed-height frame pushes siblings off-screen. Here the image lives in an
/// overlay on `Color.clear`, so only the frame decides the size, and it requests the imgproxy variant
/// that matches that frame instead of the full-size original.
///
/// Images load through `ImageLoader`, whose decoded-image cache is read synchronously, so a reused
/// list cell draws its image on the first frame instead of flashing the placeholder. The size is
/// quantised to an imgproxy preset and never steps down while a larger variant is cached; while a
/// larger one loads, the current image stays on screen.
public struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    let placeholder: Placeholder

    @Environment(\.imageProxy) private var imageProxy
    @Environment(\.displayScale) private var displayScale
    /// The last image this view showed, kept on screen while a larger variant loads.
    @State private var shown: (source: URL, image: UIImage)?

    public init(url: URL?, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder()
    }

    public var body: some View {
        Color.clear
            .overlay {
                if let url {
                    GeometryReader { proxy in
                        content(
                            for: ImageRequest(source: url, proxy: imageProxy, size: proxy.size, scale: displayScale),
                            source: url
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                } else {
                    placeholder
                }
            }
            .clipped()
    }

    @ViewBuilder
    private func content(for request: ImageRequest?, source: URL) -> some View {
        let hit = request.flatMap(ImageLoader.shared.cache.image(for:))
        let image = hit?.image ?? shown.flatMap { $0.source == source ? $0.image : nil }
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: request) {
            guard let request, hit?.isSufficient != true else { return }
            if image != nil {
                // Already showing something: wait out a resize (e.g. a sheet detent animation) so
                // only the size it settles on is fetched.
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
            }
            if let loaded = try? await ImageLoader.shared.image(for: request) {
                shown = (request.source, loaded)
            }
        }
    }
}
