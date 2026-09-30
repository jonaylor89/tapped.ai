import Foundation
import Observation
import TappedData
import TappedUI

/// `lib/ui/paywall/paywall_view.dart` + `subscription_bloc`, on StoreKit 2 via `PurchasesRepository`.
@Observable
@MainActor
final class PaywallViewModel {
    struct Feature: Hashable {
        let title: String
        let detail: String
        let systemImage: String
    }

    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    static let features: [Feature] = [
        Feature(title: "unlimited gig opportunities", detail: "apply to every gig on the map, no daily cap", systemImage: "infinity"),
        Feature(title: "venue intel", detail: "exclusive info on venues actively looking for performers", systemImage: "building.2.fill"),
        Feature(title: "direct contact", detail: "booking emails and phone numbers for thousands of venues", systemImage: "envelope.fill"),
        Feature(title: "advanced search", detail: "filter by capacity, genre, and who venues actually book", systemImage: "slider.horizontal.3"),
    ]

    static let privacyURL = URL(string: "https://app.tapped.ai/privacy")!
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private(set) var phase: Phase = .loading
    private(set) var products: [PremiumProduct] = []
    var selectedProductId: String?
    private(set) var isPremium = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    /// Transient message shown in an alert ("purchase canceled", errors…).
    var notice: String?
    /// Increments on every successful purchase/restore; drives the success haptic.
    private(set) var successCount = 0
    private(set) var errorCount = 0

    private let purchases: any PurchasesRepository
    private let analytics: any AnalyticsRepository

    init(dependencies: Dependencies) {
        purchases = dependencies.purchases
        analytics = dependencies.analytics
    }

    var selectedProduct: PremiumProduct? {
        products.first { $0.id == selectedProductId } ?? products.first
    }

    var isBusy: Bool { isPurchasing || isRestoring }

    var ctaTitle: String {
        guard let product = selectedProduct else { return "get full access" }
        guard let period = product.period else { return "get full access · \(product.displayPrice)" }
        return "get full access · \(product.displayPrice) / \(period.rawValue)"
    }

    static func planTitle(_ product: PremiumProduct) -> String {
        switch product.period {
        case .day: "daily"
        case .week: "weekly"
        case .month: "monthly"
        case .year: "yearly"
        case nil: product.displayName.lowercased()
        }
    }

    func load() async {
        phase = .loading
        isPremium = await purchases.isPremium()
        do {
            products = try await purchases.products()
            if selectedProductId == nil { selectedProductId = products.first?.id }
            phase = products.isEmpty && !isPremium ? .failed(ErrorCopy.load("premium plans", hint: "check your connection or App Store sign-in and try again")) : .ready
        } catch {
            FirebaseBootstrap.record(error: error)
            phase = isPremium ? .ready : .failed(ErrorCopy.load("premium plans", hint: "check your connection or App Store sign-in and try again"))
        }
    }

    /// Keeps `isPremium` in sync with transaction updates (e.g. purchases on another device, Ask to Buy).
    /// IDs for `SubscriptionStoreView`: whatever the repository loaded, else the bundled defaults.
    var productIds: [String] { products.isEmpty ? TappedConfig.defaultPremiumProductIds : products.map(\.id) }

    /// Called from `SubscriptionStoreView`'s completion handlers.
    func storeCompleted(purchased: Bool, restored: Bool = false) async {
        if purchased || restored {
            isPremium = await purchases.isPremium() || purchased
            successCount += 1
            await analytics.track(restored ? "restore_purchases" : "purchase_premium")
        } else {
            errorCount += 1
        }
    }

    func observeEntitlements() async {
        for await entitlements in purchases.entitlementUpdates() {
            isPremium = entitlements.contains(.premium)
        }
    }

    func purchase() async {
        guard let product = selectedProduct, !isBusy else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await purchases.purchase(productId: product.id) {
            case .purchased:
                isPremium = true
                successCount += 1
                await analytics.track("premium_purchased", properties: ["product_id": .string(product.id)])
            case .pending:
                notice = "purchase pending approval"
            case .cancelled:
                notice = "purchase canceled"
            }
        } catch {
            FirebaseBootstrap.record(error: error)
            errorCount += 1
            notice = ErrorCopy.action("complete the purchase", hint: "you weren't charged. try again")
        }
    }

    func restore() async {
        guard !isBusy else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await purchases.restorePurchases()
            isPremium = await purchases.isPremium()
            if isPremium {
                successCount += 1
            } else {
                notice = "no purchases to restore"
            }
        } catch {
            FirebaseBootstrap.record(error: error)
            errorCount += 1
            notice = ErrorCopy.action("restore purchases")
        }
    }
}
