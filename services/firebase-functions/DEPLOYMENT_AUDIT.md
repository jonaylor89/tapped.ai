# Live Firebase deployment audit

Checked **2026-10-12T17:15:23.312468+00:00**, project `in-the-loop-306520`, all regions: **60 deployed functions**, including **27 Firebase-managed extension functions**.

This is a read-only inventory, not a deployment or retirement operation. `ACTIVE` is provider state, not proof of current traffic; `UNKNOWN` is not proof a function is disabled. Paused schedulers may still have an active backing function.

## Findings

- **Target is zero Firebase Functions, including extensions—not retaining Auth/compatibility handlers permanently.** See [the full retirement plan](../../platform/FIREBASE_FUNCTIONS_RETIREMENT.md). Founder booking/application/onboarding alerts are required business behavior, not obsolete triggers: Rust outbox replacements were deployed and verified through live API actions, then those three Functions were deleted (55 remain after subsequent Stream callback and approved Mailchimp retirement). The table below is the original inventory snapshot, not the current function count. Other notification/Auth effects must also be accounted for.
- Backend source and Firebase project/deployment configuration are independent of the retired mobile directory.
- The entrypoint explicitly exports only the 11 allowlisted Auth side effects and HTTP compatibility endpoints. Legacy Firestore modules are preserved for reference, **not exported or approved for deployment**. Previously deleted triggers (including `onUserDeleted`, default-service and review-counter writers) cannot be recreated by the supported deployment command.
- Both webhook compatibility handlers delegate to Rust; the Stream proxy forwards the original bytes/signature instead of accessing Firestore. These local changes have **not been deployed**.
- **8 custom functions are deployed but absent from the repository source**: `createConnectedAccount`, `createPaymentIntent`, `getAccountById`, `notifyFoundersOnUserFeedbackSubmitted`, `notifyVenueOfInterestedOpportunities`, `sendEmailOnSubscriptionExpiration`, `sendEmailOnSubscriptionPurchase`, `transformLocationPayloadForSearch`. Moving the existing source does not recover them. Recover deployed build source if maintenance is needed, or confirm provider routing/usage before retiring them.
- Remaining Firestore triggers and extension writers are still deployed. In particular, Stripe's Auth-triggered customer creation, Stripe's HTTP webhook, scheduled writes and BigQuery extensions need a separate retirement audit. Client deny-all rules do not stop Admin SDK writers.
- Firebase-managed extensions are controlled through Firebase/Google Cloud, not this package. Removing mobile code or removing an export does **not** undeploy them.
- No production functions, extensions, provider URLs, schedulers, credentials or Firestore data were changed in this cleanup.

## Approved Mailchimp retirement

`addUserToMailchimpOnCreated` (Gen1, `us-central1`) has been deleted with explicit user approval:
Mailchimp is no longer used. Its source/export, deployment allowlist entry and npm dependencies were
removed, along with the Rust signup subscription step and worker configuration. The deployment guard
now rejects that name. No source Firestore documents or Mailchimp account/audience/customer data were
deleted. The inventory below remains the original historical snapshot; its source/allowlist columns
are not the current entrypoint contract.

## Follow-up before shutting down Firestore itself

Verify third-party routing (Postmark, Stream, RevenueCat/Stripe) and remaining Auth/extension dependencies; migrate or retire legacy handlers explicitly. Do not redeploy missing-source or Firestore-backed handlers, and do not delete managed extensions blindly (they can clean up data). This follow-up is separate from removing the retired mobile source.

## Inventory

Only safe deployment metadata is recorded in [deployment-inventory.json](deployment-inventory.json): names, generation/state, trigger patterns and source availability. No environment variables, secrets, private source bundles or document data are included.

