# Migrating Cloud Functions → Rust API

## Overview
Move HTTP/callable Cloud Functions from `com.intheloopstudio/functions/` to the Rust API at `https://api.tapped.ai` (deployed on the Hetzner VPS).

## Firebase Auth in Rust
Use [`firebase-verifyid`](https://crates.io/crates/firebase-verifyid) for Axum middleware:
```toml
firebase-verifyid = "0.1.5"
```
- Auto-fetches & caches Google's public JWK keys
- Verifies Firebase ID tokens (RS256, checks `aud`/`iss`/`exp`)
- Extracts Firebase UID (`sub`) — same as `context.auth.uid` in Cloud Functions
- Project ID: `in-the-loop-306520`

Flutter side:
```dart
final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
// Send as: Authorization: Bearer $idToken
```

## Functions that CAN move to Rust API

### REST / HTTP (`onRequest`)
| Function | File | What it does |
|----------|------|-------------|
| `spotifyRedirect` | spotify.ts | Spotify OAuth redirect |

### Callable (`onCall`)
| Function | File | What it does |
|----------|------|-------------|
| `addActivity` | activities.ts | Create an activity |
| `createPaymentIntent` | payments.ts | Stripe payment intent |
| `createConnectedAccount` | payments.ts | Stripe connected account |
| `getAccountById` | payments.ts | Get Stripe account |
| `getPlaceById` | places.ts | Google Places lookup |
| `getPlaceIdByLatLng` | places.ts | Reverse geocode |
| `transformLocationPayloadForSearch` | search.ts | Transform location for indexing |
| `createAvatarInferenceJob` | ai_generators.ts | Create AI avatar job |
| `spotifyAuthorizeCodeGrant` | spotify.ts | Spotify auth code exchange |
| `spotifyRefreshToken` | spotify.ts | Refresh Spotify token |
| `getArtistBySpotifyId` | spotify.ts | Get Spotify artist |
| `getTopTracksByArtistId` | spotify.ts | Get Spotify top tracks |

### Webhooks (`onRequest`)
| Function | File | What it does |
|----------|------|-------------|
| `sendEmailOnSubscriptionPurchase` | webhooks.ts | RevenueCat subscription webhook |
| `sendEmailOnSubscriptionExpiration` | webhooks.ts | RevenueCat expiration webhook |
| `streamBeforeMessageWebhook` | webhooks.ts | Stream chat message hook |
| `inboundEmailWebhook` | webhooks.ts | Postmark inbound email |

### Scheduled (move to cron on Hetzner)
| Function | File | What it does |
|----------|------|-------------|
| `cancelBookingIfExpired` | bookings.ts | Cancel stale pending bookings (hourly) |

## Functions that MUST stay as Cloud Functions

### Firestore Triggers
| Function | File | Trigger |
|----------|------|---------|
| `sendToDevice` | activities.ts | `activities/{id}` onCreate |
| `notifyFoundersOnBookings` | bookings.ts | `bookings/{id}` onCreate |
| `incrementReviewCountOnBookerReview` | bookings.ts | `reviews/{id}/bookerReviews/{rid}` onCreate |
| `incrementReviewCountOnPerformerReview` | bookings.ts | `reviews/{id}/performerReviews/{rid}` onCreate |
| `sendWelcomeEmailOnUserCreated` | email_triggers.ts | `users/{id}` onCreate |
| `sendBookingRequestSentEmailOnBooking` | email_triggers.ts | `bookings/{id}` onCreate |
| `sendBookingRequestReceivedEmailOnBooking` | email_triggers.ts | `bookings/{id}` onCreate |
| `sendBookingNotificationsOnBookingConfirmed` | email_triggers.ts | `bookings/{id}` onUpdate |
| `sendEmailOnLabelApplication` | email_triggers.ts | label applications onCreate |
| `sendEmailOnPremiumWaitlist` | email_triggers.ts | premium waitlist onCreate |
| `copyOpportunityToFeedsOnCreate` | opportunities.ts | `opportunities/{id}` onWrite |
| `addInterestedUserOnApplyToOpportunity` | opportunities.ts | opportunity onUpdate |
| `copyOpportunitiesToFeedOnCreateUser` | opportunities.ts | `users/{id}` onCreate |
| `incrementServiceCountOnBooking` | services.ts | `bookings/{id}` onCreate |
| `createDefaultServicesOnUserCreated` | services.ts | `users/{id}` onCreate |
| `notifyFoundersOnUserOnboarded` | signups.ts | `users/{id}` onCreate |
| `notifyFoundersOnUserFeedbackSubmitted` | user_feedback.ts | feedback onCreate |
| `createBookingOnEventCrawled` | crawler.ts | `crawler/{link}` onCreate |
| `onDeleteAvatar` | ai_generators.ts | avatar doc onDelete |

### Auth Triggers
| Function | File | Trigger |
|----------|------|---------|
| `onUserDeleted` | index.ts | auth.user.onDelete |
| `createStreamUserOnUserCreated` | stream.ts | auth.user.onCreate |
| `updateStreamUserOnUserUpdate` | stream.ts | user doc onUpdate |
| `deleteStreamUser` | stream.ts | auth.user.onDelete |
| `giveUserCoverArtCreditsOnCreate` | ai_generators.ts | auth.user.onCreate |
| `createOpportunityFeedOnUserCreated` | opportunities.ts | auth.user.onCreate |
| `notifyFoundersOnSignUp` | signups.ts | auth.user.onCreate |
| `notifyFoundersOnUserDelete` | signups.ts | auth.user.onDelete |
| `notifyFoundersOnAppRemoved` | signups.ts | auth.user.onDelete |
| `addUserToMailchimpOnCreated` | mailchimp.ts | auth.user.onCreate |
