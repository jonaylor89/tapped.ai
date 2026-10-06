import Foundation
import Synchronization
import TappedDomain
import UIKit

/// One image to show in a `RemoteImage`: which URL to fetch and how large to decode it.
struct ImageRequest: Hashable, Sendable {
    /// The URL the caller asked for (before imgproxy rewriting).
    let source: URL
    /// What gets fetched: the imgproxy variant, or `source` when it isn't proxied.
    let url: URL
    /// Decode so the image's shorter side covers this many pixels (capped at the original).
    let pixels: Int
    /// Requests whose images can stand in for each other at a different size.
    let group: String

    var key: String { "\(url.absoluteString)#\(pixels)" }

    /// Quantised to an imgproxy preset, so every size between two rungs is the same request.
    init?(source: URL, proxy: ImageProxy, size: CGSize, scale: CGFloat) {
        guard size.width.isFinite, size.height.isFinite,
              let preset = ImageProxy.preset(
                  pixelWidth: Int((size.width * scale).rounded(.up)),
                  pixelHeight: Int((size.height * scale).rounded(.up))
              )
        else { return nil }
        self.source = source
        url = proxy.url(for: source, preset: preset)
        pixels = preset.pixels
        // A square crop can't stand in for a width-fit variant (or vice versa); an unproxied image
        // is the same bytes at any size.
        group = proxy.proxies(source) ? "\(source.absoluteString)#\(preset.kind.rawValue)" : source.absoluteString
    }
}

/// Decoded images keyed by request, readable synchronously so reused list cells draw on first frame.
final class ImageCache: NSObject, NSCacheDelegate, Sendable {
    struct Hit {
        let image: UIImage
        /// `false` when only a smaller variant is cached: show it, but fetch the requested one.
        let isSufficient: Bool
    }

    private final class Entry {
        let image: UIImage
        let group: String
        let pixels: Int

        init(image: UIImage, group: String, pixels: Int) {
            self.image = image
            self.group = group
            self.pixels = pixels
        }
    }

    /// `NSCache` is thread-safe but predates `Sendable`.
    private nonisolated(unsafe) let images = NSCache<NSString, Entry>()
    /// group → cached sizes → cache key. Lets a request find a larger variant of the same image.
    private let index = Mutex<[String: [Int: String]]>([:])
    private nonisolated(unsafe) var memoryWarning: NSObjectProtocol?

    init(costLimit: Int = 96 * 1024 * 1024, countLimit: Int = 400) {
        super.init()
        images.totalCostLimit = costLimit
        images.countLimit = countLimit
        images.delegate = self
        memoryWarning = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.removeAll() }
    }

    deinit {
        if let memoryWarning { NotificationCenter.default.removeObserver(memoryWarning) }
    }

    /// The smallest cached variant that covers `request`, else the largest smaller one.
    ///
    /// Sticky by design: once a larger variant is cached, a view that shrinks keeps using it rather
    /// than fetching the smaller preset.
    func image(for request: ImageRequest) -> Hit? {
        let sizes = index.withLock { $0[request.group] ?? [:] }
        let covering = sizes.filter { $0.key >= request.pixels }.sorted { $0.key < $1.key }
        let smaller = sizes.filter { $0.key < request.pixels }.sorted { $0.key > $1.key }
        for (pixels, key) in covering + smaller {
            if let entry = images.object(forKey: key as NSString) {
                return Hit(image: entry.image, isSufficient: pixels >= request.pixels)
            }
        }
        return nil
    }

    func insert(_ image: UIImage, for request: ImageRequest) {
        let entry = Entry(image: image, group: request.group, pixels: request.pixels)
        index.withLock { $0[request.group, default: [:]][request.pixels] = request.key }
        images.setObject(entry, forKey: request.key as NSString, cost: Self.cost(of: image))
    }

    func removeAll() {
        images.removeAllObjects()
        index.withLock { $0.removeAll() }
    }

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let entry = obj as? Entry else { return }
        index.withLock { index in
            index[entry.group]?[entry.pixels] = nil
            if index[entry.group]?.isEmpty == true { index[entry.group] = nil }
        }
    }

    static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1 }
        return max(1, cgImage.bytesPerRow * cgImage.height)
    }
}
