import Foundation

/// Rewrites Firebase Storage image URLs to resized variants served by imgproxy (`img.tapped.ai`).
///
/// The preset ladders mirror `IMGPROXY_PRESETS` in `docker-compose.prod.yml` (and the web app's
/// `src/lib/image-loader.ts`); a URL for a preset the server doesn't define fails to load.
public struct ImageProxy: Sendable, Hashable {
    /// `nil` disables rewriting, so every image loads from its original URL.
    public let baseURL: URL?

    public init(baseURL: URL?) {
        self.baseURL = baseURL
    }

    public static let disabled = ImageProxy(baseURL: nil)

    /// `w<N>`: fit to N px wide, aspect ratio kept.
    static let widthPresets = [64, 128, 256, 384, 640, 828, 1080, 1600]
    /// `sq<N>`: center-cropped to an N×N square.
    static let squarePresets = [64, 128, 256, 384]

    /// Mirrors `IMGPROXY_ALLOWED_SOURCES`; anything else is returned untouched.
    static let proxiedSources = [
        "https://firebasestorage.googleapis.com/v0/b/in-the-loop-306520.appspot.com/",
        "https://storage.googleapis.com/in-the-loop-306520.appspot.com/",
    ]

    /// The smallest variant that covers a `pixelWidth` × `pixelHeight` box, or `source` itself when the
    /// proxy is disabled or the image isn't in the Firebase bucket.
    public func url(for source: URL, pixelWidth: Int, pixelHeight: Int) -> URL {
        guard let baseURL, pixelWidth > 0, pixelHeight > 0,
              Self.proxiedSources.contains(where: source.absoluteString.hasPrefix)
        else { return source }

        let longest = max(pixelWidth, pixelHeight)
        let preset = if abs(pixelWidth - pixelHeight) * 20 <= longest, longest <= Self.squarePresets.last! {
            "sq\(Self.squarePresets.first { $0 >= longest }!)"
        } else {
            // Sizing by the longest side keeps portrait boxes sharp, since `w<N>` only bounds width.
            "w\(Self.widthPresets.first { $0 >= longest } ?? Self.widthPresets.last!)"
        }
        return baseURL.appending(path: "unsafe/\(preset)/\(Self.base64URL(source.absoluteString))")
    }

    static func base64URL(_ string: String) -> String {
        Data(string.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
