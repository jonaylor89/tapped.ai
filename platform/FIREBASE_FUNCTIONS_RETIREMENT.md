# Target: zero Firebase Functions

The goal is to delete **all custom and extension-managed Firebase Functions**, in every region/generation, without losing required behavior. Firebase **Auth and hosted email verification remain**. No migrated application-data Firestore fallback, sync or dual writes may be introduced. No source Firestore documents, billing accounts or analytics datasets are deleted by this plan.

The [live inventory](../services/firebase-functions/DEPLOYMENT_AUDIT.md) records **60 functions** (27 extension-managed) at 2026-10-12T17:15:23.312468+00:00. It is a snapshot, not evidence of traffic or replacement parity. Production now has **55 Functions**: the three founder booking/application/onboarding triggers and Stream callback were deleted after live Rust verification; `addUserToMailchimpOnCreated` was explicitly retired because Mailchimp is no longer used. The original inventory below remains a historical 60-function checklist.

## Founder bookings, applications and onboarding — implemented locally

- Migration `20261016000000_founder_notification_outbox.sql` and `src/domain/founder_notifications.rs` add a private Postgres outbox.
- New profile creation, new booking creation and first opportunity application enqueue inside the **same business transaction**. Imports/updates/repeated applications do not replay old events.
- Legacy filters remain: skip unclaimed/deleted onboarding; skip scraper/crawler bookings and ordinary manually added history; retain missing-requester/location founder alerts. Initial application comments are captured once.
- The worker runs inside the production Rust API when `SLACK_WEBHOOK_URL` is configured. Missing configuration retains events for later delivery; it never silently discards them.
- Atomic leases, recovery after worker crashes, bounded backoff and Slack Retry-After handling protect delivery. API retries/concurrent applications generate one event.
- Delivery is **at-least-once**, not exactly-once: Slack incoming webhooks have no cross-database/idempotency contract. A crash or lost response after Slack acceptance can repeat a message.
- The queue is not exposed through public/private collection APIs. Logs contain no message bodies or webhook credentials.
- Validation: library tests, full API tests with a real isolated PostGIS DB, rollback/lease/retry/concurrency tests, and one explicitly labelled real Slack smoke message accepted by the existing webhook.
- The existing Slack secret was staged privately in production `.env` with a root-only backup; no services were restarted. Compose passes it into Rust on the next rollout.
- **Deployed and verified** at `05b9311533f91c40f59ebe1aee7ca078476a6e1e` (Deploy API `38302412506`; Node/Rust/iOS/functions CI passed). Live API-created onboarding (two accounts), booking and application events reached Slack; repeat application produced no extra event. Synthetic accounts/rows were removed. The three corresponding legacy Functions were then deleted; no source Firestore documents were deleted.

Queue operations (run only through a trusted administrative DB connection; do not publish payloads):

```sql
SELECT event_type, count(*), min(created_at), max(attempts)
FROM founder_notification_outbox WHERE delivered_at IS NULL GROUP BY event_type;
SELECT count(*) FROM founder_notification_outbox WHERE locked_until < now() AND delivered_at IS NULL;
```

Delivered event keys are retained for deduplication. Payloads contain internal founder-notification data; include this table in private Postgres backups/retention policy, never client serving.

## Identity/provider rollout (deployed; retirement gates remain)

Deployed at `4e0e2307377b` (Deploy API `38308109118`; Rust/Node/functions CI passed; 64 library + 78 real-PostGIS API tests). Rust now has a separate identity/provider worker, private generic outbox, Auth lifecycle ledger,
per-device FCM jobs, booking email jobs, Stream profile/delete synchronization and stable-ID
founder welcome DMs. It baselines existing Firebase Auth accounts without replaying old welcomes,
confirms apparent deletions with an individual Auth lookup, and never reads/writes Firestore.
The production baseline completed with **119,548 Auth identities**, without replaying old accounts. A real synthetic Auth signup was captured once while held, then its enabled provider effects completed; deletion was independently confirmed and Stream cleanup completed. The fixture was removed. **Auth effects were returned to held mode** because legacy Auth hooks remain: identity capture continues, and new lifecycle deliveries remain durable in the queue rather than running concurrently with legacy hooks. Email templates were read once from the
legacy template collection, preserved privately for Postgres provisioning, without changing source.
An isolated principal with only `firebaseauth.users.get` and `cloudmessaging.messages.create` was
provisioned; live checks confirmed Auth reads work and Firestore access is denied (403). Its private
credential is mounted only in the optional identity worker, never the serving API.

