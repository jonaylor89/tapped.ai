import SwiftUI
import Testing
@testable import TappedUI

@Suite("FlowLayout + copy helpers")
struct FlowLayoutTests {
    @Test func wrapsWhenTheRowIsFull() {
        let sizes = Array(repeating: CGSize(width: 40, height: 20), count: 3)
        let frames = FlowLayout.frames(for: sizes, maxWidth: 100, spacing: 10, lineSpacing: 10)
        #expect(frames.map(\.origin) == [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 0, y: 30)])
        #expect(FlowLayout.size(of: sizes, maxWidth: 100, spacing: 10, lineSpacing: 10) == CGSize(width: 90, height: 50))
    }

    @Test func keepsOneRowWhenEverythingFits() {
        let sizes = [CGSize(width: 30, height: 10), CGSize(width: 30, height: 24)]
        #expect(FlowLayout.size(of: sizes, maxWidth: 200, spacing: 8, lineSpacing: 4) == CGSize(width: 68, height: 24))
        #expect(FlowLayout.size(of: sizes, maxWidth: .infinity, spacing: 8, lineSpacing: 4).height == 24)
    }

    @Test func clampsOversizedItemsToTheWidth() {
        let frames = FlowLayout.frames(for: [CGSize(width: 500, height: 40), CGSize(width: 20, height: 20)], maxWidth: 120, spacing: 8, lineSpacing: 6)
        #expect(frames[0].width == 120)
        #expect(frames[1].origin == CGPoint(x: 0, y: 46))
    }

    @Test func emptyLayoutIsZero() {
        #expect(FlowLayout.size(of: [], maxWidth: 100, spacing: 8, lineSpacing: 8) == .zero)
    }

    @Test func errorCopyNamesObjectCauseAndNextStep() {
        let message = ErrorCopy.load("your bookings")
        #expect(message == "couldn't load your bookings — check your connection and try again")
        #expect(ErrorCopy.headline(message) == "couldn't load your bookings")
        #expect(ErrorCopy.detail(message) == "check your connection and try again")
        #expect(ErrorCopy.detail("plain") == "")
    }

    @MainActor @Test func newViewsRender() {
        for view in [AnyView(OfflineBanner()), AnyView(PremiumBadge()), AnyView(FlowLayout { Text("a"); Text("b") })] {
            let size = ImageRenderer(content: view.frame(width: 320)).uiImage?.size ?? .zero
            #expect(size.height > 0)
        }
    }
}
