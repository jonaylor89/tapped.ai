# Tapped for iOS (native SwiftUI)

Native rewrite of the Flutter app in `../com.intheloopstudio/`. The Flutter app is the **read-only spec**:
never edit it from this project.

- Swift 6, `SWIFT_STRICT_CONCURRENCY=complete`, SwiftUI only, iOS 26 minimum
- SPM only (no CocoaPods), every dependency pinned with `exact:` and `Package.resolved` committed
- Bundle ID `com.intheloopstudio` (same as Flutter, so it ships as an update to the existing app)

## Setup

```bash
brew install xcodegen             # 2.46.0 used to generate the committed project
cd com.intheloopstudio.ios
xcodegen generate                 # only needed after editing project.yml (the .xcodeproj is committed)
open Tapped.xcodeproj
```

### Firebase config

`Tapped/Resources/GoogleService-Info.plist` is a **placeholder** (`API_KEY = PLACEHOLDER`). With the placeholder the
app automatically runs in mock mode. For live Firebase, copy the real file from the Flutter app (same Firebase
project, `in-the-loop-306520`, same bundle ID):

```bash
cp ../com.intheloopstudio/ios/Runner/GoogleService-Info.plist Tapped/Resources/GoogleService-Info.plist
```

Or download it from Firebase console → Project settings → iOS app `com.intheloopstudio`. Don't commit the real file.

Other config lives in `Info.plist` and is read by `TappedConfig` (`TappedData/Services/TappedConfig.swift`):

| Key | Value |
| --- | --- |
| `TappedTypesenseHost` / `Port` / `Protocol` / `SearchAPIKey` | `search.tapped.ai`, search-only key (same public key the Flutter app ships) |
| `TappedGooglePlacesAPIKey` | `$(TAPPED_GOOGLE_PLACES_API_KEY)` build setting, empty by default — pass it via `xcodebuild … TAPPED_GOOGLE_PLACES_API_KEY=…` or an untracked `.xcconfig` |
| `TappedPostHogAPIKey` / `TappedPostHogHost` | PostHog project key / `https://us.i.posthog.com` |
| `GIDClientID` + reversed-client-ID URL scheme | Google Sign-In (same OAuth client as Flutter) |
| `TappedPremiumProductIds` | optional override for StoreKit product IDs |

## Build / test / run

```bash
# build + test: app tests, TappedDomain, TappedUI
xcodebuild build test -project Tapped.xcodeproj -scheme Tapped \
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

Mock sign-in: any email + password works, except the password `wrong` (which returns an auth error).

## Architecture

```
com.intheloopstudio.ios/
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
`ContentView`: `splash → maintenance | signedOut (AuthFlowView) | onboarding (placeholder) | signedIn (ShellView)`.
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
2. If it's a destination, it already has a `Route` case (mirrors `tapped_route.dart`). Replace the
   `PlaceholderScreen` for that case in `Features/Navigation/Views/RouteDestination.swift` with your view.
3. Build the view model against `Dependencies`; add `#Preview`s using `Dependencies.mock()` and `Samples`.
4. Add Swift Testing tests in `TappedTests/`.
5. `xcodegen generate` is only needed if you add a new target or edit `project.yml` (sources are folder-globbed,
   but new files still need the project regenerated to show up in Xcode — run it; it's idempotent).

Navigate with `@Environment(Router.self) var router; router.push(.settings)`. Never construct destinations inline
with `NavigationLink(destination:)`.

### Adding a repository method

1. Add it to the protocol (e.g. `DatabaseRepository`), keeping the Dart method name and arguments.
2. Implement it in `FirestoreDatabaseRepository` (or the relevant live impl) — replace the
   `throw NotImplemented("…")` stub.
3. Implement it in the mock (`MockDatabaseRepository`) against `Samples`.
4. Add a `TappedDataTests` test for the mock (and a decoding fixture in `TappedDomainTests` if new JSON).
5. Unimplemented methods must `throw NotImplemented(#function)` — never `fatalError`.

### Dependency injection

`Dependencies` is a `Sendable` struct of protocol existentials (`auth`, `database`, `search`, `places`,
`purchases`, `analytics`, `remoteConfig`). Read with `@Environment(\.dependencies)`; pass into view models' inits.
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

## What's stubbed

- `DatabaseRepository`: only the Discover + profile-header subset is live in `FirestoreDatabaseRepository`
  (users by id/username, username availability, featured performers/opportunities, booking/booker leaders,
  activities + observer, bookings by requester/requestee + observers, opportunities, reviews + observers, premium
  waitlist, contacted venues); everything else throws `NotImplemented`.
- Every `Route` except `login`/`signUp`/`forgotPassword`/`discovery` resolves to `PlaceholderScreen`.
- Onboarding (phase `.onboarding`) is a placeholder; unread message count is `0` until Stream Chat lands.
- StoreKit product IDs `com.intheloopstudio.premium.monthly|yearly` are placeholders (Flutter uses RevenueCat
  offerings; no StoreKit config exists in the repo).
- Push: APNs token is forwarded to FCM; topic subscription/deep-link routing is session 5.

## Screen ownership (follow-up sessions)

| Session | Scope | Routes |
| --- | --- | --- |
| 2 | Profile, Settings, Share profile, Tasks, Activity | `profile`, `settings`, `shareProfile`, `tasks`, `activities`, `image`, `addCollaborators` |
| 3 | Bookings, Request to perform, Services, Booking history map | `bookings`, `booking`, `createBooking`, `bookingConfirmation`, `requestToPerform`, `requestToPerformConfirmation`, `addPastBooking`, `bookingHistory`, `serviceSelection`, `createService`, `service` |
| 4 | Search, Advanced search, Gig search, Opportunities, Feed, Reviews | `search`, `advancedSearch`, `gigSearch`, `opportunity`, `interestedUsers`, `reviews`, `locationForm` |
| 5 | Onboarding, Universal links, Push, Remote Config gates | `onboarding`, `AppSession` phases, `TappedApp.onOpenURL`, `AppDelegate` push |
| 6 | Paywall (StoreKit 2), Messaging (Stream Chat), Admin | `paywall`, `messagingChannelList`, `streamChannel`, `videoCall`, `admin` |

`Route.owner` encodes the same table so `PlaceholderScreen` shows who owns each destination.
Shared code (`TappedUI`, `TappedData` protocols, `Route`) is changed by small, separate PRs so sessions don't conflict.
