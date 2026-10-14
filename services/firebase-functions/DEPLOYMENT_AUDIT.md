# Live Firebase deployment audit

## Final production state — 2026-10-14

Production has exactly **two Gen1 Node.js 22 Functions**: `onUserCreate` and `onUserDelete`.
Both are authenticated, retryable transports to Rust, with no business logic or HTTP/Firestore exports.
The former four Auth transports and every other Function/managed extension are deleted. The Rust
API, mail worker and identity worker run on Hetzner at `40f3513df01d22986a7e2f5c5b40dcf5a8579e58`.

Real synthetic checks after retirement proved one signup/deletion job each, Stream provisioning and
confirmed deletion, UID-bound token minting, actual WebSocket rejection of a revoked token before
and after a Rust profile upsert, successful fresh-token connections, and refusal to mint for deleted
identities. Firebase hosted verification links still work; a verification code was applied successfully.
The SDK/REST timestamp precision mismatch discovered live is fixed and migrated without replay.

Two obsolete live Stripe callbacks were removed: the retired payments extension and an already-
absent cover-art Cloud Run service. Unrelated RevenueCat callbacks (live/test) and all billing objects
were preserved. StoreKit remains unchanged. Postmark configuration is explicitly deferred to the owner;
no mail Worker remains on Cloudflare. See `deployment-retirement-audit.json` for sanitized evidence.

The sections below are historical snapshots and do not describe current deployment state.

Checked **2026-10-12T17:15:23.312468+00:00**, project `in-the-loop-306520`, all regions: **60 deployed functions**, including **27 Firebase-managed extension functions**.

This original table is a historical read-only inventory, not the current production state. On **2026-10-14**, user-approved retirement of three BigQuery extensions removed **15 Functions** and **16 task queues**; all six BigQuery archive tables/views and their metadata row counts were preserved. All-regions Functions inventory now lists **40 Functions**. See [the current retirement plan](../../platform/FIREBASE_FUNCTIONS_RETIREMENT.md).

The original inventory itself is not a deployment or retirement operation. `ACTIVE` is provider state, not proof of current traffic; `UNKNOWN` is not proof a function is disabled. Paused schedulers may still have an active backing function.

## Read-only usage follow-up — 2026-10-14T13:30:37Z

[`deployment-usage-audit.json`](deployment-usage-audit.json) records a fresh all-regions inventory and a bounded 30-day log audit: **40 Functions (26 Gen1 / 14 Gen2; 28 custom / 12 managed)**, zero BigQuery Functions. All 14 Gen2 services were mapped; 9,570 matching log entries were returned below the 100,000-record cap. Raw logs/configuration remain private (0600); the committed artifact contains only names, states, timestamps and aggregate counts.

Important contrary evidence: `updateStreamUserOnUserUpdate` is `UNKNOWN` but has **2,365 execution starts** (last 2026-10-10), and `transformLocationPayloadForSearch` has **10 execution starts** (last 2026-10-01). Neither is proven disabled/unused by its source status. Stripe's webhook has five execution starts (last 2026-10-11); its obsolete provider routing must still be disconnected deliberately. The scheduled-writes extension last started on 2026-10-10, consistent with the separately verified paused scheduler; 634 historical starts do not indicate current scheduling.

Supported-source inspection found no Functions SDK/callable/Cloud Functions URL in current app/package clients. Native Stream tokens, opportunity notifications and Spotify artist lookup route through authenticated Rust repositories. Native Spotify currently imports an artist link, not an OAuth connection; that does **not** prove the old OAuth provider callback can be removed. Request-builder tests cover only their named routes, not real delivery or external caller absence.

**Historical client audit, superseded by owner clarification:** StoreKit purchases/paywalls are supported and must remain. Native dependencies and `SubscriptionStoreView` were preserved; the web Stripe pricing-table script was removed. Stripe retirement does not disable StoreKit.

No matching logs is **not** proof of no callers: retention, exclusions, sampling, external provider configuration and installed legacy clients remain separate checks. No production resource, provider object or source document was changed by this audit.

## Findings

- **Current target is only two transport-only Firebase Auth hooks (`onUserCreate`, `onUserDelete`); all other Functions/extensions must be deletable.** See [the full retirement plan](../../platform/FIREBASE_FUNCTIONS_RETIREMENT.md). Founder booking/application/onboarding alerts are required business behavior, not obsolete triggers: Rust outbox replacements were deployed and verified through live API actions, then those three Functions were deleted (40 remain after subsequent Stream callback, Mailchimp and BigQuery retirements). The table below is the original inventory snapshot, not the current function count. Other notification/Auth effects must also be accounted for.
- Backend source and Firebase project/deployment configuration are independent of the retired mobile directory.
- The entrypoint explicitly exports only the current allowlisted thin Auth transports and temporary HTTP compatibility endpoints. Legacy Firestore modules are preserved for reference, **not exported or approved for deployment**. Previously deleted triggers (including `onUserDeleted`, default-service and review-counter writers) cannot be recreated by the supported deployment command.
- Both webhook compatibility handlers delegate to Rust; the Stream proxy forwards the original bytes/signature instead of accessing Firestore. These local changes have **not been deployed**.
- **8 custom functions are deployed but absent from the repository source**: `createConnectedAccount`, `createPaymentIntent`, `getAccountById`, `notifyFoundersOnUserFeedbackSubmitted`, `notifyVenueOfInterestedOpportunities`, `sendEmailOnSubscriptionExpiration`, `sendEmailOnSubscriptionPurchase`, `transformLocationPayloadForSearch`. Moving the existing source does not recover them. Recover deployed build source if maintenance is needed, or confirm provider routing/usage before retiring them.
- Remaining Firestore triggers and extension writers are still deployed. In particular, Stripe's Auth-triggered customer creation, Stripe's HTTP webhook and scheduled writes need a separate retirement audit. BigQuery extensions were subsequently retired with explicit user approval; billing is retirement-only for the free launch. Client deny-all rules do not stop Admin SDK writers.
- Firebase-managed extensions are controlled through Firebase/Google Cloud, not this package. Removing mobile code or removing an export does **not** undeploy them.
- The original source cleanup changed no production resources. Subsequent explicitly approved retirements are recorded above; no source Firestore, billing or analytics data was deleted.

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
