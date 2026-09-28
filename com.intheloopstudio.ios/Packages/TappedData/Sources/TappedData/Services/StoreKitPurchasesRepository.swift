import Foundation
import StoreKit

/// StoreKit 2 implementation. Any verified, unrevoked transaction for one of `productIds` grants `premium`.
public struct StoreKitPurchasesRepository: PurchasesRepository {
    let productIds: [String]

    public init(productIds: [String]) {
        self.productIds = productIds
    }

    public func products() async throws -> [PremiumProduct] {
        try await Product.products(for: productIds)
            .sorted { $0.price < $1.price }
            .map { PremiumProduct(id: $0.id, displayName: $0.displayName, description: $0.description, displayPrice: $0.displayPrice) }
    }

    public func purchase(productId: String) async throws -> PurchaseOutcome {
        guard let product = try await Product.products(for: [productId]).first else {
            throw StoreKitError.notEntitled
        }
        switch try await product.purchase() {
        case let .success(verification):
            let transaction = try verification.payloadValue
            await transaction.finish()
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
            let task = Task {
                continuation.yield(await activeEntitlements())
                for await update in Transaction.updates {
                    if case let .verified(transaction) = update { await transaction.finish() }
                    continuation.yield(await activeEntitlements())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