| Function | Generation / state | Trigger | Source ownership | Allowlisted |
| --- | --- | --- | --- | --- |
| `addUserToMailchimpOnCreated` | GEN_1 / ACTIVE | providers/firebase.auth/eventTypes/user.create | `src/lib/mailchimp.ts` | Yes |
| `createConnectedAccount` | GEN_1 / ACTIVE | HTTP | **Missing from repository** | No |
| `createPaymentIntent` | GEN_1 / ACTIVE | HTTP | **Missing from repository** | No |
| `createStreamUserOnUserCreated` | GEN_1 / ACTIVE | providers/cloud.firestore/eventTypes/document.create | `src/lib/stream.ts` | No |
| `deleteStreamUser` | GEN_1 / ACTIVE | providers/firebase.auth/eventTypes/user.delete | `src/lib/stream.ts` | Yes |
| `ext-auth-chat-createStreamUser` | GEN_1 / ACTIVE | providers/firebase.auth/eventTypes/user.create | Managed extension | No |
| `ext-auth-chat-deleteStreamUser` | GEN_1 / ACTIVE | providers/firebase.auth/eventTypes/user.delete | Managed extension | No |
| `ext-auth-chat-getStreamUserToken` | GEN_1 / ACTIVE | HTTP | Managed extension | No |
| `ext-auth-chat-revokeStreamUserToken` | GEN_1 / ACTIVE | HTTP | Managed extension | No |
| `ext-firestore-bigquery-export-73n7-fsexportbigquery` | GEN_1 / ACTIVE | providers/cloud.firestore/eventTypes/document.write | Managed extension | No |
| `ext-firestore-bigquery-export-73n7-fsimportexistingdocs` | GEN_1 / ACTIVE | HTTP | Managed extension | No |
| `ext-firestore-bigquery-export-73n7-initBigQuerySync` | GEN_1 / ACTIVE | HTTP | Managed extension | No |
| `ext-firestore-bigquery-export-73n7-setupBigQuerySync` | GEN_1 / ACTIVE | HTTP | Managed extension | No |
| `ext-firestore-bigquery-export-73n7-syncBigQuery` | GEN_1 / ACTIVE | HTTP | Managed extension | No |
| `ext-firestore-bigquery-export-d85k-fsexportbigquery` | GEN_1 / ACTIVE | providers/cloud.firestore/eventTypes/document.write | Managed extension | No |
| `ext-firestore-bigquery-export-d85k-fsimportexistingdocs` | GEN_1 / ACTIVE | HTTP | Managed extension | No |
| `ext-firestore-bigquery-export-d85k-initBigQuerySync` | GEN_1 / ACTIVE | HTTP | Managed extension | No |
| `ext-firestore-bigquery-export-d85k-setupBigQuerySync` | GEN_1 / ACTIVE | HTTP | Managed extension | No |
| `ext-firestore-bigquery-export-d85k-syncBigQuery` | GEN_1 / ACTIVE | HTTP | Managed extension | No |
| `ext-firestore-bigquery-export-fsexportbigquery` | GEN_1 / ACTIVE | providers/cloud.firestore/eventTypes/document.write | Managed extension | No |
| `ext-firestore-bigquery-export-fsimportexistingdocs` | GEN_1 / ACTIVE | HTTP | Managed extension | No |
| `ext-firestore-bigquery-export-initBigQuerySync` | GEN_1 / ACTIVE | HTTP | Managed extension | No |
| `ext-firestore-bigquery-export-setupBigQuerySync` | GEN_1 / ACTIVE | HTTP | Managed extension | No |
| `ext-firestore-bigquery-export-syncBigQuery` | GEN_1 / ACTIVE | HTTP | Managed extension | No |
| `ext-firestore-schedule-writes-deliverWrites` | GEN_1 / ACTIVE | google.pubsub.topic.publish | Managed extension | No |
| `ext-firestore-send-email-processQueue` | GEN_1 / ACTIVE | providers/cloud.firestore/eventTypes/document.write | Managed extension | No |
| `ext-firestore-stripe-payments-createCheckoutSession` | GEN_1 / ACTIVE | providers/cloud.firestore/eventTypes/document.create | Managed extension | No |
| `ext-firestore-stripe-payments-createCustomer` | GEN_1 / ACTIVE | providers/firebase.auth/eventTypes/user.create | Managed extension | No |
| `ext-firestore-stripe-payments-createPortalLink` | GEN_1 / ACTIVE | HTTP | Managed extension | No |
| `ext-firestore-stripe-payments-handleWebhookEvents` | GEN_1 / ACTIVE | HTTP | Managed extension | No |
| `ext-firestore-stripe-payments-onCustomerDataDeleted` | GEN_1 / ACTIVE | providers/cloud.firestore/eventTypes/document.delete | Managed extension | No |
| `ext-firestore-stripe-payments-onUserDeleted` | GEN_1 / ACTIVE | providers/firebase.auth/eventTypes/user.delete | Managed extension | No |
| `getAccountById` | GEN_1 / ACTIVE | HTTP | **Missing from repository** | No |
| `getArtistBySpotifyId` | GEN_2 / ACTIVE | HTTP | `src/lib/spotify.ts` | Yes |
| `getTopTracksByArtistId` | GEN_2 / ACTIVE | HTTP | `src/lib/spotify.ts` | Yes |
| `inboundEmailWebhook` | GEN_2 / ACTIVE | HTTP | `src/lib/webhooks.ts` | Yes |
| `notifyFoundersOnAppRemoved` | GEN_1 / ACTIVE | providers/google.firebase.analytics/eventTypes/event.log | `src/lib/signups.ts` | No |
| `notifyFoundersOnBookings` | GEN_1 / ACTIVE | providers/cloud.firestore/eventTypes/document.create | `src/lib/bookings.ts` | No |
| `notifyFoundersOnEmail` | GEN_2 / ACTIVE | google.cloud.firestore.document.v1.created | `src/lib/dm_email_sync/venue_contacting.ts` | No |
| `notifyFoundersOnOpportunityInterest` | GEN_1 / ACTIVE | providers/cloud.firestore/eventTypes/document.create | `src/lib/opportunities.ts` | No |
| `notifyFoundersOnOrphanEmail` | GEN_2 / ACTIVE | google.cloud.firestore.document.v1.created | `src/lib/dm_email_sync/venue_contacting.ts` | No |
| `notifyFoundersOnSignUp` | GEN_1 / ACTIVE | providers/firebase.auth/eventTypes/user.create | `src/lib/signups.ts` | Yes |
| `notifyFoundersOnUserDelete` | GEN_1 / ACTIVE | providers/firebase.auth/eventTypes/user.delete | `src/lib/signups.ts` | Yes |
| `notifyFoundersOnUserFeedbackSubmitted` | GEN_2 / ACTIVE | google.cloud.firestore.document.v1.created | **Missing from repository** | No |
| `notifyFoundersOnUserOnboarded` | GEN_2 / ACTIVE | google.cloud.firestore.document.v1.created | `src/lib/signups.ts` | No |
| `notifyFoundersOnVenueContact` | GEN_2 / ACTIVE | google.cloud.firestore.document.v1.created | `src/lib/dm_email_sync/venue_contacting.ts` | No |
| `notifyVenueOfInterestedOpportunities` | GEN_2 / ACTIVE | HTTP | **Missing from repository** | No |
| `sendBookingRequestReceivedEmailOnBooking` | GEN_1 / ACTIVE | providers/cloud.firestore/eventTypes/document.create | `src/lib/email_triggers.ts` | No |
| `sendBookingRequestSentEmailOnBooking` | GEN_1 / ACTIVE | providers/cloud.firestore/eventTypes/document.create | `src/lib/email_triggers.ts` | No |
| `sendEmailOnSubscriptionExpiration` | GEN_2 / ACTIVE | HTTP | **Missing from repository** | No |
| `sendEmailOnSubscriptionPurchase` | GEN_2 / ACTIVE | HTTP | **Missing from repository** | No |
| `sendToDevice` | GEN_1 / UNKNOWN | providers/cloud.firestore/eventTypes/document.create | `src/lib/activities.ts` | No |
| `sendWelcomeEmailOnUserCreated` | GEN_1 / ACTIVE | providers/firebase.auth/eventTypes/user.create | `src/lib/email_triggers.ts` | Yes |
| `setLatestContactRequest` | GEN_2 / ACTIVE | google.cloud.firestore.document.v1.created | `src/lib/dm_email_sync/venue_contacting.ts` | No |
| `spotifyAuthorizeCodeGrant` | GEN_2 / ACTIVE | HTTP | `src/lib/spotify.ts` | Yes |
| `spotifyRedirect` | GEN_2 / ACTIVE | HTTP | `src/lib/spotify.ts` | Yes |
| `spotifyRefreshToken` | GEN_2 / ACTIVE | HTTP | `src/lib/spotify.ts` | Yes |
| `streamBeforeMessageWebhook` | GEN_2 / ACTIVE | HTTP | `src/lib/webhooks.ts` | Yes |
| `transformLocationPayloadForSearch` | GEN_1 / ACTIVE | HTTP | **Missing from repository** | No |
| `updateStreamUserOnUserUpdate` | GEN_1 / UNKNOWN | providers/cloud.firestore/eventTypes/document.update | `src/lib/stream.ts` | No |

## Refresh

```sh
gcloud functions list --project=in-the-loop-306520 \
  --format='table(name.basename(),environment,state,status,buildConfig.entryPoint,entryPoint,eventTrigger.eventType)'
```

Inspect source/trigger changes manually and update the sanitized inventory. Never save full `gcloud functions describe` output in the repository: it may contain privileged environment configuration.
