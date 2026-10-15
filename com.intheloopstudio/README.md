# Tapped for iOS (native SwiftUI)

The production native iOS app. Its source, tests and this README define the supported behaviour;
the legacy mobile app is retired and Android is no longer supported. Backend Firebase hooks/config
live independently in [`../services/firebase-functions/`](../services/firebase-functions/README.md).
Application data/search use Rust/Postgres; Firebase remains for identity/email verification and the SDK services listed below.

- Swift 6, `SWIFT_STRICT_CONCURRENCY=complete`, SwiftUI only, iOS 26 minimum
- SPM only (no CocoaPods), every dependency pinned with `exact:` and `Package.resolved` committed
- Bundle ID `com.intheloopstudio` (ships as an update to the existing App Store app)

## Setup

```bash
brew install xcodegen             # 2.46.0 used to generate the committed project
cd com.intheloopstudio
xcodegen generate                 # only needed after editing project.yml (the .xcodeproj is committed)
open Tapped.xcodeproj
```

### Firebase config

`Tapped/Resources/GoogleService-Info.plist` contains the production configuration for the same Firebase project
(`in-the-loop-306520`) and existing bundle ID. It is committed so local and Xcode Cloud release builds use
live Firebase. Regenerate it from Firebase console → Project settings → iOS app `com.intheloopstudio` if the Firebase
configuration changes.

Other config lives in `Info.plist` and is read by `TappedConfig` (`TappedData/Services/TappedConfig.swift`):

| Key | Value |
| --- | --- |
| `TappedPostHogAPIKey` / `TappedPostHogHost` | PostHog project key / `https://us.i.posthog.com` |
| `GIDClientID` + reversed-client-ID URL scheme | Google Sign-In using the existing OAuth client |
| `TappedPremiumProductIds` | optional override for StoreKit product IDs |
| `TappedAPIURL` | optional; Tapped API base URL used by authenticated app requests, including venue outreach and Stream tokens (default `https://api.tapped.ai`) |
| `TappedStreamAPIKey` | optional; Stream Chat **public** app key. The user token comes from the authenticated Tapped API, never from the app bundle |

Launch gates come from `GET /app/v1/public/app-config` (`TappedAPIRemoteConfigRepository`; cached per API host for the
next launch, 3 s fetch timeout). Edit the single Postgres `app_config` row, e.g.
`UPDATE app_config SET down_for_maintenance = true;` — clients pick it up within ~30 s (`Cache-Control: max-age=30`).

| Column | Type / default | Effect |
| --- | --- | --- |
| `down_for_maintenance` | bool / `false` | `MaintenanceView` gate |
| `booking_fee` | number | fee shown on booking forms |
| `ios_minimum_app_version` | string / `""` | semver; installed version below it → blocking `UpdateRequiredView`. Empty/unparseable = off |
| `ios_latest_app_version` | string / `""` | semver; installed version below it → dismissible "update available" alert (update now / later / ignore this version) |
| `premium_waitlist_enabled` | bool / `false` | legacy configuration; never replaces the required premium activation step |

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
SIMCTL_CHILD_TAPPED_MOCK=1 SIMCTL_CHILD_TAPPED_MOCK_SIGNED_IN=1 SIMCTL_CHILD_TAPPED_MOCK_PREMIUM=1 xcrun simctl launch booted com.intheloopstudio
```

## Mock mode

`Dependencies.resolve()` picks `.mock` when any of these hold: env `TAPPED_MOCK=1`, the `TAPPED_MOCK` Swift
compilation condition, SwiftUI previews, or a placeholder/missing `GoogleService-Info.plist`. Mocks are actors in
`TappedData/Mocks` backed by `TappedDomain.Samples` (Richmond, VA venues, performers, gigs).

Extra launch env vars (mock mode only), used for screenshots and UI tests:

| Var | Values | Effect |
| --- | --- | --- |
| `TAPPED_MOCK_SIGNED_IN` | `1` | start signed in as `Samples.performer` |
| `TAPPED_MOCK_PREMIUM` | `1` | premium entitlement active; required to reach the shell in signed-in mocks |
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
| `TAPPED_MOCK_WAITLIST` | `1` | legacy Remote Config flag; cannot replace premium activation |
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
│   ├── App/                     TappedApp, AppDelegate, AppSession (auth/profile gate), ContentView, LaunchOptions
│   ├── Features/<Feature>/
│   │   ├── Views/               screens (SwiftUI)
│   │   ├── ViewModels/          @Observable @MainActor view models
│   │   └── Components/          feature-private subviews
│   └── Resources/               Info.plist, entitlements, assets, GoogleService-Info.plist
├── TappedTests/                 Swift Testing: view models, session, router
├── Packages/
│   ├── TappedDomain/            Codable/Sendable models, Samples; no deps
│   ├── TappedData/              repository protocols + Rust API/Firebase Auth/Places/StoreKit/PostHog impls + mocks + Dependencies
│   └── TappedUI/                tokens, Liquid Glass components, MapsStyleSheet, RiveView; depends on TappedDomain + Rive
```

