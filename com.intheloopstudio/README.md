# Tapped for iOS (native SwiftUI)

Native rewrite of the Flutter app in `../com.intheloopstudio.flutter/`. The Flutter app is the **read-only spec**:
never edit it from this project.

- Swift 6, `SWIFT_STRICT_CONCURRENCY=complete`, SwiftUI only, iOS 26 minimum
- SPM only (no CocoaPods), every dependency pinned with `exact:` and `Package.resolved` committed
- Bundle ID `com.intheloopstudio` (same as Flutter, so it ships as an update to the existing app)

## Setup

```bash
brew install xcodegen             # 2.46.0 used to generate the committed project
cd com.intheloopstudio
xcodegen generate                 # only needed after editing project.yml (the .xcodeproj is committed)
open Tapped.xcodeproj
```

### Firebase config

`Tapped/Resources/GoogleService-Info.plist` contains the production configuration for the same Firebase project
(`in-the-loop-306520`) and bundle ID as the Flutter app. It is committed so local and Xcode Cloud release builds use
live Firebase. Regenerate it from Firebase console → Project settings → iOS app `com.intheloopstudio` if the Firebase
configuration changes.

Other config lives in `Info.plist` and is read by `TappedConfig` (`TappedData/Services/TappedConfig.swift`):

| Key | Value |
| --- | --- |
| `TappedTypesenseHost` / `Port` / `Protocol` / `SearchAPIKey` | `search.tapped.ai`, search-only key (same public key the Flutter app ships) |
| `TappedPostHogAPIKey` / `TappedPostHogHost` | PostHog project key / `https://us.i.posthog.com` |
| `GIDClientID` + reversed-client-ID URL scheme | Google Sign-In (same OAuth client as Flutter) |
| `TappedPremiumProductIds` | optional override for StoreKit product IDs |
| `TappedAPIURL` | optional; Tapped API base URL used by authenticated app requests, including venue outreach and Stream tokens (default `https://api.tapped.ai`) |
| `TappedStreamAPIKey` | optional; Stream Chat **public** app key (default is the key the Flutter app ships). The user token comes from the authenticated Tapped API, never from the app bundle |

Remote Config keys (fetched by `FirebaseRemoteConfigRepository`; create the `ios_*` / waitlist keys in the Firebase console,
Flutter has no equivalents):

