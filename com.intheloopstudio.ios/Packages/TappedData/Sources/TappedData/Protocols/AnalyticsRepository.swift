import Foundation

/// Product analytics (PostHog). Firebase Analytics is intentionally not used.
public protocol AnalyticsRepository: Sendable {
    func identify(userId: String, properties: [String: AnalyticsValue]) async
    func track(_ event: String, properties: [String: AnalyticsValue]) async
    func screen(_ name: String, properties: [String: AnalyticsValue]) async
    func reset() async
}

public extension AnalyticsRepository {
    func track(_ event: String) async { await track(event, properties: [:]) }
    func screen(_ name: String) async { await screen(name, properties: [:]) }
}

public enum AnalyticsValue: Sendable, Hashable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral, ExpressibleByFloatLiteral {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(floatLiteral value: Double) { self = .double(value) }

    var anyValue: Any {
        switch self {
        case let .string(v): v
        case let .int(v): v
        case let .double(v): v
        case let .bool(v): v
        }
    }
}
