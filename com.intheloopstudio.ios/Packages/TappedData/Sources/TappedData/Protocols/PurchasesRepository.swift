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
    public var id: String
    public var displayName: String
    public var description: String
    public var displayPrice: String

    public init(id: String, displayName: String, description: String, displayPrice: String) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.displayPrice = displayPrice
    }
}

public enum PurchaseOutcome: Sendable, Hashable {
    case purchased
    case pending
    case cancelled
}
