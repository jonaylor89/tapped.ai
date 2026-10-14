# Target: only transport-only Firebase Auth hooks

The current user-approved target is to make **every non-Auth custom and extension-managed Firebase Function deletable**, in every region/generation, without losing required behavior. Retain the existing Auth hooks only as authenticated webhook transports to Rust; no welcome email, Slack, Stream, billing or application-data business logic may execute in them. Firebase **Auth and hosted email verification remain**. No migrated application-data Firestore fallback, sync or dual writes may be introduced. No source Firestore documents, billing accounts or analytics datasets are deleted by this plan.

After user-approved BigQuery retirement, the all-regions production check on **2026-10-14** confirmed **40 Functions: 28 custom and 12 extension-managed** (down from 55). The user subsequently clarified that this is a **free launch with no billing/customer backfill**. Stripe/payment/subscription Functions are now retirement-only, not Rust replacement requirements. Historical provider objects observed by the audit remain untouched; do not delete/cancel customers, connected accounts or subscriptions as part of retiring Functions.

The [live inventory](../services/firebase-functions/DEPLOYMENT_AUDIT.md) records **60 functions** (27 extension-managed) at 2026-10-12T17:15:23.312468+00:00. It is a snapshot, not evidence of traffic or replacement parity. Production now has **40 Functions**: the three founder booking/application/onboarding triggers and Stream callback were deleted after live Rust verification; Mailchimp and all 15 BigQuery extension Functions were explicitly retired by the user. The original inventory below remains a historical 60-function checklist.

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
The production baseline completed with **119,548 Auth identities**, without replaying old accounts. A real synthetic Auth signup was captured once while held, then its enabled provider effects completed; subsequent Auth deletion and Stream-user absence were observed. Legacy Auth/chat handlers were also active, so that absence does **not** independently prove Rust-only Stream deletion. A later local HTTP audit found the Rust delete-path/404 gap documented below; replacement-only cleanup must be reverified after rollout. The fixture was removed. **Auth effects were returned to held mode** because legacy Auth hooks remain: identity capture continues, and new lifecycle deliveries remain durable in the queue rather than running concurrently with legacy hooks. Email templates were read once from the
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

- Latest read-only container inspection on 2026-10-14: API, identity worker and mail worker run `49fa76bfdf76cd29044f2cb32242749b0676754c`. New Auth transports, booking reminders, Spotify OAuth and Stream revocation remain local, not deployed.
- Labelled founder mail: provider job → SQLite durable mail handoff → Postmark accepted, final mail state `sent`; synthetic fixture removed.
- Founder FCM probe: provider identified an expired registration as `UNREGISTERED`; Rust removed that invalid token. **No current-device delivery proven**; obtain a fresh test token before retiring `sendToDevice`.
- **Mailchimp deliberately retired by user approval.** Deleted Gen1 `addUserToMailchimpOnCreated` in `us-central1`; removed its entrypoint, deployment allowlist entry, source, npm dependencies, Rust signup call and worker configuration. The prior 403 `User Disabled` is no longer a migration blocker. No Mailchimp account/audience/customer data or source Firestore documents were deleted. Remaining Auth/welcome/founder effects are unchanged; held Auth jobs are retained, not discarded.
- Rust orphan handling durably forwards to the founder and queues a Slack alert. **Live verified on 2026-10-14** through two identical authenticated public HTTP posts: one mail-outbox event, one Postmark message with a **Delivered** event, and one acknowledged Slack outbox event. Synthetic records are labelled and retained privately for audit; no source Firestore data changed. Legacy orphan-trigger retirement is now eligible for an approved bounded deletion.
- Authenticated `POST /app/v1/feedback` accepts `{id: UUID, text: string}`; server owns sender identity, escapes Slack mentions, rejects invalid text and deduplicates per sender/id. Private queue only; local real-PostGIS test passed. Live feedback retirement check remains.
- Managed-extension/provider-routing and reminder retirement gates below are **not complete**. Billing replacement/backfill is no longer required for the explicitly free launch. 40 Functions still exist; only individually approved and verified retirements have been executed.
- Temporary isolated PostGIS container and tunnel were removed. Original Firestore data is unchanged.

