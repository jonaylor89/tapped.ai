import Foundation

/// Holds a non-`Sendable` listener handle so it can be removed from an `onTermination` closure.
/// Only use for opaque registration tokens that are safe to touch from any thread.
final class ListenerBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

extension Array {
    /// Runs `transform` concurrently and returns non-nil results in the original order.
    func concurrentCompactMap<T: Sendable>(
        _ transform: @escaping @Sendable (Element) async throws -> T?
    ) async throws -> [T] where Element: Sendable {
        try await withThrowingTaskGroup(of: (Int, T?).self) { group in
            for (index, element) in enumerated() {
                group.addTask { (index, try await transform(element)) }
            }
            var results = [(Int, T)]()
            for try await (index, value) in group {
                if let value { results.append((index, value)) }
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
