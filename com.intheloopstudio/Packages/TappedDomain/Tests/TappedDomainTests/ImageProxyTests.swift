import Foundation
import Testing
@testable import TappedDomain

@Suite("ImageProxy")
struct ImageProxyTests {
    let proxy = ImageProxy(baseURL: URL(string: "https://img.tapped.ai")!)
    let source = URL(string: "https://firebasestorage.googleapis.com/v0/b/in-the-loop-306520.appspot.com/o/images%2Fusers%2Fabc.jpg?alt=media&token=1234")!

    private func preset(_ url: URL) -> String { url.pathComponents[2] }

    @Test func encodesSourceAsBase64URL() throws {
        let url = proxy.url(for: source, pixelWidth: 132, pixelHeight: 132)
        #expect(url.absoluteString.hasPrefix("https://img.tapped.ai/unsafe/sq256/"))
        let encoded = url.lastPathComponent
        #expect(!encoded.contains("+") && !encoded.contains("/") && !encoded.contains("="))
        var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        let decoded = try #require(Data(base64Encoded: base64))
        #expect(String(decoding: decoded, as: UTF8.self) == source.absoluteString)
    }

    @Test func picksSquareCropForSquareBoxes() {
        #expect(preset(proxy.url(for: source, pixelWidth: 54, pixelHeight: 54)) == "sq64")
        #expect(preset(proxy.url(for: source, pixelWidth: 288, pixelHeight: 288)) == "sq384")
        // Bigger than the square ladder: fall back to width-fit.
        #expect(preset(proxy.url(for: source, pixelWidth: 600, pixelHeight: 600)) == "w640")
    }

    @Test func picksWidthPresetByLongestSide() {
        #expect(preset(proxy.url(for: source, pixelWidth: 660, pixelHeight: 360)) == "w828")
        #expect(preset(proxy.url(for: source, pixelWidth: 1206, pixelHeight: 1320)) == "w1600")
        #expect(preset(proxy.url(for: source, pixelWidth: 3000, pixelHeight: 2000)) == "w1600")
    }

    @Test func leavesOtherURLsAlone() {
        let other = URL(string: "https://images.squarespace-cdn.com/a.jpg")!
        #expect(proxy.url(for: other, pixelWidth: 100, pixelHeight: 100) == other)
        #expect(ImageProxy.disabled.url(for: source, pixelWidth: 100, pixelHeight: 100) == source)
        #expect(proxy.url(for: source, pixelWidth: 0, pixelHeight: 100) == source)
    }

    @Test func quantisesBoxesToTheSamePreset() {
        // A sheet growing from 300 to 380 pt wide @3x stays on one rung, so its URL doesn't change.
        let sizes = stride(from: 900, through: 1080, by: 30).map { ImageProxy.preset(pixelWidth: $0, pixelHeight: 600) }
        #expect(Set(sizes) == [ImageProxy.Preset(kind: .width, pixels: 1080)])
        #expect(ImageProxy.preset(pixelWidth: 1081, pixelHeight: 600)?.description == "w1600")
        #expect(ImageProxy.preset(pixelWidth: 0, pixelHeight: 600) == nil)
    }

    @Test func presetURLMatchesSizedURL() {
        let preset = ImageProxy.Preset(kind: .square, pixels: 256)
        #expect(proxy.url(for: source, preset: preset) == proxy.url(for: source, pixelWidth: 200, pixelHeight: 200))
        #expect(proxy.proxies(source))
        #expect(!ImageProxy.disabled.proxies(source))
        #expect(ImageProxy.disabled.url(for: source, preset: preset) == source)
    }
}