## Remaining caller/client audit — read-only, 2026-10-14

- Fresh all-regions inventory still lists **40 Functions**: 26 Gen1 / 14 Gen2, 28 custom / 12 managed; zero BigQuery Functions. [`deployment-usage-audit.json`](../services/firebase-functions/deployment-usage-audit.json) records a complete bounded 30-day query below its cap, with all Gen2 services mapped. It is aggregate metadata, not deletion authorization or business parity proof.
- `updateStreamUserOnUserUpdate` (`UNKNOWN`) has 2,365 historical execution starts through 2026-10-10. `transformLocationPayloadForSearch` has ten through 2026-10-01. The source's absence or historical “unused” label is not sufficient; legacy indexing provider/caller routing remains unverified. Stripe's obsolete webhook also has historical starts through 2026-10-11.
- Current supported source routes native Stream token minting, opportunity notifications and Spotify artist-link import through Rust; it has no Functions serving SDK/callable/URL. Native artist-link import is not OAuth and cannot prove old consent/refresh callback disconnection. Request-builder tests prove only those specific local request contracts.
- Client free-launch gap found: live native dependencies still use StoreKit and a purchasable subscription view, while the web root loads Stripe's pricing-table script. Disable supported client checkout paths and open free-launch feature access without backfilling entitlements or changing historical provider objects. Provider callback disconnection and live client verification remain required.

## Legacy mail/scheduler queue audit — read-only, 2026-10-14

- `queued_writes` contains **zero documents**, including zero pending future writes. Old schedulers remain paused; no queued scheduled-write payload must be transferred.
- `mail` contains **4,970 records**: 2,507 success, 2,449 error, 10 processing, one pending and three missing known delivery state. All **14 unresolved** records were created in a 27-second burst on **2024-01-02**; they contain six welcome/four sent/four received templates and no saved SMTP acceptance metadata. They were snapshotted privately (0600), not deleted or blindly resent. Unknown historical delivery remains an explicit review gate before any replay/queue retirement; age is not proof of delivery.
- The old extension uses `smtp-relay.gmail.com`; new Rust production transport uses Postmark. Supported application producers no longer use Firestore mail writes, but current booking-template delivery and provider-routing verification remain required before extension retirement.
- A live authenticated orphan-forward probe verified actual Postmark delivery and Slack acceptance, with duplicate HTTP retry producing only one notification email. It is not proof of a real inbound SMTP reply or complete mail-extension parity. Default Python User-Agent was rejected by Cloudflare with 1010; a descriptive authenticated probe User-Agent was accepted. Manual mail tools now identify themselves explicitly; no WAF/authentication policy was weakened.

## Auth webhook transport migration — local implementation, not deployed

- `POST /webhooks/firebase/auth` validates a dedicated `AUTH_WEBHOOK_SECRET` HMAC over `timestamp.raw_body`, constant-time signature comparison, five-minute freshness and bounded payloads. Missing configuration or Postgres failure returns 503, never success.
- The four existing custom Auth exports now come from `auth_hooks.ts`: signup/welcome and delete/founder hooks forward the lifecycle account snapshot and retry failed calls (`failurePolicy: true`). They import no Firestore/provider business modules.
- Rust commits the identity ledger, application cleanup and provider outbox atomically before 204. Account creation time is the incarnation key. Duplicate hooks and reconciliation share outbox keys; stale callbacks/scans cannot resurrect deleted accounts or remove a newer incarnation. Per-identity and profile advisory locks serialize concurrent first delivery and cleanup.
- Local verification: signature/tamper/expiry tests, concurrent signed HTTP requests against real PostGIS, duplicate hook/scanner capture, out-of-order create/delete/recreate, and database-failure retry; Functions forwarding/deployment-boundary tests.
- Rollout remains required: provision the dedicated Secret Manager credential and matching private production environment variable, deploy Rust first, selectively deploy all four approved Auth transports, reconcile previously held jobs against legacy deliveries, then enable Rust Auth effects. Do not release old held welcome jobs blindly or run legacy hooks and enabled Rust effects concurrently. Stream/billing extensions remain separate retirement gates.