Repository-root `../ci_scripts/ci_post_clone.sh` handles Xcode Cloud.
Configure Xcode Cloud with `com.intheloopstudio/Tapped.xcodeproj` and scheme `Runner`;
it resolves the committed SPM lockfile without Flutter, CocoaPods or sibling source folders.

Dependency direction: `Tapped → TappedUI, TappedData → TappedDomain`. `TappedUI` never imports `TappedData`;
`TappedDomain` imports nothing but Foundation.

### Flow

`TappedApp` resolves `Dependencies` once and injects it with `.environment(\.dependencies, …)` alongside `AppSession`
and `Router`. `AppSession.run()` drives
`ContentView`: `splash → maintenance | updateRequired | signedOut (AuthFlowView) | confirmEmail | onboarding
(OnboardingView) | premiumRequired (final onboarding step) | signedIn (ShellView)`. Entering `signedIn` publishes `latestAppVersion`, requests push permission
and registers the raw APNs device token (with its `development`/`production` environment) through the authenticated Rust API;
the identity worker delivers straight to APNs. Current session profiles refresh centrally every 30 seconds; edits update the session immediately without discarding unsaved drafts.

Links: `TappedApp.onOpenURL` (universal links on the associated domains + the `com.intheloopstudio://` scheme) and
notification taps (`AppDelegate` → `NotificationPayload`, using the `url` payload key) feed `InboundLinks`, which
buffers a `DeepLink` until `ShellView` is on screen; `DeepLinkResolver` turns it into a `Route`. So cold-start
links survive splash/auth/onboarding.

Remote Config: `down_for_maintenance`, `booking_fee`, `ios_minimum_app_version` (hard gate, replaces `upgrader`),
`ios_latest_app_version` (dismissible alert: update now / later / ignore), `premium_waitlist_enabled`.

Destructive actions: wrap them in `.reauthenticationSheet(isPresented:reason:onSuccess:)`; it offers the account's
linked providers (password / apple / google).
`ShellView` is a `NavigationStack(path: $router.path)` whose root is `DiscoverView`; profile and messages are pushed
from Discover's top chrome.

### Premium-only onboarding

Profile setup asks for name → genres → location (steps 1–3 of 4). The first step discloses that a
subscription is required. Continuing or skipping location saves the profile through the Rust API, then
`AppSession` presents premium activation as step 4. Cancelling checkout, pending approval, an unavailable
storefront, or relaunching cannot discard the saved profile or unlock the app. Existing subscribers skip
activation; existing non-subscribers and expired/revoked subscriptions return to this same gate.

Only verified `PurchasesRepository` entitlements permit `signedIn`. Purchase callbacks alone never grant
access. Entitlements are rechecked on transaction updates, foreground, and the session's 30-second refresh.
Deep links remain buffered until the shell appears; background notification actions also require premium.
There is no waitlist substitution or free path through the gate. Legacy `Route.paywall` opens settings,
not another purchase screen; settings links to App Store subscription management.

The final step shows full localized monthly/yearly billing prices, auto-renewal terms, a price-bearing
purchase button, restore, legal/support links, subscription management, sign out and reauthenticated account
deletion. It does not promise a free trial, discounted price, or guaranteed bookings. Cancellation is silent;
pending approval, restore failures and loading failures offer explicit recovery.

Funnel events: `onboarding_profile_saved`, `premium_activation_viewed`, `premium_purchase_started`,
`premium_purchase_cancelled`, `premium_purchase_pending`, `premium_purchased`, `premium_restored`,
`premium_activation_completed`. Profile completion is not counted as paid activation.

Tests: `PremiumAccessTests` covers session boundaries and purchase/restore failures;
`PremiumOnboardingTests` covers the onboarding-to-activation-to-shell path, relaunch, restoring without a
subscription, existing subscribers, buffered deep links, and accessibility layout. Before release, verify
real App Store sandbox purchase, cancellation, Ask to Buy, cross-device restore, expiry/refund, and legal
destinations with the production products. Client gating does not replace server-side API authorization.

### Discover

`MKMapView` (via `UIViewRepresentable`, for built-in `clusteringIdentifier`
clustering), glass top chrome (avatar · search capsule · messages, venues/gigs picker, "finish setting up" banner,
"search this area"), floating controls (filters, locate, debug zoom) that fade from `.medium` to `.large`, and
`MapsStyleSheet` with results header, quick actions, results, genre chips, top performers, featured gigs.
`DiscoverViewModel` handles bounding-box API/Postgres search, filters and venue-fit sorting. All shell features are included in the subscription; there are no feature-level upsells or free-application quotas.

## Conventions

- **Branches** `ios/<topic>`; **PR titles** `feat(ios): …` / `fix(ios): …`.
- **Feature folder** = `Views/`, `ViewModels/`, `Components/`. One screen = one `XxxView` + (if stateful) `XxxViewModel`.
- **View models** are `@Observable @MainActor final class`, take `Dependencies` (or specific repos) in `init`,
  expose `async` intents, and are unit-tested with mocks. No Combine.
- **Repositories** are protocols in `TappedData`. Views and view models only see protocols and `TappedDomain`
  types; `import Firebase…` is allowed only inside `Packages/TappedData/Sources/TappedData/Firebase` and `Services`.
