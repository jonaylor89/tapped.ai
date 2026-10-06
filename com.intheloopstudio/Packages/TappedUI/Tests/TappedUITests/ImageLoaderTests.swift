import Foundation
import TappedDomain
import Testing
import UIKit
@testable import TappedUI

@Suite("RemoteImage loader + cache")
struct ImageLoaderTests {
    let proxy = ImageProxy(baseURL: URL(string: "https://img.tapped.ai")!)
    let source = URL(string: "https://firebasestorage.googleapis.com/v0/b/in-the-loop-306520.appspot.com/o/a.jpg?alt=media")!
    let other = URL(string: "https://example.com/a.jpg")!

    private func request(_ source: URL, _ width: CGFloat, _ height: CGFloat, proxy: ImageProxy? = nil) -> ImageRequest {
        ImageRequest(source: source, proxy: proxy ?? self.proxy, size: CGSize(width: width, height: height), scale: 3)!
    }

    private static func png(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private static func image(pixels: Int) -> UIImage {
        ImageLoader.downsample(png(width: pixels, height: pixels), coveringPixels: pixels)!
    }

    // MARK: Requests

    @Test func requestIsStableWithinAPreset() {
        // 300…360 pt @3x = 900…1080 px: one `w1080` request, so a growing sheet doesn't refetch.
        let requests = stride(from: CGFloat(300), through: 360, by: 10).map { request(source, $0, 200) }
        #expect(Set(requests).count == 1)
        #expect(requests[0].url.pathComponents[2] == "w1080")
        #expect(request(source, 361, 200).url.pathComponents[2] == "w1600")
    }

    @Test func emptyOrNonFiniteSizesHaveNoRequest() {
        #expect(ImageRequest(source: source, proxy: proxy, size: .zero, scale: 3) == nil)
        #expect(ImageRequest(source: source, proxy: proxy, size: CGSize(width: CGFloat.infinity, height: 10), scale: 3) == nil)
    }

    @Test func unproxiedImagesShareOneGroupAcrossCrops() {
        let square = request(other, 44, 44)
        let wide = request(other, 300, 100)
        #expect(square.url == other && wide.url == other)
        #expect(square.group == wide.group)
        #expect(square.key != wide.key)
        // Proxied: a square crop can't stand in for a width-fit variant.
        #expect(request(source, 44, 44).group != request(source, 300, 100).group)
    }

    // MARK: Cache

    @Test func largerCachedVariantCoversSmallerRequests() throws {
        let cache = ImageCache()
        let large = request(source, 120, 120) // sq384
        cache.insert(Self.image(pixels: 384), for: large)

        let small = request(source, 20, 20) // sq64
        let hit = try #require(cache.image(for: small))
        #expect(hit.isSufficient)
        #expect(hit.image.cgImage?.width == 384)
    }

    @Test func smallerCachedVariantIsAPlaceholderOnly() throws {
        let cache = ImageCache()
        cache.insert(Self.image(pixels: 64), for: request(source, 20, 20))
        let hit = try #require(cache.image(for: request(source, 120, 120)))
        #expect(!hit.isSufficient)
        #expect(hit.image.cgImage?.width == 64)
    }

    @Test func prefersTheSmallestCoveringVariant() throws {
        let cache = ImageCache()
        cache.insert(Self.image(pixels: 384), for: request(source, 120, 120))
        cache.insert(Self.image(pixels: 128), for: request(source, 40, 40))
        let hit = try #require(cache.image(for: request(source, 20, 20)))
        #expect(hit.isSufficient)
        #expect(hit.image.cgImage?.width == 128)
    }

    @Test func otherCropsAndImagesDontMatch() {
        let cache = ImageCache()
        cache.insert(Self.image(pixels: 384), for: request(source, 120, 120))
        #expect(cache.image(for: request(source, 300, 100)) == nil)
        #expect(cache.image(for: request(other, 20, 20)) == nil)
    }

    @Test func evictionDropsTheIndexEntry() {
        let cache = ImageCache(countLimit: 1)
        let first = request(source, 20, 20)
        cache.insert(Self.image(pixels: 64), for: first)
        cache.insert(Self.image(pixels: 64), for: request(other, 20, 20))
        #expect(cache.image(for: first) == nil)
        cache.removeAll()
        #expect(cache.image(for: request(other, 20, 20)) == nil)
    }

    // MARK: Decoding

    @Test func downsamplesSoTheShorterSideCovers() throws {
        let image = try #require(ImageLoader.downsample(Self.png(width: 800, height: 400), coveringPixels: 100))
        #expect(image.cgImage?.width == 200)
        #expect(image.cgImage?.height == 100)
    }

    @Test func neverUpscales() throws {
        let image = try #require(ImageLoader.downsample(Self.png(width: 300, height: 150), coveringPixels: 1080))
        #expect(image.cgImage?.width == 300)
        #expect(ImageLoader.downsample(Data("not an image".utf8), coveringPixels: 64) == nil)
    }

    // MARK: Loader

    @Test func coalescesConcurrentRequestsAndCaches() async throws {
        let fetches = Fetches(data: Self.png(width: 400, height: 400))
        let loader = ImageLoader(cache: ImageCache()) { try await fetches.fetch($0) }
        let req = request(source, 40, 40)

        async let first = loader.image(for: req)
        async let second = loader.image(for: req)
        let images = try await [first, second]
        #expect(images[0] === images[1])
        #expect(await fetches.count == 1)

        _ = try await loader.image(for: request(source, 20, 20)) // covered by the cached sq128
        #expect(await fetches.count == 1)
        #expect(await loader.inFlightCount == 0)
    }

    @Test func cancellingTheLastWaiterCancelsTheDownload() async throws {
        let fetches = Fetches(data: Self.png(width: 64, height: 64), delay: .seconds(10))
        let loader = ImageLoader(cache: ImageCache()) { try await fetches.fetch($0) }
        let req = request(source, 20, 20)

        let waiter = Task { try await loader.image(for: req) }
        while await fetches.count == 0 { await Task.yield() }
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(await fetches.cancelled == 1)
        #expect(await loader.inFlightCount == 0)
        #expect(loader.cache.image(for: req) == nil)
    }

    @Test func oneCancelledWaiterDoesntCancelTheOthers() async throws {
        let fetches = Fetches(data: Self.png(width: 64, height: 64), delay: .milliseconds(300))
        let loader = ImageLoader(cache: ImageCache()) { try await fetches.fetch($0) }
        let req = request(source, 20, 20)

        let leaving = Task { try await loader.image(for: req) }
        let staying = Task { try await loader.image(for: req) }
        while await loader.waiters(for: req) < 2 { await Task.yield() }
        leaving.cancel()
        let image = try await staying.value
        #expect(image.cgImage?.width == 64)
        #expect(await fetches.count == 1)
        #expect(await fetches.cancelled == 0)
    }
}

private actor Fetches {
    let data: Data
    let delay: Duration
    private(set) var count = 0
    private(set) var cancelled = 0

    init(data: Data, delay: Duration = .milliseconds(50)) {
        self.data = data
        self.delay = delay
    }

    func fetch(_ url: URL) async throws -> Data {
        count += 1
        do {
            try await Task.sleep(for: delay)
        } catch {
            cancelled += 1
            throw error
        }
        return data
    }
}