## Booking-email parity follow-up — local fix, not deployed

- Compared both deployed compiled handlers with the Rust recipient selector. Preserved their per-role asymmetry: sent checks `booking.addedByUser`, received checks `requestee.addedByUser`. Calendar field presence (including explicit null/empty) suppresses both, as in the deployed handlers.
- Selection is bound to the actual requester/requestee IDs; self-bookings retain both role templates. Missing/unclaimed/deleted/internal recipients are filtered. Real API-mutation tests against PostGIS verify exact destinations/template keys, no import/update/retry replay, and transaction rollback on mail-queue failure.
- Read-only production SQL on 2026-10-14 verified `welcome`, `bookingRequestSent`, `bookingRequestReceived` are provisioned and contain no unresolved template expressions. The external provider outbox has **zero pending jobs** at that check; this point-in-time observation does not replace cutover reconciliation.
- Production has **15,317 future confirmed bookings** before filtering. The read-only eligibility check reduces this to **one booking / two active claimed recipients**, neither with stored device tokens; there are **zero overdue pending bookings**. The existing reminder migration already seeds only eligible future offsets, so no separate bootstrap/backfill tool is needed. Reconcile pending legacy writes before enabling delivery; do not blindly schedule all imported bookings or replay purchase/welcome mail.
- Live booking-template delivery and corrected-selector rollout remain retirement gates.

## Booking reminders and expiry — local implementation, not deployed

- Private `booking_reminders` state schedules one-week/day/hour push reminders for both claimed, active participants. API booking mutations schedule/cancel atomically; date changes invalidate old jobs and delivered keys never replay.
- Migration baselines only future reminder delivery times for existing confirmed bookings. A populated-PostGIS test executes the exact migration SQL and verifies offset/recipient filtering and zero historical activity/provider/founder replay. Delivery rechecks current booking status/date/recipients, then commits the activity, per-device push outbox and completion in one transaction. Failed queue writes roll everything back. Past starts and canceled/deleted/unclaimed recipients do not deliver.
- Rust also preserves the legacy pending-booking expiry rule (>24h past start), under the same booking lock, without replaying historical notifications.
- `BOOKING_REMINDERS_ENABLED=1` enables the API worker after legacy pending-write reconciliation. A read-only production check confirmed all three old schedulers (scheduled writes, search appearances, booking expiry) remain **PAUSED**. No production scheduler or record was changed.
- Scheduling cancels only obsolete jobs. A note-only edit retains valid overdue-but-undelivered reminders while the event is still future; missed day/week offsets are not replayed. Real PostGIS tests cover this regression, retries/parallel delivery, all offsets/recipients, rescheduling/cancellation, rollback/recovery and expiry. Fresh-device FCM and production retirement checks remain required. Reminder email sends were commented out in the legacy handler; this replacement preserves its actual push-only behavior.

## Spotify OAuth — local implementation, not deployed

- Authenticated `POST /app/v1/spotify/oauth/authorize`, `/exchange` and `/refresh` replace the redirect/code-grant/refresh callables. Authorization returns a consent URL using one-time, UID-bound ten-minute state and S256 PKCE; exchange rejects foreign, expired and replayed state.
- Spotify's callback is `https://api.tapped.ai/webhooks/spotify/callback`. The unauthenticated callback only returns a fixed success page, never tokens or token-bearing redirect URLs. Grants/refresh credentials live in private Postgres tables; refresh uses only the signed-in user's stored token and preserves it when Spotify omits a rotated token. Auth deletion clears tokens and pending state atomically.
- Provider failures retain state for retry and return sanitized errors. The real provider's code can still be lost if a token exchange succeeds but the database commit fails; Spotify has no transactional/idempotency contract for authorization codes, so the user must reconnect in that case.
- Real PostGIS tests cover PKCE state, UID binding, concurrent replay, expired state, refresh-token preservation, private serving boundaries and callback/provider failure. Provider dashboard registration of the new redirect URI, real consent/refresh verification and live-caller audit remain retirement gates.

