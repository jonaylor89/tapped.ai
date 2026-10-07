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

    /// An imgproxy preset: `sq<N>` (center-cropped N×N square) or `w<N>` (N px wide, aspect kept).
    public struct Preset: Sendable, Hashable, CustomStringConvertible {
        public enum Kind: String, Sendable, Hashable {
            case square = "sq"
            case width = "w"
        }

        public let kind: Kind
        /// The preset's bound in pixels: the square's side, or the width for `w<N>`.
        public let pixels: Int

        public init(kind: Kind, pixels: Int) {
            self.kind = kind
            self.pixels = pixels
        }

        public var description: String { "\(kind.rawValue)\(pixels)" }
    }

    /// The smallest preset that covers a `pixelWidth` × `pixelHeight` box, or `nil` for an empty box.
    ///
    /// Every box between two rungs maps to the same preset, so a view can resize (say, during a
    /// sheet detent animation) without its URL changing until it crosses into the next rung.
    public static func preset(pixelWidth: Int, pixelHeight: Int) -> Preset? {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let longest = max(pixelWidth, pixelHeight)
        if abs(pixelWidth - pixelHeight) * 20 <= longest, longest <= squarePresets.last! {
            return Preset(kind: .square, pixels: squarePresets.first { $0 >= longest }!)
        }
        // Sizing by the longest side keeps portrait boxes sharp, since `w<N>` only bounds width.
        return Preset(kind: .width, pixels: widthPresets.first { $0 >= longest } ?? widthPresets.last!)
    }

    /// Whether `source` is rewritten to imgproxy variants (proxy enabled and the image is in the bucket).
    public func proxies(_ source: URL) -> Bool {
        baseURL != nil && Self.proxiedSources.contains(where: source.absoluteString.hasPrefix)
    }

    /// The `preset` variant of `source`, or `source` itself when ``proxies(_:)`` is false.
    public func url(for source: URL, preset: Preset) -> URL {
        guard let baseURL, proxies(source) else { return source }
        return baseURL.appending(path: "unsafe/\(preset)/\(Self.base64URL(source.absoluteString))")
    }

    /// The smallest variant that covers a `pixelWidth` × `pixelHeight` box, or `source` itself when the
    /// proxy is disabled or the image isn't in the Firebase bucket.
    public func url(for source: URL, pixelWidth: Int, pixelHeight: Int) -> URL {
        guard let preset = Self.preset(pixelWidth: pixelWidth, pixelHeight: pixelHeight) else { return source }
        return url(for: source, preset: preset)
    }

    static func base64URL(_ string: String) -> String {
        Data(string.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
