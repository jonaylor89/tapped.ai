import Foundation
import ImageIO
import UIKit

/// Fetches, downsamples and caches images for `RemoteImage`.
///
/// Concurrent requests for the same variant share one download, which is cancelled once every view
/// waiting on it has disappeared. Decoding happens off the main actor via `CGImageSource`
/// thumbnails, so a list scroll never decodes a full-size photo on the main thread.
actor ImageLoader {
    static let shared = ImageLoader()

    nonisolated let cache: ImageCache
    private let fetch: @Sendable (URL) async throws -> Data
    private var inFlight: [String: InFlight] = [:]

    private struct InFlight {
        let task: Task<UIImage, any Error>
        var waiters: Int
    }

    init(cache: ImageCache = ImageCache(), fetch: @escaping @Sendable (URL) async throws -> Data = ImageLoader.download) {
        self.cache = cache
        self.fetch = fetch
    }

    func image(for request: ImageRequest) async throws -> UIImage {
        if let hit = cache.image(for: request), hit.isSufficient { return hit.image }
        let key = request.key
        let task: Task<UIImage, any Error>
        if var existing = inFlight[key] {
            existing.waiters += 1
            inFlight[key] = existing
            task = existing.task
        } else {
            task = Task.detached { [fetch, cache] in
                let data = try await fetch(request.url)
                try Task.checkCancellation()
                guard let image = ImageLoader.downsample(data, coveringPixels: request.pixels) else {
                    throw URLError(.cannotDecodeContentData)
                }
                cache.insert(image, for: request)
                return image
            }
            inFlight[key] = InFlight(task: task, waiters: 1)
        }
        defer { finish(key, task) }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            Task { await self.release(key, task) }
        }
    }

    /// Number of downloads currently running (for tests).
    var inFlightCount: Int { inFlight.count }

    /// Views waiting on `request`'s download (for tests).
    func waiters(for request: ImageRequest) -> Int { inFlight[request.key]?.waiters ?? 0 }

    private func finish(_ key: String, _ task: Task<UIImage, any Error>) {
        if inFlight[key]?.task == task { inFlight[key] = nil }
    }

    private func release(_ key: String, _ task: Task<UIImage, any Error>) {
        guard var entry = inFlight[key], entry.task == task else { return }
        entry.waiters -= 1
        if entry.waiters > 0 {
            inFlight[key] = entry
        } else {
            entry.task.cancel()
            inFlight[key] = nil
        }
    }

    /// Decodes `data` so its shorter side is at least `pixels` (never upscaling), honouring EXIF orientation.
    nonisolated static func downsample(_ data: Data, coveringPixels pixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        let longest = max(width, height)
        let shortest = min(width, height)
        let target = min(longest, Int((Double(longest) * Double(pixels) / Double(shortest)).rounded(.up)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    /// A session with its own HTTP cache, so images survive relaunches without crowding `URLCache.shared`.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        let directory = URL.cachesDirectory.appending(path: "RemoteImage", directoryHint: .isDirectory)
        configuration.urlCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            directory: directory
        )
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }()

    @Sendable static func download(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
