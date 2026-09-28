import Foundation
import SwiftUI

/// Every repository the app uses, injected through `@Environment(\.dependencies)`.
/// Views and view models only ever see these protocols — never Firebase types.
public struct Dependencies: Sendable {
    public enum Mode: String, Sendable {
        case live
        case mock
    }

    public var mode: Mode
    public var auth: any AuthRepository
    public var database: any DatabaseRepository
    public var search: any SearchRepository
    public var places: any PlacesRepository
    public var purchases: any PurchasesRepository
    public var analytics: any AnalyticsRepository
    public var remoteConfig: any RemoteConfigRepository
    public var venueOutreach: any VenueOutreachRepository

    public init(
        mode: Mode,
        auth: any AuthRepository,
        database: any DatabaseRepository,
        search: any SearchRepository,
        places: any PlacesRepository,
        purchases: any PurchasesRepository,
        analytics: any AnalyticsRepository,
        remoteConfig: any RemoteConfigRepository,
        venueOutreach: any VenueOutreachRepository = MockVenueOutreachRepository()
    ) {
        self.mode = mode
        self.auth = auth
        self.database = database
        self.search = search
        self.places = places
        self.purchases = purchases
        self.analytics = analytics
        self.remoteConfig = remoteConfig
        self.venueOutreach = venueOutreach
    }

    /// Requires `FirebaseBootstrap.configure()` to have run before any repository is used.
    public static func live(config: TappedConfig = .fromBundle()) -> Dependencies {
        let database = FirestoreDatabaseRepository()
        return Dependencies(
            mode: .live,
            auth: FirebaseAuthRepository(),
            database: database,
            search: TypesenseSearchRepository(config: config, database: database),
            places: GooglePlacesRepository(apiKey: config.googlePlacesAPIKey),
            purchases: StoreKitPurchasesRepository(productIds: config.premiumProductIds),
            analytics: PostHogAnalytics(),
            remoteConfig: FirebaseRemoteConfigRepository(),
            venueOutreach: TappedAPIVenueOutreachRepository(baseURL: config.tappedAPIURL)
        )
    }

    public static func mock(
        signedIn: Bool = false,
        isPremium: Bool = false,
        claims: [CustomClaim] = [],
        downForMaintenance: Bool = false
    ) -> Dependencies {
        Dependencies(
            mode: .mock,
            auth: MockAuthRepository(signedInAs: signedIn ? MockAuthRepository.sampleUser : nil, claims: claims),
            database: MockDatabaseRepository(),
            search: MockSearchRepository(),
            places: MockPlacesRepository(),
            purchases: MockPurchasesRepository(isPremium: isPremium),
            analytics: MockAnalytics(),
            remoteConfig: MockRemoteConfigRepository(downForMaintenance: downForMaintenance),
            venueOutreach: MockVenueOutreachRepository()
        )
    }

    /// Mock mode when `TAPPED_MOCK=1` (scheme env var), when built with `-D TAPPED_MOCK`,
    /// or when no real `GoogleService-Info.plist` is bundled.
    public static func resolveMode(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        hasFirebaseConfig: Bool = FirebaseBootstrap.hasConfiguration()
    ) -> Mode {
        #if TAPPED_MOCK
        return .mock
        #else
        if environment["TAPPED_MOCK"] == "1" { return .mock }
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return .mock }
        return hasFirebaseConfig ? .live : .mock
        #endif
    }

    /// Mock-mode launch arguments used by UI tests / screenshots:
    /// `TAPPED_MOCK_SIGNED_IN=1` starts signed in, `TAPPED_MOCK_PREMIUM=1` grants premium.
    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> Dependencies {
        switch resolveMode(environment: environment) {
        case .live:
            return .live()
        case .mock:
            return .mock(
                signedIn: environment["TAPPED_MOCK_SIGNED_IN"] == "1",
                isPremium: environment["TAPPED_MOCK_PREMIUM"] == "1"
            )
        }
    }
}

public extension EnvironmentValues {
    @Entry var dependencies: Dependencies = .mock()
}
