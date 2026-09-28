import Foundation

/// StoreKit 2 premium subscription. Replaces RevenueCat (`subscription_repository.dart`).
public protocol PurchasesRepository: Sendable {
    func products() async throws -> [PremiumProduct]
    func purchase(productId: String) async throws -> PurchaseOutcome
    func restorePurchases() async throws
    func activeEntitlements() async -> Set<Entitlement>
    /// Yields the active entitlements immediately and then after every transaction update.
    func entitlementUpdates() -> AsyncStream<Set<Entitlement>>
}

public extension PurchasesRepository {
    func isPremium() async -> Bool { await activeEntitlements().contains(.premium) }
}

public struct Entitlement: RawRepresentable, Sendable, Hashable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let premium = Entitlement(rawValue: "premium")
}

public struct PremiumProduct: Sendable, Hashable, Identifiable {
    public enum Period: String, Sendable, Hashable {
        case day, week, month, year
    }

    public var id: String
    public var displayName: String
    public var description: String
    public var displayPrice: String
    /// Subscription renewal period; `nil` for non-subscriptions.
    public var period: Period?

    public init(id: String, displayName: String, description: String, displayPrice: String, period: Period? = nil) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.displayPrice = displayPrice
        self.period = period
    }
}

/// Fan-out for entitlement changes that StoreKit's `Transaction.updates` does not report
/// (in-app purchases and restores), shared by every `entitlementUpdates()` stream.
actor EntitlementBroadcaster {
    private var continuations: [UUID: AsyncStream<Set<Entitlement>>.Continuation] = [:]

    func register(_ id: UUID, _ continuation: AsyncStream<Set<Entitlement>>.Continuation) {
        continuations[id] = continuation
    }

    func unregister(_ id: UUID) { continuations[id] = nil }

    func publish(_ entitlements: Set<Entitlement>) {
        for continuation in continuations.values { continuation.yield(entitlements) }
    }
}

public enum PurchaseOutcome: Sendable, Hashable {
    case purchased
    case pending
    case cancelled
}