## Stream/Auth profile parity — local fix, not deployed

- Firebase Auth email changes previously updated Postgres without a Stream effect. Hooks and reconciliation now share a transactional normalized-email update which queues `stream_profile` with `created=false` only when an active, claimed profile actually changes. Repeated captures do not enqueue duplicates or replay introductions/welcomes; deleted/unclaimed profiles are not revived.
- Stream signup/delete/profile deliveries now take a separate per-UID transaction-scoped provider lock, read current state after acquiring it, and retain contended jobs for retry. Slow provider calls do not block Auth capture or API profile mutations. This orders completed calls across replicas; it does not provide a cross-provider/database transaction or exactly-once network delivery.
- Fixed a malformed DELETE path (`/users//uid`) whose 404 was previously accepted as success. The regression test fails with the old path. A DELETE 404 now requires a separate authenticated query-users check confirming absence or a matching, valid deletion tombstone; active users, malformed/mismatched results and failed lookups retain the job for retry.
- Real PostGIS and authenticated local HTTP fixtures cover hook/scanner repetition, baseline behavior, inactive profiles, transactional rollback, concurrent profile writes, responsive deletion capture during blocked provider I/O, and seven 404-confirmation scenarios. Latest validation: **66 library tests + 97 API tests passed**, one manual Slack test intentionally ignored; Clippy clean. These are not live Stream evidence. Provider-side profile/welcome-DM/revocation and replacement-only deletion verification remain retirement gates.

## Stream token revocation — local implementation, not deployed

- Authenticated `POST /app/v1/stream-token/revoke` derives the UID exclusively from Firebase Auth and waits for Stream's accepted `revoke_tokens_issued_before` partial user update before acknowledging. Upstream failures return 502, not success.
- Newly minted one-hour Stream tokens include `iat`, so timestamp revocation is enforceable. Deleted Auth identities cannot mint tokens again while an old Firebase ID token is still cryptographically valid.
- Provider-stub and real PostGIS tests cover UID binding, provider failure, issue/expiry timestamps and deleted-identity refusal. Live revocation/profile/welcome-DM verification and managed chat-extension retirement remain gates. Specifically, prove an already-issued token is rejected after revocation **and stays rejected after a subsequent profile upsert**; provider acceptance alone is insufficient. Isolate Rust-only provisioning/deletion from legacy writers, verify current native profile/Auth-email changes and actual welcome-DM receipt/deduplication, and separately verify Firebase signup/delete/hosted email verification through the retained transports.

## Free-launch billing decision

The user explicitly removed billing/customer backfill from scope: the new application launches free. No paid checkout/payment/entitlement API, subscription-email/premium-chat port or billing baseline is required. The exploratory local billing implementation and baseline tooling were removed from the migration stack; no billing migrations were deployed and no provider/source object was mutated. Before retiring Stripe/RevenueCat compatibility Functions and the Stripe extension, disable only the obsolete callback routing/resources, preserving provider data and unrelated cover-art/RevenueCat routes. There is no blanket billing-data or extension cleanup approval.

## BigQuery — retired with explicit user approval

The user explicitly removed BigQuery from scope; there is **no Rust analytics exporter, analytics backfill or warehouse replacement requirement**. The unpublished exporter experiment was discarded, not deployed.

On 2026-10-14 the three `firebase/firestore-bigquery-export@0.1.51` instances (`firestore-bigquery-export`, `-73n7`, `-d85k`) were uninstalled using the Firebase Extensions API. Before deletion, each installed spec was verified to declare **only five Functions**, with no uninstall lifecycle/data-cleanup hook. All-regions Functions inventory confirms **zero BigQuery Functions** and **40 total Functions**. All **16** BigQuery task queues were removed (including four orphan queues from the already-absent `-k4ks` instance); no BigQuery scheduler/Eventarc/Pub/Sub resource remains in the checked region.

