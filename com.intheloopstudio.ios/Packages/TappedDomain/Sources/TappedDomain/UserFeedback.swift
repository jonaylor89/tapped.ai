import Foundation

/// Payload for `DatabaseRepository.sendFeedback` (the Flutter app uses the `feedback` package's type).
public struct UserFeedback: Codable, Sendable, Hashable {
    public var text: String
    public var extra: [String: String]

    public init(text: String, extra: [String: String] = [:]) {
        self.text = text
        self.extra = extra
    }
}
