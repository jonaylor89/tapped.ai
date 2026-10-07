import Foundation
import Synchronization

public final class MockTelemetryRepository: TelemetryRepository {
    private let recorded = Mutex<[TelemetrySpan]>([])

    public init() {}

    public var spans: [TelemetrySpan] { recorded.withLock { $0 } }

    public func record(_ spans: [TelemetrySpan]) async {
        recorded.withLock { $0.append(contentsOf: spans) }
    }
}