A Stream conformance gap was also fixed: success must return JSON with the entire original message,
not a plain-text status. Attachment-only messages and claimed-user DM email preferences are supported. The provider callback was then changed directly to Rust and a real signed Stream message preserved custom fields. Synthetic users/channel were cleaned; `streamBeforeMessageWebhook` was deleted only after this check.

**Postmark blocker:** changing InboundHookUrl was rejected with HTTP 422: "You are not entitled to
Inbound processing. To add inbound, upgrade to the next tier." No plan upgrade was made; the existing
provider URL remains unchanged. Zero Functions requires an approved upgrade or alternative provider.
The old inbound URL must remain a compatibility proxy in the meantime. That named Function was selectively updated to the Rust-only bridge, and its unchanged public URL was verified to persist in the Rust mail store. The plan itself was not upgraded.

## Latest production checks and concrete blockers

- API and optional identity worker run `eb577af2bc74` (Deploy API `38311045804` succeeded); readiness checks are healthy. `5ceddc6055cc` also deployed successfully through `38310078030`.
- Labelled founder mail: provider job → SQLite durable mail handoff → Postmark accepted, final mail state `sent`; synthetic fixture removed.
- Founder FCM probe: provider identified an expired registration as `UNREGISTERED`; Rust removed that invalid token. **No current-device delivery proven**; obtain a fresh test token before retiring `sendToDevice`.
- **Mailchimp deliberately retired by user approval.** Deleted Gen1 `addUserToMailchimpOnCreated` in `us-central1`; removed its entrypoint, deployment allowlist entry, source, npm dependencies, Rust signup call and worker configuration. The prior 403 `User Disabled` is no longer a migration blocker. No Mailchimp account/audience/customer data or source Firestore documents were deleted. Remaining Auth/welcome/founder effects are unchanged; held Auth jobs are retained, not discarded.
- Rust orphan handling now durably forwards to the founder and queues a Slack alert, instead of just storing the orphan. Stable keys prevent retry-created duplicate jobs. Local mail tests passed; positive live orphan forwarding/Slack retirement verification remains.
- Authenticated `POST /app/v1/feedback` accepts `{id: UUID, text: string}`; server owns sender identity, escapes Slack mentions, rejects invalid text and deduplicates per sender/id. Private queue only; local real-PostGIS test passed. Live feedback retirement check remains.
- Remaining billing/entitlement, managed-extension and reminder retirement gates below are **not complete**. 55 Functions still exist; no blanket deletion is approved or executed.
- Temporary isolated PostGIS container and tunnel were removed. Original Firestore data is unchanged.

## Required remaining work

1. Deploy/verify the founder outbox above.
2. Replace Auth side effects with a reliable account-lifecycle source that handles signup/deletion, including admin/provider-created accounts. Bootstrap/baseline existing identities to avoid replaying welcomes. Mailchimp is intentionally retired, not a replacement requirement. Firebase login/verification must remain intact.
3. Verify/implement push delivery and booking email/reminder behavior. Token registration and stored activities are **not** proof of remote push or email delivery.
4. Finish Stream profile/user/token lifecycle and direct Stream/Postmark provider routing. Postmark's unchanged inbound URL/plan is a real removal dependency, not a reason to keep a Function indefinitely; change the provider configuration/plan or choose a supported alternative before deleting its proxy.
5. Resolve billing/entitlement/webhook behavior and missing-source custom functions. Retire genuinely obsolete features explicitly; do not infer that an active subscription/webhook is unused from source grep.
6. Retire extensions deliberately, including their Pub/Sub/Eventarc/scheduler resources, while preserving source documents and billing/analytics data.
7. Delete bounded batches only after their gates below pass; refresh the all-regions Gen1/Gen2 inventory after each batch. Remove the standalone Firebase backend package/CI once no deployment source is needed.

No blanket delete/uninstall command is supplied: some extension uninstall/cleanup paths can affect data, and the inventory alone does not establish safety.

## Every remaining function has a removal gate