- **Concurrency**: `async/await` everywhere; database observers are cancellable, bounded `AsyncThrowingStream`s backed by 30-second API polling;
  domain types are `Sendable` structs; mocks are actors.
- **Copy is lowercase** ("search tapped", "finish setting up", "get booked."), matching the brand.
  Route titles, errors, buttons, empty states, all of it.
- **Design**: Liquid Glass for floating chrome only (nav, search capsule, map controls, bottom bars, sheets) via
  `tappedGlass(_:in:interactive:)`; forms/settings use native `Form`/inset-grouped lists; system font + SF Symbols;
  accent (`TappedColors.accent`, `#0086CC`) as tint/outline, not fills. Use `TappedSpacing`/`TappedRadius`/
  `GlassRadius`/`GlassMetrics`/`GlassMotion` tokens instead of literals.
- **SDKs**: Firebase (Auth only), GoogleSignIn, PostHog (analytics + error tracking: crash autocapture and
  `ErrorReporting.record(error:)` non-fatals), Rive,
  Stream Chat (messaging session). No Firestore/Functions serving SDK or Typesense; application data, functions and search use Rust API clients. Not used: Firebase Analytics, Remote Config, Crashlytics, Messaging (FCM), Stripe, RevenueCat, Mapbox, Lottie, Google Maps SDK.
- **Pinning**: `.package(url:…, exact: "x.y.z")` only. After changing a dependency, resolve in Xcode (or
  `xcodebuild -resolvePackageDependencies`) and commit
  `Tapped.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. CI resolves with
  `-disableAutomaticPackageResolution`, so an out-of-date lockfile fails the build.

### Adding a feature

1. Create `Tapped/Features/<Feature>/{Views,ViewModels,Components}`.
2. If it's a destination, add or reuse a `Route` case. Resolve it in
   `Features/Navigation/Views/RouteDestination.swift` (or the feature's `…RouteDestination`), and add a
   `TAPPED_MOCK_ROUTE` name in `Route+MockLaunch.swift`.
3. Build the view model against `Dependencies`; add `#Preview`s using `Dependencies.mock()` and `Samples`.
4. Add Swift Testing tests in `TappedTests/`.
5. `xcodegen generate` is only needed if you add a new target or edit `project.yml` (sources are folder-globbed,
   but new files still need the project regenerated to show up in Xcode — run it; it's idempotent).

Navigate with `@Environment(Router.self) var router; router.push(.settings)`. Never construct destinations inline
with `NavigationLink(destination:)`.

### Adding a repository method

1. Add it to the protocol (e.g. `DatabaseRepository`) using domain types.
2. Implement it in `TappedAPIDatabaseRepository` (or the relevant live implementation). Never add a Firestore fallback or dual writes.
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
- `TappedDomainTests`: current API and legacy-encoding JSON fixtures → models (timestamps, defaults, scalar→array coercion); no Firestore/Typesense serving dependency.
- `TappedDataTests`: mocks and API database/search request handling. Run separately from `Packages/TappedData`;
  it isn't part of the `Runner` scheme's test action.
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
| Search & opportunities | Search (performers/venues, recents), advanced search, location form, gig search (venue fit), opportunity detail + apply, opportunities list, feed, interested users, reviews (new reviews carry the most recent confirmed booking id between the two users) | `search`, `advancedSearch`, `locationForm`, `gigSearch`, `opportunity`, `opportunities`, `opportunityFeed`, `interestedUsers`, `reviews` | #23 |
| Onboarding & platform | Onboarding steps, email verification, universal links + `com.intheloopstudio://` scheme + notification taps (`InboundLinks` → `DeepLinkResolver`), APNs token, API app-config gates (maintenance, update required/available), `.reauthenticationSheet` | `onboarding`, `AppSession` phases | #21 |
| Premium, messaging, admin | StoreKit 2 final onboarding activation (`PaywallView`, `Tapped.storekit`), Stream Chat conversation list + channel (native SwiftUI over `ChatRepository`), video call (coming-soon screen), admin opportunity form (admin claim) | `paywall`, `messagingChannelList`, `streamChannel`, `videoCall`, `admin` | #19 |

`Route.discovery` pops to the root (Discover is the shell root).

## What's stubbed

- Video call remains a "coming soon" screen.
- StoreKit uses the existing App Store Connect `Tapped Premium` subscription products: `prod_2499_1m` ($12.99/month)
  and `prod_11999_1y` ($119.99/year). `StoreKit/Tapped.storekit` mirrors them for local testing. The activation UI always uses StoreKit's localized prices, not these reference amounts.
- Push: no topic subscriptions; token registration goes through Rust.
- Badges, curated leaders, premium waitlist, historical contact flags, blocking/reporting are explicitly disabled/unmigrated (contact support@tapped.ai). Applications are unmetered and feeds are computed.
- Public Firebase configuration is committed at `Tapped/Resources/GoogleService-Info.plist`; it is not a service-account credential. Unit tests use mocks; simulator tests and actual App Store distribution remain separate validation paths.