The `firestore_export` dataset still contains all six original tables/views. Metadata row counts are unchanged: `prod_users_raw_changelog` **159,501**, `bookings_raw_changelog` **381,400**, `crawler_raw_changelog` **1,191,304**. Source Firestore documents were not deleted; no BigQuery table/view/dataset deletion was requested. Private extension configuration backups remain outside the repository. This retirement does not authorize deletion of archives or unrelated integrations.

## Required remaining work

1. Founder outbox deployment/verification is complete (historical step retained above).
2. Replace Auth side effects with a reliable account-lifecycle source that handles signup/deletion, including admin/provider-created accounts. Bootstrap/baseline existing identities to avoid replaying welcomes. Mailchimp is intentionally retired, not a replacement requirement. Firebase login/verification must remain intact.
3. Verify/implement push delivery and booking email/reminder behavior. Token registration and stored activities are **not** proof of remote push or email delivery.
4. Finish Stream profile/user/token lifecycle and direct Stream/Postmark provider routing. Postmark's unchanged inbound URL/plan is a real removal dependency, not a reason to keep a Function indefinitely; change the provider configuration/plan or choose a supported alternative before deleting its proxy.
5. Retire billing Functions/extensions for the explicitly free launch without backfill, canceling billing objects or reintroducing paid features. Disconnect their obsolete callbacks/resources deliberately; preserve unrelated provider routes and historical provider data.
6. Retire extensions deliberately, including their Pub/Sub/Eventarc/scheduler resources, while preserving source documents and billing/analytics data.
7. Delete bounded batches only after their gates below pass; refresh the all-regions Gen1/Gen2 inventory after each batch. Retain a minimal transport-only Auth package/CI for the four approved hooks; do not delete that deployment source wholesale.

No blanket delete/uninstall command is supplied: some extension uninstall/cleanup paths can affect data, and the inventory alone does not establish safety.

## Every remaining function has a removal gate

