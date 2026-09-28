import Foundation

/// Thrown by repository methods that have a protocol requirement but no implementation yet.
/// Follow-up sessions replace these; never use `fatalError` for unimplemented data paths.
public struct NotImplemented: Error, Sendable, Equatable, CustomStringConvertible {
    public let function: String

    public init(_ function: String = #function) {
        self.function = function
    }

    public var description: String { "not implemented: \(function)" }
}
