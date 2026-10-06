import Foundation
import SwiftUI
import TappedDomain

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
    public var notifications: any NotificationRepository
    public var chat: any ChatRepository
    public var storage: any StorageRepository
    public var venueOutreach: any VenueOutreachRepository
    public var opportunityNotifications: any OpportunityNotificationRepository
    /// Injected into the view tree as `\.imageProxy` for `RemoteImage`.
    public var imageProxy: ImageProxy
    public var location: any LocationRepository
    public var spotify: any SpotifyRepository

    public init(
        mode: Mode,
        auth: any AuthRepository,
        database: any DatabaseRepository,
        search: any SearchRepository,
        places: any PlacesRepository,
        purchases: any PurchasesRepository,
        analytics: any AnalyticsRepository,
        remoteConfig: any RemoteConfigRepository,
        notifications: any NotificationRepository = MockNotificationRepository(),
        chat: any ChatRepository = MockChatRepository(),
        storage: any StorageRepository = MockStorageRepository(),
        venueOutreach: any VenueOutreachRepository = MockVenueOutreachRepository(),
        opportunityNotifications: any OpportunityNotificationRepository = MockOpportunityNotificationRepository(),
        imageProxy: ImageProxy = .disabled,
        location: any LocationRepository = MockLocationRepository(),
        spotify: any SpotifyRepository = MockSpotifyRepository()
    ) {
        self.mode = mode
        self.auth = auth
        self.database = database
        self.search = search
        self.places = places
        self.purchases = purchases
        self.analytics = analytics
        self.remoteConfig = remoteConfig
        self.notifications = notifications
        self.chat = chat
        self.storage = storage
        self.venueOutreach = venueOutreach
        self.opportunityNotifications = opportunityNotifications
        self.imageProxy = imageProxy
        self.location = location
        self.spotify = spotify
    }

    /// Requires `FirebaseBootstrap.configure()` to have run before any repository is used.
    public static func live(config: TappedConfig = .fromBundle()) -> Dependencies {
        let database = FirestoreDatabaseRepository()
        return Dependencies(
            mode: .live,
            auth: FirebaseAuthRepository(),
            database: database,
            search: TypesenseSearchRepository(config: config, database: database),
            places: TappedAPIPlacesRepository(baseURL: config.tappedAPIURL),
            purchases: StoreKitPurchasesRepository(productIds: config.premiumProductIds),
            analytics: PostHogAnalytics(),
            remoteConfig: FirebaseRemoteConfigRepository(),
            notifications: FirebaseNotificationRepository(),
            chat: StreamChatRepository(
                apiKey: config.streamAPIKey,
                tokenProvider: TappedAPIStreamTokenRepository(baseURL: config.tappedAPIURL).fetch
            ),
            storage: FirebaseStorageRepository(),
            venueOutreach: TappedAPIVenueOutreachRepository(baseURL: config.tappedAPIURL),
            opportunityNotifications: TappedAPIOpportunityNotificationRepository(baseURL: config.tappedAPIURL),
            imageProxy: ImageProxy(baseURL: config.imageProxyURL),
            location: CoreLocationRepository(),
            spotify: TappedAPISpotifyRepository(baseURL: config.tappedAPIURL)
        )
    }

    public static func mock(
        signedIn: Bool = false,
        isPremium: Bool = false,
        claims: [CustomClaim] = [],
        downForMaintenance: Bool = false,
        onboarding: Bool = false,
        emailVerified: Bool = true,
        minimumAppVersion: String = "",
        latestAppVersion: String = "",
        premiumWaitlist: Bool = false,
        storeKitPurchases: Bool = false,
        notifications: any NotificationRepository = MockNotificationRepository(),
        storage: any StorageRepository = MockStorageRepository()
    ) -> Dependencies {
        var newUser = MockAuthRepository.newUser
        newUser.isEmailVerified = emailVerified
        let authUser: AuthUser? = onboarding ? newUser : (signedIn ? MockAuthRepository.sampleUser : nil)
        return Dependencies(
            mode: .mock,
            auth: MockAuthRepository(signedInAs: authUser, claims: claims),
            database: MockDatabaseRepository(),
            search: MockSearchRepository(),
            places: MockPlacesRepository(),
            purchases: storeKitPurchases
                ? StoreKitPurchasesRepository(productIds: TappedConfig.defaultPremiumProductIds)
                : MockPurchasesRepository(isPremium: isPremium),
            analytics: MockAnalytics(),
            remoteConfig: MockRemoteConfigRepository(
                downForMaintenance: downForMaintenance,
                minimumAppVersion: minimumAppVersion,
                latestAppVersion: latestAppVersion,
                premiumWaitlistEnabled: premiumWaitlist
            ),
            notifications: notifications,
            chat: MockChatRepository(),
            storage: storage,
            venueOutreach: MockVenueOutreachRepository(),
            opportunityNotifications: MockOpportunityNotificationRepository()
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
    /// `TAPPED_MOCK_SIGNED_IN=1` starts signed in, `TAPPED_MOCK_PREMIUM=1` grants premium,
    /// `TAPPED_MOCK_ONBOARDING=1` starts as a new account without a user doc (`TAPPED_MOCK_UNVERIFIED=1` → confirm email),
    /// `TAPPED_MOCK_MAINTENANCE=1`, `TAPPED_MOCK_MIN_VERSION=<v>`, `TAPPED_MOCK_LATEST_VERSION=<v>`, `TAPPED_MOCK_WAITLIST=1`
    /// drive the Remote Config gates. `TAPPED_MOCK_ADMIN=1` grants the `admin` claim, `TAPPED_MOCK_STOREKIT=1` uses real StoreKit 2
    /// (pair with the scheme's `Tapped.storekit` configuration).
    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> Dependencies {
        switch resolveMode(environment: environment) {
        case .live:
            return .live()
        case .mock:
            return .mock(
                signedIn: environment["TAPPED_MOCK_SIGNED_IN"] == "1",
                isPremium: environment["TAPPED_MOCK_PREMIUM"] == "1",
                claims: environment["TAPPED_MOCK_ADMIN"] == "1" ? [.admin] : [],
                downForMaintenance: environment["TAPPED_MOCK_MAINTENANCE"] == "1",
                onboarding: environment["TAPPED_MOCK_ONBOARDING"] == "1" || environment["TAPPED_MOCK_UNVERIFIED"] == "1",
                emailVerified: environment["TAPPED_MOCK_UNVERIFIED"] != "1",
                minimumAppVersion: environment["TAPPED_MOCK_MIN_VERSION"] ?? "",
                latestAppVersion: environment["TAPPED_MOCK_LATEST_VERSION"] ?? "",
                premiumWaitlist: environment["TAPPED_MOCK_WAITLIST"] == "1",
                storeKitPurchases: environment["TAPPED_MOCK_STOREKIT"] == "1"
            )
        }
    }
}

public extension EnvironmentValues {
    @Entry var dependencies: Dependencies = .mock()
}