| Function | Replacement / deletion gate |
| --- | --- |
| `addUserToMailchimpOnCreated` | **Deleted** with explicit user approval; Mailchimp is no longer used and has no Rust replacement |
| `createConnectedAccount` | Retire for the user-approved free launch; disconnect obsolete callbacks/resources only, with no billing backfill or provider-data deletion |
| `createPaymentIntent` | Retire for the user-approved free launch; disconnect obsolete callbacks/resources only, with no billing backfill or provider-data deletion |
| `createStreamUserOnUserCreated` | Replace/verify Stream profile synchronization from authoritative API profile changes, without Firestore |
| `deleteStreamUser` | **Retain only as thin Auth transport**; selectively deploy forwarding handler after Rust webhook verification |
| `ext-auth-chat-createStreamUser` | Rust token endpoint exists; verify/replace Stream user provisioning, deletion and token revocation before removing Auth hooks/extension |
| `ext-auth-chat-deleteStreamUser` | Rust token endpoint exists; verify/replace Stream user provisioning, deletion and token revocation before removing Auth hooks/extension |
| `ext-auth-chat-getStreamUserToken` | Rust token endpoint exists; verify/replace Stream user provisioning, deletion and token revocation before removing Auth hooks/extension |
| `ext-auth-chat-revokeStreamUserToken` | Rust token endpoint exists; verify/replace Stream user provisioning, deletion and token revocation before removing Auth hooks/extension |
| `ext-firestore-bigquery-export-73n7-fsexportbigquery` | **Deleted** by user-approved BigQuery retirement; extension instance/task queues removed and archive tables/views preserved |
| `ext-firestore-bigquery-export-73n7-fsimportexistingdocs` | **Deleted** by user-approved BigQuery retirement; extension instance/task queues removed and archive tables/views preserved |
| `ext-firestore-bigquery-export-73n7-initBigQuerySync` | **Deleted** by user-approved BigQuery retirement; extension instance/task queues removed and archive tables/views preserved |
| `ext-firestore-bigquery-export-73n7-setupBigQuerySync` | **Deleted** by user-approved BigQuery retirement; extension instance/task queues removed and archive tables/views preserved |
| `ext-firestore-bigquery-export-73n7-syncBigQuery` | **Deleted** by user-approved BigQuery retirement; extension instance/task queues removed and archive tables/views preserved |
| `ext-firestore-bigquery-export-d85k-fsexportbigquery` | **Deleted** by user-approved BigQuery retirement; extension instance/task queues removed and archive tables/views preserved |
| `ext-firestore-bigquery-export-d85k-fsimportexistingdocs` | **Deleted** by user-approved BigQuery retirement; extension instance/task queues removed and archive tables/views preserved |
| `ext-firestore-bigquery-export-d85k-initBigQuerySync` | **Deleted** by user-approved BigQuery retirement; extension instance/task queues removed and archive tables/views preserved |
| `ext-firestore-bigquery-export-d85k-setupBigQuerySync` | **Deleted** by user-approved BigQuery retirement; extension instance/task queues removed and archive tables/views preserved |
| `ext-firestore-bigquery-export-d85k-syncBigQuery` | **Deleted** by user-approved BigQuery retirement; extension instance/task queues removed and archive tables/views preserved |
| `ext-firestore-bigquery-export-fsexportbigquery` | **Deleted** by user-approved BigQuery retirement; extension instance/task queues removed and archive tables/views preserved |
| `ext-firestore-bigquery-export-fsimportexistingdocs` | **Deleted** by user-approved BigQuery retirement; extension instance/task queues removed and archive tables/views preserved |
| `ext-firestore-bigquery-export-initBigQuerySync` | **Deleted** by user-approved BigQuery retirement; extension instance/task queues removed and archive tables/views preserved |
| `ext-firestore-bigquery-export-setupBigQuerySync` | **Deleted** by user-approved BigQuery retirement; extension instance/task queues removed and archive tables/views preserved |
| `ext-firestore-bigquery-export-syncBigQuery` | **Deleted** by user-approved BigQuery retirement; extension instance/task queues removed and archive tables/views preserved |
| `ext-firestore-schedule-writes-deliverWrites` | Keep scheduler paused; preserve/replace any required booking reminders/expiry jobs before extension retirement |
| `ext-firestore-send-email-processQueue` | Verify all email producers moved to Rust mail worker; reconcile pending legacy mail without duplicate delivery |
| `ext-firestore-stripe-payments-createCheckoutSession` | Retire for the user-approved free launch; disconnect obsolete callbacks/resources only, with no billing backfill or provider-data deletion |
| `ext-firestore-stripe-payments-createCustomer` | Retire for the user-approved free launch; disconnect obsolete callbacks/resources only, with no billing backfill or provider-data deletion |
| `ext-firestore-stripe-payments-createPortalLink` | Retire for the user-approved free launch; disconnect obsolete callbacks/resources only, with no billing backfill or provider-data deletion |
| `ext-firestore-stripe-payments-handleWebhookEvents` | Retire for the user-approved free launch; disconnect obsolete callbacks/resources only, with no billing backfill or provider-data deletion |
| `ext-firestore-stripe-payments-onCustomerDataDeleted` | Retire for the user-approved free launch; disconnect obsolete callbacks/resources only, with no billing backfill or provider-data deletion |
| `ext-firestore-stripe-payments-onUserDeleted` | Retire for the user-approved free launch; disconnect obsolete callbacks/resources only, with no billing backfill or provider-data deletion |
| `getAccountById` | Retire for the user-approved free launch; disconnect obsolete callbacks/resources only, with no billing backfill or provider-data deletion |
| `getArtistBySpotifyId` | Rust Spotify lookup routes exist; verify live callers then delete legacy callable |
| `getTopTracksByArtistId` | Rust Spotify lookup routes exist; verify live callers then delete legacy callable |
| `inboundEmailWebhook` | Switch Postmark inbound provider URL/authentication to Rust and verify real replies; old URL currently requires compatibility proxy |
| `notifyFoundersOnAppRemoved` | Legacy analytics removal signal; Android retired/native Firebase Analytics unused, confirm intentional retirement |
| `notifyFoundersOnBookings` | **Deleted** after production Rust/outbox/Slack verification |
| `notifyFoundersOnEmail` | Rust venue outreach/mail persistence exists; verify founder delivery and provider routing before retiring Firestore contact workflow |
| `notifyFoundersOnOpportunityInterest` | **Deleted** after production Rust/outbox/Slack verification |
| `notifyFoundersOnOrphanEmail` | **Live replacement verified**: Rust orphan forwarding, one Postmark Delivered event and Slack acknowledgment under duplicate HTTP retry; eligible for approved bounded retirement |
| `notifyFoundersOnSignUp` | **Retain only as thin Auth transport**; selectively deploy forwarding handler and reconcile held lifecycle effects |
| `notifyFoundersOnUserDelete` | **Retain only as thin Auth transport**; selectively deploy forwarding handler after Rust cleanup verification |
| `notifyFoundersOnUserFeedbackSubmitted` | Recover missing handler behavior or replace founder feedback delivery via the supported feedback/support channel |
| `notifyFoundersOnUserOnboarded` | **Deleted** after production Rust/outbox/Slack verification |
| `notifyFoundersOnVenueContact` | Rust venue outreach/mail persistence exists; verify founder delivery and provider routing before retiring Firestore contact workflow |
| `notifyVenueOfInterestedOpportunities` | Rust venue outreach/mail persistence exists; verify founder delivery and provider routing before retiring Firestore contact workflow |
| `sendBookingRequestReceivedEmailOnBooking` | Preserve booking-request email recipients/templates/filters with durable Rust delivery before retiring |
| `sendBookingRequestSentEmailOnBooking` | Preserve booking-request email recipients/templates/filters with durable Rust delivery before retiring |
| `sendEmailOnSubscriptionExpiration` | Retire for the user-approved free launch; disconnect obsolete callbacks/resources only, with no billing backfill or provider-data deletion |
| `sendEmailOnSubscriptionPurchase` | Retire for the user-approved free launch; disconnect obsolete callbacks/resources only, with no billing backfill or provider-data deletion |
| `sendToDevice` | Verify/implement Rust FCM/APNs delivery from authoritative events; API token registration alone is not push delivery |
| `sendWelcomeEmailOnUserCreated` | **Retain only as thin Auth transport**; selectively deploy forwarding handler and reconcile previously delivered welcomes |
| `setLatestContactRequest` | Rust venue outreach/mail persistence exists; verify founder delivery and provider routing before retiring Firestore contact workflow |
| `spotifyAuthorizeCodeGrant` | Verify/replace OAuth redirect, exchange and refresh routes for every supported client/provider; source-only grep is insufficient |
| `spotifyRedirect` | Verify/replace OAuth redirect, exchange and refresh routes for every supported client/provider; source-only grep is insufficient |
| `spotifyRefreshToken` | Verify/replace OAuth redirect, exchange and refresh routes for every supported client/provider; source-only grep is insufficient |
| `streamBeforeMessageWebhook` | **Deleted** after direct provider routing and signed message verification |
| `transformLocationPayloadForSearch` | Postgres search replaces legacy indexing; 30-day logs show ten execution starts through 2026-10-01, so verify external indexing webhook/caller disconnection rather than assume unused |
| `updateStreamUserOnUserUpdate` | Replace/verify Stream profile synchronization from authoritative API profile changes, without Firestore; `UNKNOWN` state is not disabled (2,365 historical execution starts through 2026-10-10) |

## Completion criteria

- All required business effects execute through Rust/explicitly supported non-Function infrastructure; live end-to-end tests pass.
- Provider callback URLs and supported clients no longer depend on Cloud Functions HTTP endpoints. Only Firebase Auth lifecycle triggers use the retained transport hooks.
- Google Cloud lists **only the explicitly retained transport-only Firebase Auth hooks across all regions**; no non-Auth or managed-extension function remains, and no managed extension can recreate them.
- No orphan trigger/scheduler continues invoking removed handlers or mutating migrated data.
- Firebase Auth/email verification still work; source Firestore archives/documents remain protected.
