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
| `getUserById` | rest.ts | Get user by ID |
| `getUserByUsername` | rest.ts | Get user by username |
| `getOpportunityById` | rest.ts | Get opportunity by ID |
| `spotifyRedirect` | spotify.ts | Spotify OAuth redirect |
| `fetchPlaceById` | places.ts | Fetch Google Place by ID |
| `richmondEventsWebhook` | calendar.ts | Ingest Richmond events |

### Callable (`onCall`)
| Function | File | What it does |
|----------|------|-------------|
| `addActivity` | activities.ts | Create an activity |
| `createPaymentIntent` | payments.ts | Stripe payment intent |
| `createConnectedAccount` | payments.ts | Stripe connected account |
| `getAccountById` | payments.ts | Get Stripe account |
| `checkoutSessionToClientReferenceId` | payments.ts | Checkout session lookup |
| `getPlaceById` | places.ts | Google Places lookup |
| `getPlacePhotoUrlFromName` | places.ts | Google Places photo URL |
| `getPlaceIdByLatLng` | places.ts | Reverse geocode |
| `autocompletePlaces` | places.ts | Places autocomplete |
| `transformLocationPayloadForSearch` | search.ts | Transform location for indexing |
| `createAvatarInferenceJob` | ai_generators.ts | Create AI avatar job |
| `getAvatarInferenceJob` | ai_generators.ts | Get AI avatar job status |
| `deleteInferenceJob` | ai_generators.ts | Delete AI inference job |
| `trainModel` | ai_generators.ts | Train AI model |
| `createSingleMarketingPlan` | ai_generators.ts | Generate marketing plan |
| `generateEnhancedBio` | ai_generators.ts | AI-enhanced bio |
| `getChartmetricIdBySpotifyId` | chartmetric.ts | Chartmetric lookup |
| `spotifyAuthorizeCodeGrant` | spotify.ts | Spotify auth code exchange |
| `spotifyRefreshToken` | spotify.ts | Refresh Spotify token |
| `getArtistBySpotifyId` | spotify.ts | Get Spotify artist |
| `getTopTracksByArtistId` | spotify.ts | Get Spotify top tracks |
| `sendEmailOnVenueContacting` | email_triggers.ts | Send venue contact email |

### Webhooks (`onRequest`)
| Function | File | What it does |
|----------|------|-------------|
| `imageWebhook` | ai_generators.ts | LeapAI image callback |
| `trainWebhook` | ai_generators.ts | LeapAI training callback |
| `marketingPlanStripeWebhook` | ai_generators.ts | Marketing plan Stripe webhook |
| `coverArtStripeWebhook` | ai_generators.ts | Cover art Stripe webhook |
| `coverArtStripeTestWebhook` | ai_generators.ts | Cover art Stripe test webhook |
| `emailMarketingPlanStripeWebhook` | email_triggers.ts | Email marketing Stripe webhook |
| `sendEmailOnSubscriptionPurchase` | webhooks.ts | RevenueCat subscription webhook |
| `sendEmailOnSubscriptionExpiration` | webhooks.ts | RevenueCat expiration webhook |
| `streamBeforeMessageWebhook` | webhooks.ts | Stream chat message hook |
| `inboundEmailWebhook` | webhooks.ts | Postmark inbound email |

### Scheduled (move to cron on Hetzner)
| Function | File | What it does |
|----------|------|-------------|
| `cancelBookingIfExpired` | bookings.ts | Cancel stale pending bookings (hourly) |
| `sendSearchAppearances` | search.ts | Notify users of search appearances (every 3h) |

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
| `generateMarketingPlan` | ai_generators.ts | marketing form onCreate |
| `notifyFoundersOnMarketingForm` | ai_generators.ts | marketing form onCreate |
| `notifyFoundersOnGuestMarketingPlan` | ai_generators.ts | guest marketing onCreate |

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
