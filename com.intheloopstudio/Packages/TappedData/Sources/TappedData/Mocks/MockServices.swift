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
        Array(users.filter { user in
            if let lat, let lng {
                guard let location = user.location, Self.meters(from: (lat, lng), to: (location.lat, location.lng)) <= Double(radius) else { return false }
            }
            return matches(user, input: input, filters: filters)
        }.prefix(limit))
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
        opportunities.filter { opportunity in
            if let lat, let lng, Self.meters(from: (lat, lng), to: (opportunity.location.lat, opportunity.location.lng)) > Double(radius) { return false }
            return input.isEmpty || opportunity.title.localizedCaseInsensitiveContains(input)
        }
    }

    /// Haversine distance, mirroring Typesense's `location:(lat, lng, r km)` radius filter.
    static func meters(from a: (lat: Double, lng: Double), to b: (lat: Double, lng: Double)) -> Double {
        let r = 6_371_000.0
        let dLat = (b.lat - a.lat) * .pi / 180, dLng = (b.lng - a.lng) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * r * asin(min(1, sqrt(h)))
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
        PlaceData(placeId: Samples.washington.placeId, name: "Washington", shortFormattedAddress: "Washington, DC, USA", lat: Samples.washington.lat, lng: Samples.washington.lng, locality: "Washington"),
    ] + Samples.venues.compactMap { venue in
        venue.location.map {
            PlaceData(placeId: $0.placeId, name: venue.displayName, shortFormattedAddress: "\(venue.displayName), Richmond, VA", lat: $0.lat, lng: $0.lng, locality: "Richmond")
        }
    }

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

/// Always reports Richmond, VA (`Location.rva`) unless given another result.
public struct MockLocationRepository: LocationRepository {
    public var result: Result<GeoCoordinate, LocationError>

    public init(result: Result<GeoCoordinate, LocationError> = .success(GeoCoordinate(lat: Location.rva.lat, lng: Location.rva.lng))) {
        self.result = result
    }

    public func currentCoordinate() async throws -> GeoCoordinate { try result.get() }
}

public actor MockPurchasesRepository: PurchasesRepository {
    private var entitlements: Set<Entitlement>
    private let broadcaster = EntitlementBroadcaster()

    public init(isPremium: Bool = false) {
        entitlements = isPremium ? [.premium] : []
    }

    public func products() async throws -> [PremiumProduct] {
        [
            PremiumProduct(id: TappedConfig.defaultPremiumProductIds[0], displayName: "tapped premium", description: "monthly", displayPrice: "$12.99", period: .month),
            PremiumProduct(id: TappedConfig.defaultPremiumProductIds[1], displayName: "tapped premium", description: "yearly", displayPrice: "$119.99", period: .year),
        ]
    }

    public func purchase(productId: String) async throws -> PurchaseOutcome {
        entitlements.insert(.premium)
        await broadcaster.publish(entitlements)
        return .purchased
    }

    public func restorePurchases() async throws {
        await broadcaster.publish(entitlements)
    }

    public func activeEntitlements() async -> Set<Entitlement> { entitlements }

    public nonisolated func entitlementUpdates() -> AsyncStream<Set<Entitlement>> {
        AsyncStream { continuation in
            let id = UUID()
            Task {
                await self.broadcaster.register(id, continuation)
                continuation.yield(await self.activeEntitlements())
            }
            continuation.onTermination = { _ in Task { await self.broadcaster.unregister(id) } }
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

/// Serves `MockSpotifyRepository.artists` by id.
public struct MockSpotifyRepository: SpotifyRepository {
    public static let artists = [
        SpotifyArtist(
            id: "4Z8W4fKeB5YxbusRsdQVPb",
            name: "Nova Waves",
            genres: ["electronic", "dance pop", "indietronica"],
            followers: 12_400,
            imageURL: URL(string: "https://picsum.photos/seed/nova-waves/640")
        ),
    ]

    public init() {}

    public func artist(id: String) async throws -> SpotifyArtist? {
        Self.artists.first { $0.id == id }
    }
}

/// Records every venue email thread instead of calling the Tapped API.
public actor MockVenueOutreachRepository: VenueOutreachRepository {
    public private(set) var threads: [VenueEmailThread] = []
    public var failure: VenueOutreachError?

    public init(failure: VenueOutreachError? = nil) {
        self.failure = failure
    }

    public func createVenueEmailThread(id: String, venueId: String, subject: String, textBody: String) async throws {
        if let failure { throw failure }
        threads.append(VenueEmailThread(id: id, venueId: venueId, subject: subject, textBody: textBody))
    }
}

/// Records venue notifications instead of calling the authenticated API.
public actor MockOpportunityNotificationRepository: OpportunityNotificationRepository {
    public struct VenueNotification: Sendable, Hashable {
        public var opportunityIds: [String]
        public var note: String

        public init(opportunityIds: [String], note: String) {
            self.opportunityIds = opportunityIds
            self.note = note
        }
    }

    public private(set) var venueNotifications: [VenueNotification] = []

    public init() {}

    public func notifyVenueOfInterestedOpportunities(opportunityIds: [String], note: String) async throws {
        venueNotifications.append(VenueNotification(opportunityIds: opportunityIds, note: note))
    }
}