| Key | Type / default | Effect |
| --- | --- | --- |
| `down_for_maintenance` | bool / `false` | `MaintenanceView` gate |
| `booking_fee` | number | fee shown on booking forms |
| `ios_minimum_app_version` | string / `""` | semver; installed version below it → blocking `UpdateRequiredView` (replaces Flutter's `upgrader`). Empty/unparseable = off |
| `ios_latest_app_version` | string / `""` | semver; installed version below it → dismissible "update available" alert (update now / later / ignore this version) |
| `premium_waitlist_enabled` | bool / `false` | `Route.paywall` shows the premium waitlist instead of the StoreKit paywall |

## Build / test / run

```bash
# build + test: app tests, TappedDomain, TappedUI
xcodebuild build test -project Tapped.xcodeproj -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# TappedData tests run from the package (see "Testing" for why)
(cd Packages/TappedData && xcodebuild test -scheme TappedData \
  -destination 'platform=iOS Simulator,name=iPhone 17')

# package-only fast loop (TappedDomain has no iOS-only deps)
(cd Packages/TappedDomain && swift test)
```

Run from Xcode with the **`Tapped Mock`** scheme (sets `TAPPED_MOCK=1`), or from the command line:

```bash
xcrun simctl install booted <DerivedData>/Build/Products/Debug-iphonesimulator/Tapped.app
SIMCTL_CHILD_TAPPED_MOCK=1 SIMCTL_CHILD_TAPPED_MOCK_SIGNED_IN=1 xcrun simctl launch booted com.intheloopstudio
```

## Mock mode

`Dependencies.resolve()` picks `.mock` when any of these hold: env `TAPPED_MOCK=1`, the `TAPPED_MOCK` Swift
compilation condition, SwiftUI previews, or a placeholder/missing `GoogleService-Info.plist`. Mocks are actors in
`TappedData/Mocks` backed by `TappedDomain.Samples` (Richmond, VA venues, performers, gigs).

Extra launch env vars (mock mode only), used for screenshots and UI tests:

| Var | Values | Effect |
| --- | --- | --- |
| `TAPPED_MOCK_SIGNED_IN` | `1` | start signed in as `Samples.performer` |
| `TAPPED_MOCK_PREMIUM` | `1` | premium entitlement active |
| `TAPPED_MOCK_SCREEN` | `splash` \| `login` \| `signup` \| `forgot` | pin the signed-out screen |
| `TAPPED_MOCK_DETENT` | `collapsed` \| `medium` \| `large` | initial Discover sheet detent |
| `TAPPED_MOCK_TAB` | `gigs` \| `bookings` \| `messages` \| `profile` \| `search` | initial tab in the map sheet (non-Gigs tabs open at `large`) |
| `TAPPED_MOCK_ROUTE` | see below | push a screen (or path) on top of Discover once signed in (`Route.mockLaunchPath`) |
| `TAPPED_MOCK_ROUTE_DETAIL` | screen-specific (e.g. a search query) | extra state for the launched search/opportunity screen |
| `TAPPED_MOCK_ONBOARDING` | `1` | start as a new account with no `users/{uid}` doc (→ onboarding) |
| `TAPPED_MOCK_UNVERIFIED` | `1` | new unverified email/password account (→ confirm email) |
| `TAPPED_MOCK_ONBOARDING_STEP` | `name` \| `genres` \| `location` | open onboarding on a step with sample answers |
| `TAPPED_MOCK_MAINTENANCE` | `1` | Remote Config `down_for_maintenance` |
| `TAPPED_MOCK_MIN_VERSION` / `TAPPED_MOCK_LATEST_VERSION` | e.g. `99.0.0` | force the update-required gate / update-available alert |
| `TAPPED_MOCK_WAITLIST` | `1` | Remote Config `premium_waitlist_enabled` (`Route.paywall` → waitlist) |
| `TAPPED_MOCK_SHEET` | `reauth` | present the re-authentication sheet |
| `TAPPED_MOCK_LINK` | a URL | deliver a deep link at launch (cold start) |
| `TAPPED_MOCK_GIG_NIGHT` | `upcoming` \| `onstage` \| `review` | add a confirmed booking tonight and start the Gig Night Live Activity in that phase |
| `TAPPED_MOCK_PUSH_AUTH` | `1` | request notification permission at launch so action buttons can be tried with `simctl push` |
| `TAPPED_MOCK_ADMIN` | `1` | grant the `admin` custom claim (admin form) |
| `TAPPED_MOCK_STOREKIT` | `1` | real StoreKit 2 purchases against `StoreKit/Tapped.storekit` (set in the `Tapped Mock` scheme) |

`TAPPED_MOCK_ROUTE` names:

- profile: `profile`, `profile:<userId>`, `settings`, `activities`, `tasks`, `shareProfile`
- bookings: `bookings`, `booking`, `booking-pending`, `booking-sent`, `booking-past`, `booking-confirmation`,
  `create-booking`, `add-past-booking`, `request-to-perform`, `request-sent`, `add-collaborators`, `history`,
  `services`, `services-book`, `service`, `service-book`, `create-service`, `edit-service`
- search / opportunities / reviews: `search`, `advanced-search`, `location-form`, `gig-search`, `opportunity`,
  `opportunities`, `opportunity-feed`, `interested-users`, `reviews`, `reviews-venue`
- premium / messaging / admin: `paywall`, `messages`, `channel`, `admin`, `videocall`

Mock sign-in: any email + password works, except the password `wrong` (which returns an auth error).

## Architecture

```
com.intheloopstudio/
├── project.yml                  xcodegen spec (source of truth for Tapped.xcodeproj)
├── Tapped/                      app target
│   ├── App/                     TappedApp, AppDelegate, AppSession (auth gate), ContentView, LaunchOptions
│   ├── Features/<Feature>/
│   │   ├── Views/               screens (SwiftUI)
│   │   ├── ViewModels/          @Observable @MainActor view models
│   │   └── Components/          feature-private subviews
│   └── Resources/               Info.plist, entitlements, assets, GoogleService-Info.plist
├── TappedTests/                 Swift Testing: view models, session, router
├── Packages/
│   ├── TappedDomain/            Codable/Sendable models (Firestore field names), Samples; no deps
│   ├── TappedData/              repository protocols + Firebase/Typesense/Places/StoreKit/PostHog impls + mocks + Dependencies
│   └── TappedUI/                tokens, Liquid Glass components, MapsStyleSheet, RiveView; depends on TappedDomain + Rive
└── ci_scripts/ci_post_clone.sh  Xcode Cloud
```

Dependency direction: `Tapped → TappedUI, TappedData → TappedDomain`. `TappedUI` never imports `TappedData`;
`TappedDomain` imports nothing but Foundation.

### Flow

`TappedApp` resolves `Dependencies` once and injects it with `.environment(\.dependencies, …)` alongside `AppSession`
and `Router`. `AppSession.run()` (the port of `AuthenticationBloc` + `DownForMaintenanceBloc`) drives
`ContentView`: `splash → maintenance | updateRequired | signedOut (AuthFlowView) | confirmEmail | onboarding
(OnboardingView) | signedIn (ShellView)`. Entering `signedIn` publishes `latestAppVersion`, requests push permission
and saves the FCM token to `device_tokens/{uid}/tokens/{token}`.

Links: `TappedApp.onOpenURL` (universal links on the associated domains + the `com.intheloopstudio://` scheme) and
notification taps (`AppDelegate` → `NotificationPayload`, which reads Flutter's `url` key) feed `InboundLinks`, which
buffers a `DeepLink` until `ShellView` is on screen; `DeepLinkResolver` turns it into a `Route`. So cold-start
links survive splash/auth/onboarding.

Remote Config: `down_for_maintenance`, `booking_fee`, `ios_minimum_app_version` (hard gate, replaces `upgrader`),
`ios_latest_app_version` (dismissible alert: update now / later / ignore), `premium_waitlist_enabled`.

Destructive actions: wrap them in `.reauthenticationSheet(isPresented:reason:onSuccess:)`; it offers the account's
linked providers (password / apple / google).
`ShellView` is a `NavigationStack(path: $router.path)` whose root is `DiscoverView`; profile and messages are pushed
from Discover's top chrome, like Flutter.

### Discover

Port of `lib/ui/discover/**`: `MKMapView` (via `UIViewRepresentable`, for built-in `clusteringIdentifier`
clustering), glass top chrome (avatar · search capsule · messages, venues/gigs picker, "finish setting up" banner,
"search this area"), floating controls (filters, locate, debug zoom) that fade from `.medium` to `.large`, and
`MapsStyleSheet` with results header, quick actions, results, genre chips, top performers, featured gigs.
`DiscoverViewModel` mirrors `DiscoverCubit` (bounding-box Typesense search, premium-gated filters, venue fit sort).

## Conventions

- **Branches** `ios/<topic>`; **PR titles** `feat(ios): …` / `fix(ios): …`.
- **Feature folder** = `Views/`, `ViewModels/`, `Components/`. One screen = one `XxxView` + (if stateful) `XxxViewModel`.
- **View models** are `@Observable @MainActor final class`, take `Dependencies` (or specific repos) in `init`,
  expose `async` intents, and are unit-tested with mocks. No Combine.
- **Repositories** are protocols in `TappedData`. Views and view models only see protocols and `TappedDomain`
  types; `import Firebase…` is allowed only inside `Packages/TappedData/Sources/TappedData/Firebase` and `Services`.
- **Concurrency**: `async/await` everywhere; Firestore listeners are `AsyncThrowingStream`s (`…Observer` methods);
  domain types are `Sendable` structs; mocks are actors.
- **Copy is lowercase** ("search tapped", "finish setting up", "get booked."), matching the brand and Flutter app.
  Route titles, errors, buttons, empty states, all of it.
- **Design**: Liquid Glass for floating chrome only (nav, search capsule, map controls, bottom bars, sheets) via
  `tappedGlass(_:in:interactive:)`; forms/settings use native `Form`/inset-grouped lists; system font + SF Symbols;
  accent (`TappedColors.accent`, `#0086CC`) as tint/outline, not fills. Use `TappedSpacing`/`TappedRadius`/
  `GlassRadius`/`GlassMetrics`/`GlassMotion` tokens instead of literals.
- **No third-party UI libraries.** Allowed SDKs: Firebase (Auth, Firestore, Functions, Storage, Remote Config,
  Crashlytics, Messaging), GoogleSignIn, PostHog, Rive, Stream Chat (messaging session). Not used: Firebase
  Analytics, Stripe, RevenueCat, Mapbox, Lottie, Google Maps SDK.
- **Pinning**: `.package(url:…, exact: "x.y.z")` only. After changing a dependency, resolve in Xcode (or
  `xcodebuild -resolvePackageDependencies`) and commit
  `Tapped.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. CI resolves with
  `-disableAutomaticPackageResolution`, so an out-of-date lockfile fails the build.

### Adding a feature

1. Create `Tapped/Features/<Feature>/{Views,ViewModels,Components}`.
2. If it's a destination, it already has a `Route` case (mirrors `tapped_route.dart`). Resolve it in
   `Features/Navigation/Views/RouteDestination.swift` (or the feature's `…RouteDestination`), and add a
   `TAPPED_MOCK_ROUTE` name in `Route+MockLaunch.swift`.
3. Build the view model against `Dependencies`; add `#Preview`s using `Dependencies.mock()` and `Samples`.
4. Add Swift Testing tests in `TappedTests/`.
5. `xcodegen generate` is only needed if you add a new target or edit `project.yml` (sources are folder-globbed,
   but new files still need the project regenerated to show up in Xcode — run it; it's idempotent).

Navigate with `@Environment(Router.self) var router; router.push(.settings)`. Never construct destinations inline
with `NavigationLink(destination:)`.

### Adding a repository method

1. Add it to the protocol (e.g. `DatabaseRepository`), keeping the Dart method name and arguments.
2. Implement it in `FirestoreDatabaseRepository` (or the relevant live impl).
3. Implement it in the mock (`MockDatabaseRepository`) against `Samples`.
4. Add a `TappedDataTests` test for the mock (and a decoding fixture in `TappedDomainTests` if new JSON).

### Dependency injection

`Dependencies` is a `Sendable` struct of protocol existentials (`auth`, `database`, `search`, `places`,
`purchases`, `analytics`, `remoteConfig`, `notifications`, `storage`, `venueOutreach`, `chat`, `functions`). Read with `@Environment(\.dependencies)`; pass into view models' inits.
Tests and previews use `Dependencies.mock(signedIn:isPremium:claims:downForMaintenance:)`; override a single repo
by constructing `Dependencies(...)` with your own mock.

### Previews

Every `TappedUI` component and every feature view has a `#Preview`. `TappedUI` previews use `PreviewBackdrop` (a
map-like gradient) so glass is visible. `ComponentGallery` shows everything at once. Previews always use mocks.

### Testing

- Swift Testing (`import Testing`, `@Test`, `#expect`) everywhere.
- `TappedDomainTests`: Firestore/Typesense JSON fixtures → models (timestamps, defaults, scalar→array coercion).
- `TappedDataTests`: mocks and Typesense request building. Run from `Packages/TappedData`: when the app and a
  package test bundle both link Firebase in one build, Xcode turns `FirebaseFirestore` into a dynamic framework
  and linking fails (unresolved abseil symbols), so it isn't part of the `Tapped` scheme's test action.
- `TappedUITests`: `ImageRenderer` smoke renders of every component in light/dark + sheet math.
- `TappedTests`: view models (`DiscoverViewModel`, auth), `AppSession`, `Router`, `Route`, `LaunchOptions`.

## Features

Every `Route` case resolves to a real screen (`RouteDestination` → `BookingsRouteDestination` /
`SearchOpportunitiesDestination`). `Route.owner` records which rewrite session built each destination.

| Area | Screens / behaviour | Routes | Built in |
| --- | --- | --- | --- |
| Shell, Discover, auth | Map + clustering, glass chrome, three-detent `MapsStyleSheet` (quick actions/results fade in above the collapsed detent), filters, all results; splash, login, sign up, forgot password, confirm email | `discovery`, `login`, `signUp`, `forgotPassword` | #18 |
| Profile | Profile (hero, stats, socials, reviews, services, bookings; **message** via `MessageUserButton` → `ChatRepository.createDirectConversation` → `streamChannel`), settings / edit profile (delete account behind `.reauthenticationSheet`), share profile (QR), tasks, activity (unread badge on the Discover avatar), image viewer | `profile`, `settings`, `shareProfile`, `tasks`, `activities`, `image` | #22 |
| Bookings | Bookings list (upcoming/past, sent/received), booking detail + accept/decline/cancel, create booking, confirmation, add past booking, booking history map, request to perform (+ add collaborators) and confirmation, services list / detail / create-edit | `bookings`, `booking`, `createBooking`, `bookingConfirmation`, `addPastBooking`, `bookingHistory`, `requestToPerform`, `requestToPerformConfirmation`, `addCollaborators`, `serviceSelection`, `service`, `createService` | #20 |
| Search & opportunities | Search (performers/venues, recents), advanced search, location form, gig search (premium, venue fit), opportunity detail + apply, opportunities list, feed, interested users, reviews (new reviews carry the most recent confirmed booking id between the two users) | `search`, `advancedSearch`, `locationForm`, `gigSearch`, `opportunity`, `opportunities`, `opportunityFeed`, `interestedUsers`, `reviews` | #23 |
| Onboarding & platform | Onboarding steps, email verification, universal links + `com.intheloopstudio://` scheme + notification taps (`InboundLinks` → `DeepLinkResolver`), FCM token, Remote Config gates (maintenance, update required/available, premium waitlist), `.reauthenticationSheet` | `onboarding`, `AppSession` phases | #21 |
| Premium, messaging, admin | StoreKit 2 paywall (`PaywallGate`, `Tapped.storekit`), Stream Chat conversation list + channel (native SwiftUI over `ChatRepository`), video call (coming-soon screen, as in Flutter), admin opportunity form (admin claim) | `paywall`, `messagingChannelList`, `streamChannel`, `videoCall`, `admin` | #19 |

`Route.discovery` pops to the root (Discover is the shell root).

## What's stubbed

- Video call is a "coming soon" screen (Flutter's `VideoCallView` is empty too).
- StoreKit uses the existing App Store Connect `Tapped Premium` subscription products: `prod_2499_1m` ($12.99/month)
  and `prod_11999_1y` ($119.99/year). `StoreKit/Tapped.storekit` mirrors them for local testing.
- Push: no topic subscriptions (Flutter has none either).
- Live Firebase / Stream / Storage / APNs paths compile and are unit-tested against mocks only; this repo has no real
  `GoogleService-Info.plist`.
