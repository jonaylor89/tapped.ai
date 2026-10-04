import Foundation
import Network
import Observation

/// Reachability updates. `NWPathNetworkSource` is live; `MockNetworkSource` drives tests and screenshots.
public protocol NetworkPathSource: Sendable {
    /// `true` while a satisfied path exists. Yields the current value first.
    func updates() -> AsyncStream<Bool>
}

/// `NWPathMonitor` over all interfaces.
public struct NWPathNetworkSource: NetworkPathSource {
    public init() {}

    public func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { continuation.yield($0.status == .satisfied) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "ai.tapped.network-monitor"))
        }
    }
}

/// Emits `initial`, then every `send(_:)`.
public final class MockNetworkSource: NetworkPathSource, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Bool
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    public init(isOnline: Bool = true) {
        current = isOnline
    }

    public func send(_ isOnline: Bool) {
        let targets = lock.withLock {
            current = isOnline
            return Array(continuations.values)
        }
        for continuation in targets { continuation.yield(isOnline) }
    }

    public func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let id = UUID()
            let value = lock.withLock {
                continuations[id] = continuation
                return current
            }
            continuation.yield(value)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                _ = lock.withLock { self.continuations.removeValue(forKey: id) }
            }
        }
    }
}

/// Observable connectivity for offline banners. Starts listening on init.
@Observable
@MainActor
public final class NetworkMonitor {
    public private(set) var isOnline = true
    public var isOffline: Bool { !isOnline }

    @ObservationIgnored private var task: Task<Void, Never>?

    public init(source: any NetworkPathSource = NWPathNetworkSource()) {
        task = Task { [weak self] in
            for await isOnline in source.updates() {
                guard let self else { return }
                if self.isOnline != isOnline { self.isOnline = isOnline }
            }
        }
    }

    isolated deinit {
        task?.cancel()
    }

    /// App-wide monitor. `TAPPED_MOCK_OFFLINE=1` forces offline for screenshots.
    public static let shared = NetworkMonitor(
        source: ProcessInfo.processInfo.environment["TAPPED_MOCK_OFFLINE"] == "1" ? MockNetworkSource(isOnline: false) : NWPathNetworkSource()
    )
}
