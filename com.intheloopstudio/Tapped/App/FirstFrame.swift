import QuartzCore

/// Lets launch work that isn't needed for the first frame wait until that frame is on screen.
@MainActor
enum FirstFrame {
    /// Resumes on the next display refresh, after the frame currently being built has been committed.
    static func rendered() async {
        await withCheckedContinuation { continuation in
            let ticker = Ticker(continuation)
            CADisplayLink(target: ticker, selector: #selector(Ticker.tick(_:))).add(to: .main, forMode: .common)
        }
    }

    @MainActor
    private final class Ticker: NSObject {
        private var continuation: CheckedContinuation<Void, Never>?

        init(_ continuation: CheckedContinuation<Void, Never>) {
            self.continuation = continuation
        }

        @objc func tick(_ link: CADisplayLink) {
            link.invalidate()
            continuation?.resume()
            continuation = nil
        }
    }
}
