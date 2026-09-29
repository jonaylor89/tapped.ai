import Foundation

/// Error copy: what failed — likely cause and next step. Pair with `ErrorView`'s retry button.
/// `ErrorView` splits these on the em dash into a headline and a description.
public enum ErrorCopy {
    public static let separator = " — "
    public static let connectionHint = "check your connection and try again"

    /// "couldn't load your bookings — check your connection and try again"
    public static func load(_ object: String, hint: String = connectionHint) -> String {
        "couldn't load \(object)\(separator)\(hint)"
    }

    /// "couldn't save your profile — check your connection and try again"
    public static func save(_ object: String, hint: String = connectionHint) -> String {
        "couldn't save \(object)\(separator)\(hint)"
    }

    /// "couldn't send your application — check your connection and try again"
    public static func action(_ what: String, hint: String = connectionHint) -> String {
        "couldn't \(what)\(separator)\(hint)"
    }

    /// Part before the separator ("couldn't load your bookings"); the whole message when there is none.
    public static func headline(_ message: String) -> String {
        message.components(separatedBy: separator).first ?? message
    }

    /// Part after the separator ("check your connection and try again"); empty when there is none.
    public static func detail(_ message: String) -> String {
        guard let range = message.range(of: separator) else { return "" }
        return String(message[range.upperBound...])
    }
}
