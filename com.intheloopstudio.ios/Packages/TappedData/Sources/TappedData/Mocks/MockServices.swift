import Foundation
import TappedDomain

/// Filters `Samples` locally; used in mock mode, previews and tests.
public struct MockSearchRepository: SearchRepository {
    public var users: [UserModel]
    public var opportunities: [Opportunity]
    public var bookings: [Booking]

    public init(users: [UserModel] = Samples.performers + Samples.venues, opportunities: [Opportunity] = Samples.opportunities, bookings: [Booking] = Samples.bookings) {
        self.users = users
        self.opportunities = opportunities
        self.bookings = bookings
    }

    public func queryUsers(_ input: String, filters: UserSearchFilters, lat: Double?, lng: Double?, radius: Int, limit: Int) async throws -> [UserModel] {
        Array(users.filter { matches($0, input: input, filters: filters) }.prefix(limit))
    }

    public func queryUsersInBoundingBox(_ input: String, bounds: GeoBounds, filters: UserSearchFilters, limit: Int) async throws -> [UserModel] {
        Array(users.filter { user in
            guard let location = user.location, bounds.contains(lat: location.lat, lng: location.lng) else { return false }
            return matches(user, input: input, filters: filters)
        }.prefix(limit))
    }

    public func queryBookings(_ input: String, lat: Double?, lng: Double?, radius: Int) async throws -> [Booking] { bookings }

    public func queryBookingsInBoundingBox(_ input: String, bounds: GeoBounds, limit: Int) async throws -> [Booking] {
        bookings.filter { $0.location.map { bounds.contains(lat: $0.lat, lng: $0.lng) } ?? false }
    }

    public func queryOpportunities(_ input: String, lat: Double?, lng: Double?, radius: Int, startTime: Date?) async throws -> [Opportunity] {
        opportunities.filter { input.isEmpty || $0.title.localizedCaseInsensitiveContains(input) }
    }

    public func queryOpportunitiesInBoundingBox(_ input: String, bounds: GeoBounds, limit: Int, startTime: Date?) async throws -> [Opportunity] {
        opportunities.filter { bounds.contains(lat: $0.location.lat, lng: $0.location.lng) }
    }

    private func matches(_ user: UserModel, input: String, filters: UserSearchFilters) -> Bool {
        if !input.isEmpty,
           !user.displayName.localizedCaseInsensitiveContains(input),
           !user.username.username.localizedCaseInsensitiveContains(input) { return false }
        if let occupations = filters.occupations, !occupations.isEmpty,
           !user.occupations.contains(where: occupations.contains) { return false }
        if let genres = filters.venueGenres, !genres.isEmpty,
           !(user.venueInfo?.genres ?? []).contains(where: genres.contains) { return false }
        if let genres = filters.genres, !genres.isEmpty,
           !(user.performerInfo?.genres ?? []).contains(where: genres.contains) { return false }
        if let min = filters.minCapacity, (user.venueInfo?.capacity ?? 0) < min { return false }
        if let max = filters.maxCapacity, (user.venueInfo?.capacity ?? 0) > max { return false }
        return true
    }
}

public struct MockPlacesRepository: PlacesRepository {
    public static let places: [PlaceData] = [
        PlaceData(placeId: Location.rva.placeId, name: "Richmond", shortFormattedAddress: "Richmond, VA, USA", lat: Location.rva.lat, lng: Location.rva.lng, locality: "Richmond"),
        PlaceData(placeId: Location.nyc.placeId, name: "New York", shortFormattedAddress: "New York, NY, USA", lat: Location.nyc.lat, lng: Location.nyc.lng, locality: "New York"),
        PlaceData(placeId: "ChIJW-T2Wt7Gt4kRKl2I1CJFUsI", name: "Washington", shortFormattedAddress: "Washington, DC, USA", lat: 38.9072, lng: -77.0369, locality: "Washington"),
    ]

    public init() {}

    public func searchPlace(_ query: String) async throws -> [AutocompletePrediction] {
        Self.places
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .map { AutocompletePrediction(placeId: $0.placeId, fullText: $0.shortFormattedAddress ?? $0.name, primaryText: $0.name, secondaryText: $0.shortFormattedAddress ?? "") }
    }

    public func getPlaceById(_ placeId: String) async throws -> PlaceData? { Self.places.first { $0.placeId == placeId } }
    public func getPhotoUrl(photoName: String, maxHeightPx: Int) async throws -> URL? { nil }
    public func getPlaceIdByLatLng(lat: Double, lng: Double) async throws -> String? { Location.rva.placeId }
}

public actor MockPurchasesRepository: PurchasesRepository {
    private var entitlements: Set<Entitlement>

    public init(isPremium: Bool = false) {
        entitlements = isPremium ? [.premium] : []
    }

    public func products() async throws -> [PremiumProduct] {
        [
            PremiumProduct(id: TappedConfig.defaultPremiumProductIds[0], displayName: "tapped premium", description: "monthly", displayPrice: "$9.99"),
            PremiumProduct(id: TappedConfig.defaultPremiumProductIds[1], displayName: "tapped premium", description: "yearly", displayPrice: "$79.99"),
        ]
    }

    public func purchase(productId: String) async throws -> PurchaseOutcome {
        entitlements.insert(.premium)
        return .purchased
    }

    public func restorePurchases() async throws {}
    public func activeEntitlements() async -> Set<Entitlement> { entitlements }

    public nonisolated func entitlementUpdates() -> AsyncStream<Set<Entitlement>> {
        AsyncStream { continuation in
            Task { continuation.yield(await self.activeEntitlements()) }
        }
    }
}

/// Records events so tests can assert on them.
public actor MockAnalytics: AnalyticsRepository {
    public private(set) var events: [String] = []
    public private(set) var screens: [String] = []
    public private(set) var identifiedUserId: String?

    public init() {}

    public func identify(userId: String, properties: [String: AnalyticsValue]) async { identifiedUserId = userId }
    public func track(_ event: String, properties: [String: AnalyticsValue]) async { events.append(event) }
    public func screen(_ name: String, properties: [String: AnalyticsValue]) async { screens.append(name) }
    public func reset() async { identifiedUserId = nil }
}

public struct MockRemoteConfigRepository: RemoteConfigRepository {
    public var downForMaintenance: Bool
    public var bookingFee: Double
    public var minimumAppVersion: String
    public var latestAppVersion: String
    public var premiumWaitlistEnabled: Bool

    public init(
        downForMaintenance: Bool = false,
        bookingFee: Double = 0.1,
        minimumAppVersion: String = "",
        latestAppVersion: String = "",
        premiumWaitlistEnabled: Bool = false
    ) {
        self.downForMaintenance = downForMaintenance
        self.bookingFee = bookingFee
        self.minimumAppVersion = minimumAppVersion
        self.latestAppVersion = latestAppVersion
        self.premiumWaitlistEnabled = premiumWaitlistEnabled
    }

    public func fetchAndActivate() async throws -> Bool { true }
    public func getDownForMaintenanceStatus() async -> Bool { downForMaintenance }
    public func getBookingFee() async -> Double { bookingFee }
    public func getMinimumAppVersion() async -> String { minimumAppVersion }
    public func getLatestAppVersion() async -> String { latestAppVersion }
    public func getPremiumWaitlistEnabled() async -> Bool { premiumWaitlistEnabled }
}
