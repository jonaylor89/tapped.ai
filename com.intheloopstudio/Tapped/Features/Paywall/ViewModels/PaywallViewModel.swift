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
        Feature(title: "find your next stage", detail: "discover gigs and venues that fit your sound.", systemImage: "music.mic"),
        Feature(title: "make the connection", detail: "reach out to venues and keep conversations in one place.", systemImage: "bubble.left.and.bubble.right"),
        Feature(title: "go after every opportunity", detail: "unlimited gig applications. no extra feature unlocks.", systemImage: "infinity"),
    ]

    static let privacyURL = URL(string: "https://app.tapped.ai/privacy")!
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private(set) var phase: Phase = .loading
    private(set) var products: [PremiumProduct] = []
    var selectedProductId: String?
    private(set) var isPremium = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    /// Actionable purchase/restore status. User cancellation stays silent.
    var notice: String?
    /// Increments on every successful purchase/restore; drives the success haptic.
    private(set) var successCount = 0
    private(set) var errorCount = 0

    private var hasRecordedView = false
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
        if !hasRecordedView {
            hasRecordedView = true
            await analytics.track("premium_activation_viewed")
        }
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

    /// Observe verified StoreKit updates, including Ask to Buy approval on a later launch.
    func observeEntitlements() async {
        for await entitlements in purchases.entitlementUpdates() {
            isPremium = entitlements.contains(.premium)
        }
    }

    func purchase() async {
        guard phase == .ready, let product = selectedProduct, !isBusy, !isPremium else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        await analytics.track("premium_purchase_started", properties: ["product_id": .string(product.id)])
        do {
            switch try await purchases.purchase(productId: product.id) {
            case .purchased:
                isPremium = await purchases.isPremium()
                if isPremium {
                    successCount += 1
                    await analytics.track("premium_purchased", properties: ["product_id": .string(product.id)])
                } else {
                    notice = "your purchase is processing. try restore purchases in a moment."
                }
            case .pending:
                notice = "purchase pending approval"
                await analytics.track("premium_purchase_pending")
            case .cancelled:
                await analytics.track("premium_purchase_cancelled")
            }
        } catch {
            FirebaseBootstrap.record(error: error)
            errorCount += 1
            notice = ErrorCopy.action("complete the purchase", hint: "check your App Store account or try restoring purchases")
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
                await analytics.track("premium_restored")
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
