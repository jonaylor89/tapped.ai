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
public struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    let placeholder: Placeholder

    @Environment(\.imageProxy) private var imageProxy
    @Environment(\.displayScale) private var displayScale

    public init(url: URL?, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder()
    }

    public var body: some View {
        Color.clear
            .overlay {
                if let url {
                    GeometryReader { proxy in
                        AsyncImage(url: variant(of: url, size: proxy.size)) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                placeholder
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                } else {
                    placeholder
                }
            }
            .clipped()
    }

    private func variant(of url: URL, size: CGSize) -> URL {
        imageProxy.url(
            for: url,
            pixelWidth: Int((size.width * displayScale).rounded(.up)),
            pixelHeight: Int((size.height * displayScale).rounded(.up))
        )
    }
}