| Function | Replacement / deletion gate |
| --- | --- |
| `addUserToMailchimpOnCreated` | **Deleted** with explicit user approval; Mailchimp is no longer used and has no Rust replacement |
| `createConnectedAccount` | Verify live billing/provider routing, existing subscriptions, customer/account cleanup and entitlement authority; recover missing source if needed |
| `createPaymentIntent` | Verify live billing/provider routing, existing subscriptions, customer/account cleanup and entitlement authority; recover missing source if needed |
| `createStreamUserOnUserCreated` | Replace/verify Stream profile synchronization from authoritative API profile changes, without Firestore |
| `deleteStreamUser` | Rust token endpoint exists; verify/replace Stream user provisioning, deletion and token revocation before removing Auth hooks/extension |
| `ext-auth-chat-createStreamUser` | Rust token endpoint exists; verify/replace Stream user provisioning, deletion and token revocation before removing Auth hooks/extension |
| `ext-auth-chat-deleteStreamUser` | Rust token endpoint exists; verify/replace Stream user provisioning, deletion and token revocation before removing Auth hooks/extension |
| `ext-auth-chat-getStreamUserToken` | Rust token endpoint exists; verify/replace Stream user provisioning, deletion and token revocation before removing Auth hooks/extension |
| `ext-auth-chat-revokeStreamUserToken` | Rust token endpoint exists; verify/replace Stream user provisioning, deletion and token revocation before removing Auth hooks/extension |
| `ext-firestore-bigquery-export-73n7-fsexportbigquery` | Retire Firestore analytics export extension after deciding Postgres analytics replacement/retention; do not delete datasets blindly |
| `ext-firestore-bigquery-export-73n7-fsimportexistingdocs` | Retire Firestore analytics export extension after deciding Postgres analytics replacement/retention; do not delete datasets blindly |
| `ext-firestore-bigquery-export-73n7-initBigQuerySync` | Retire Firestore analytics export extension after deciding Postgres analytics replacement/retention; do not delete datasets blindly |
| `ext-firestore-bigquery-export-73n7-setupBigQuerySync` | Retire Firestore analytics export extension after deciding Postgres analytics replacement/retention; do not delete datasets blindly |
| `ext-firestore-bigquery-export-73n7-syncBigQuery` | Retire Firestore analytics export extension after deciding Postgres analytics replacement/retention; do not delete datasets blindly |
| `ext-firestore-bigquery-export-d85k-fsexportbigquery` | Retire Firestore analytics export extension after deciding Postgres analytics replacement/retention; do not delete datasets blindly |
| `ext-firestore-bigquery-export-d85k-fsimportexistingdocs` | Retire Firestore analytics export extension after deciding Postgres analytics replacement/retention; do not delete datasets blindly |
| `ext-firestore-bigquery-export-d85k-initBigQuerySync` | Retire Firestore analytics export extension after deciding Postgres analytics replacement/retention; do not delete datasets blindly |
| `ext-firestore-bigquery-export-d85k-setupBigQuerySync` | Retire Firestore analytics export extension after deciding Postgres analytics replacement/retention; do not delete datasets blindly |
| `ext-firestore-bigquery-export-d85k-syncBigQuery` | Retire Firestore analytics export extension after deciding Postgres analytics replacement/retention; do not delete datasets blindly |
| `ext-firestore-bigquery-export-fsexportbigquery` | Retire Firestore analytics export extension after deciding Postgres analytics replacement/retention; do not delete datasets blindly |
| `ext-firestore-bigquery-export-fsimportexistingdocs` | Retire Firestore analytics export extension after deciding Postgres analytics replacement/retention; do not delete datasets blindly |
| `ext-firestore-bigquery-export-initBigQuerySync` | Retire Firestore analytics export extension after deciding Postgres analytics replacement/retention; do not delete datasets blindly |
| `ext-firestore-bigquery-export-setupBigQuerySync` | Retire Firestore analytics export extension after deciding Postgres analytics replacement/retention; do not delete datasets blindly |
| `ext-firestore-bigquery-export-syncBigQuery` | Retire Firestore analytics export extension after deciding Postgres analytics replacement/retention; do not delete datasets blindly |
| `ext-firestore-schedule-writes-deliverWrites` | Keep scheduler paused; preserve/replace any required booking reminders/expiry jobs before extension retirement |
| `ext-firestore-send-email-processQueue` | Verify all email producers moved to Rust mail worker; reconcile pending legacy mail without duplicate delivery |
| `ext-firestore-stripe-payments-createCheckoutSession` | Verify live billing/provider routing, existing subscriptions, customer/account cleanup and entitlement authority; recover missing source if needed |
| `ext-firestore-stripe-payments-createCustomer` | Verify live billing/provider routing, existing subscriptions, customer/account cleanup and entitlement authority; recover missing source if needed |
| `ext-firestore-stripe-payments-createPortalLink` | Verify live billing/provider routing, existing subscriptions, customer/account cleanup and entitlement authority; recover missing source if needed |
| `ext-firestore-stripe-payments-handleWebhookEvents` | Verify live billing/provider routing, existing subscriptions, customer/account cleanup and entitlement authority; recover missing source if needed |
| `ext-firestore-stripe-payments-onCustomerDataDeleted` | Verify live billing/provider routing, existing subscriptions, customer/account cleanup and entitlement authority; recover missing source if needed |
| `ext-firestore-stripe-payments-onUserDeleted` | Verify live billing/provider routing, existing subscriptions, customer/account cleanup and entitlement authority; recover missing source if needed |
| `getAccountById` | Verify live billing/provider routing, existing subscriptions, customer/account cleanup and entitlement authority; recover missing source if needed |
| `getArtistBySpotifyId` | Rust Spotify lookup routes exist; verify live callers then delete legacy callable |
| `getTopTracksByArtistId` | Rust Spotify lookup routes exist; verify live callers then delete legacy callable |
| `inboundEmailWebhook` | Switch Postmark inbound provider URL/authentication to Rust and verify real replies; old URL currently requires compatibility proxy |
| `notifyFoundersOnAppRemoved` | Legacy analytics removal signal; Android retired/native Firebase Analytics unused, confirm intentional retirement |
| `notifyFoundersOnBookings` | **Deleted** after production Rust/outbox/Slack verification |
| `notifyFoundersOnEmail` | Rust venue outreach/mail persistence exists; verify founder delivery and provider routing before retiring Firestore contact workflow |
| `notifyFoundersOnOpportunityInterest` | **Deleted** after production Rust/outbox/Slack verification |
| `notifyFoundersOnOrphanEmail` | Rust records orphan mail, but founder orphan alert/forwarding needs an explicit replacement |
| `notifyFoundersOnSignUp` | Port reliable Firebase Auth lifecycle capture + deduplicated Slack/email effects; do not confuse signup with profile onboarding |
| `notifyFoundersOnUserDelete` | Port reliable Firebase Auth lifecycle capture + deduplicated Slack/email effects; do not confuse signup with profile onboarding |
| `notifyFoundersOnUserFeedbackSubmitted` | Recover missing handler behavior or replace founder feedback delivery via the supported feedback/support channel |
| `notifyFoundersOnUserOnboarded` | **Deleted** after production Rust/outbox/Slack verification |
| `notifyFoundersOnVenueContact` | Rust venue outreach/mail persistence exists; verify founder delivery and provider routing before retiring Firestore contact workflow |
| `notifyVenueOfInterestedOpportunities` | Rust venue outreach/mail persistence exists; verify founder delivery and provider routing before retiring Firestore contact workflow |
| `sendBookingRequestReceivedEmailOnBooking` | Preserve booking-request email recipients/templates/filters with durable Rust delivery before retiring |
| `sendBookingRequestSentEmailOnBooking` | Preserve booking-request email recipients/templates/filters with durable Rust delivery before retiring |
| `sendEmailOnSubscriptionExpiration` | Verify live billing/provider routing, existing subscriptions, customer/account cleanup and entitlement authority; recover missing source if needed |
| `sendEmailOnSubscriptionPurchase` | Verify live billing/provider routing, existing subscriptions, customer/account cleanup and entitlement authority; recover missing source if needed |
| `sendToDevice` | Verify/implement Rust FCM/APNs delivery from authoritative events; API token registration alone is not push delivery |
| `sendWelcomeEmailOnUserCreated` | Port reliable Firebase Auth lifecycle capture + deduplicated Slack/email effects; do not confuse signup with profile onboarding |
| `setLatestContactRequest` | Rust venue outreach/mail persistence exists; verify founder delivery and provider routing before retiring Firestore contact workflow |
| `spotifyAuthorizeCodeGrant` | Verify/replace OAuth redirect, exchange and refresh routes for every supported client/provider; source-only grep is insufficient |
| `spotifyRedirect` | Verify/replace OAuth redirect, exchange and refresh routes for every supported client/provider; source-only grep is insufficient |
| `spotifyRefreshToken` | Verify/replace OAuth redirect, exchange and refresh routes for every supported client/provider; source-only grep is insufficient |
| `streamBeforeMessageWebhook` | **Deleted** after direct provider routing and signed message verification |
| `transformLocationPayloadForSearch` | Postgres search replaces legacy indexing; verify no remaining external indexing webhook caller then retire |
| `updateStreamUserOnUserUpdate` | Replace/verify Stream profile synchronization from authoritative API profile changes, without Firestore |

## Completion criteria

- All required business effects execute through Rust/explicitly supported non-Function infrastructure; live end-to-end tests pass.
- Provider callback URLs and supported clients no longer depend on Cloud Functions endpoints.
- Google Cloud lists **zero Gen1 and zero Gen2 Firebase Functions across all regions**, including extension-generated functions; no managed extension can recreate them.
- No orphan trigger/scheduler continues invoking removed handlers or mutating migrated data.
- Firebase Auth/email verification still work; source Firestore archives/documents remain protected.
