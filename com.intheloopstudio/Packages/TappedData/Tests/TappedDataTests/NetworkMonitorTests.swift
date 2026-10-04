import Foundation
import Testing
@testable import TappedData

@MainActor
@Suite("NetworkMonitor")
struct NetworkMonitorTests {
    private func settle(_ monitor: NetworkMonitor, until condition: (NetworkMonitor) -> Bool) async {
        for _ in 0..<200 where !condition(monitor) {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func followsTheMockSource() async {
        let source = MockNetworkSource(isOnline: false)
        let monitor = NetworkMonitor(source: source)
        await settle(monitor) { $0.isOffline }
        #expect(monitor.isOffline)
        source.send(true)
        await settle(monitor) { $0.isOnline }
        #expect(monitor.isOnline)
        source.send(false)
        await settle(monitor) { $0.isOffline }
        #expect(!monitor.isOnline)
    }

    @Test func mockStreamReplaysTheLatestValue() async {
        let source = MockNetworkSource(isOnline: true)
        source.send(false)
        var iterator = source.updates().makeAsyncIterator()
        #expect(await iterator.next() == false)
    }
}
