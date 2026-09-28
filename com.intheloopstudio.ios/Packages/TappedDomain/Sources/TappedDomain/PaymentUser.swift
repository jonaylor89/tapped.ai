import Foundation

/// `payment_user.dart`. Kept for data compatibility with existing Firestore/Stripe Connect records;
/// the native app does not integrate Stripe.
public struct PaymentUser: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var chargesEnabled: Bool
    public var payoutsEnabled: Bool
    public var country: String
    public var createdAt: Date
    public var defaultCurrency: String
    public var detailsSubmitted: Bool

    public init(
        id: String,
        chargesEnabled: Bool,
        payoutsEnabled: Bool,
        country: String,
        createdAt: Date,
        defaultCurrency: String,
        detailsSubmitted: Bool
    ) {
        self.id = id
        self.chargesEnabled = chargesEnabled
        self.payoutsEnabled = payoutsEnabled
        self.country = country
        self.createdAt = createdAt
        self.defaultCurrency = defaultCurrency
        self.detailsSubmitted = detailsSubmitted
    }

    enum CodingKeys: String, CodingKey {
        case id
        case chargesEnabled = "charges_enabled"
        case payoutsEnabled = "payouts_enabled"
        case country
        case createdAt = "created"
        case defaultCurrency = "default_currency"
        case detailsSubmitted = "details_submitted"
    }
}
