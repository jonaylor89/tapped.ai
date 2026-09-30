import Foundation
import StoreKit

/// StoreKit 2 implementation. Any verified, unrevoked transaction for one of `productIds` grants `premium`.
public struct StoreKitPurchasesRepository: PurchasesRepository {
    let productIds: [String]
    private let broadcaster = EntitlementBroadcaster()

    public init(productIds: [String]) {
        self.productIds = productIds
    }

    public func products() async throws -> [PremiumProduct] {
        try await Product.products(for: productIds)
            .sorted { $0.price < $1.price }
            .map { product in
                PremiumProduct(
                    id: product.id,
                    displayName: product.displayName,
                    description: product.description,
                    displayPrice: product.displayPrice,
                    period: product.subscription.flatMap { Self.period($0.subscriptionPeriod) }
                )
            }
    }

    public func purchase(productId: String) async throws -> PurchaseOutcome {
        guard let product = try await Product.products(for: [productId]).first else {
            throw StoreKitError.notEntitled
        }
        switch try await product.purchase() {
        case let .success(verification):
            let transaction = try verification.payloadValue
            await transaction.finish()
            await broadcaster.publish(await activeEntitlements())
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    public func restorePurchases() async throws {
        try await AppStore.sync()
        await broadcaster.publish(await activeEntitlements())
    }

    public func activeEntitlements() async -> Set<Entitlement> {
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  transaction.revocationDate == nil,
                  productIds.contains(transaction.productID) else { continue }
            return [.premium]
        }
        return []
    }

    public func entitlementUpdates() -> AsyncStream<Set<Entitlement>> {
        AsyncStream { continuation in
            let id = UUID()
            let broadcaster = broadcaster
            let task = Task {
                await broadcaster.register(id, continuation)
                continuation.yield(await activeEntitlements())
                for await update in Transaction.updates {
                    if case let .verified(transaction) = update { await transaction.finish() }
                    continuation.yield(await activeEntitlements())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await broadcaster.unregister(id) }
            }
        }
    }

    private static func period(_ period: Product.SubscriptionPeriod) -> PremiumProduct.Period? {
        switch period.unit {
        case .day: .day
        case .week: .week
        case .month: .month
        case .year: .year
        @unknown default: nil
        }
    }
}
