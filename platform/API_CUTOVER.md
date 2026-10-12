# API-only cutover (2026-10-11)

## Serving contract

Rust serves users, nested/root services, bookings, activities, opportunities/interests,
reviews and hashed API-key validation from Postgres. Firebase Auth remains the identity provider.
Production refuses boot without DATABASE_URL and REDIS_URL; no Firestore serving implementation remains.
Public profile responses are sanitized. Private reads/writes use Firebase identity and ownership checks.
Places uses Redis keys places:details:{place_id}, JSON, TTL 7,776,000 seconds.
Postgres and Redis are internal only. No client connects to Postgres.

Web public data reads use /app/v1 public projections. Native live database/token registration uses
Firebase-authenticated API calls. Search (text/typo, filters, radius and bounding box) reads current
Postgres rows through Rust too, so creates and edits are immediately searchable without index sync.
Neither client needs a Typesense/search key.
Native observers poll every 30 seconds with bounded buffering and cancellation.

Explicitly disabled/unmigrated: badges, curated leaderboards, premium waitlist, historical contact flags,
in-app blocking/reporting (contact support@tapped.ai). Opportunity quota billing is disabled (unmetered
applications); feeds are computed, not copied into Firestore. No legacy fallback for these features.

## Archive and import verification

Root-only services imports were incomplete: 7,705 userServices documents were also migrated.
Review ids are not globally unique: 59 id/group keys are repeated under different reviewees, and 118
stored participant ids disagree with the collection path. Identity is (id, type, reviewee_id); the
reviewee path and collection group are authoritative. Raw source values remain in the archives.

Root-only imported service container records are preserved but do not appear in owner service lists.
31 invalid booking locations remain in JSONB; their serving geography/location is null.

Nine ZIP archives with lossless tagged values (nanosecond timestamps, references, geopoints, bytes),
document paths, nested migrated groups, counts and SHA-256 manifests:
  /opt/tapped/firestore-archives/20261010-pre-cutover/

ZIP CRCs, manifest hashes, ZIP hashes and counts were verified; directory 0700, files 0600.
Archives are intentionally not committed. These contain credentials/PII: move only through secure storage.
Only migrated nested groups are included, not unrelated/unmigrated subcollections.

Final imported counts:
- users: 118,097
- services: 7,710 (5 root + 7,705 nested)
- bookings: 371,500
- activities: 67,539
- opportunities: 1,458; interests: 2,862
- reviews: 12,926 (6,521 performer + 6,405 booker)
- device tokens: 1,039 unique
- API-key hashes: 2
- Redis seed: 5,478 Places entries

Import scripts are one-time administrative tools, never ongoing synchronization.
--replace-reviews was used before API writes were opened to repair previous lossy imports.
Never run it against a serving database.

## Retired legacy writers

Schedulers paused: booking expiry, sendSearchAppearances, Firebase scheduled queued writes.
Cloud Functions retired: addInterestedUserOnApplyToOpportunity, copyOpportunityToFeedsOnCreate,
createBookingOnEventCrawled, createDefaultServicesOnUserCreated, createOpportunityFeedOnUserCreated,
incrementReviewCountOnBookerReview, incrementReviewCountOnPerformerReview,
incrementServiceCountOnBooking, onUserDeleted, getPlaceById, getPlaceIdByLatLng,
cancelBookingIfExpired.

No Firestore documents/collections were deleted. platform/firestore.rules is the client-access
shutdown rule. Rules do not block Admin SDKs, so administrative writers must also remain retired.
API containers no longer mount Firebase admin credentials. Deployment refuses rollback to a
legacy Firestore-serving image; failures must roll forward or use a Postgres-compatible image.

Deny-all client rules deployed and verified:
projects/in-the-loop-306520/rulesets/267a6f32-3751-4aac-9396-65b9495e3aaa.
Authenticated production probes verified imported reads, owned writes reflected directly in Postgres,
cross-user write denial, sanitized profiles/bookings, both review types, opportunities/interests,
device tokens, absence of dual writes, and Firestore client HTTP 403. Probe data/identities were removed.
Pre-cutover rules were backed up alongside the ZIPs.

The committed native Firebase identity key had been deleted, breaking sign-in. It was restricted
BEFORE restoration to Firebase identity/messaging/configuration/telemetry APIs only; Places and Firestore
are excluded. No new credential was committed. The temporary identity-only administrative probe key is removed after verification.
The original committed native identity configuration was verified against live Firebase Auth; no
client-side Places or privileged Rust API key is needed.

Vercel automatically deploys pushes to main. Node CI success alone is not deployment verification;
check the live website rather than treating missing local Vercel credentials as a blocker.
Live web venue search was verified to return the same IDs as Postgres, with private fields absent. The legacy client Typesense search key was revoked (old clients may fail); key metadata
was backed up alongside the ZIPs. New clients require no index key.

Final production verification after deployment d7bd63cb6be7:
- Postgres serving projections/search, Redis and mail-store readiness: healthy.
- Authenticated HTTP create/update/read, direct SQL reflection, cross-user denial and no dual writes.
- Reviews update nullable booker profiles correctly; clearing a profile section cannot erase ratings.
- New writes appear in Postgres search immediately; public results omit private fields.
- Authenticated responses are no-store; Firestore client requests are HTTP 403.
- Redis-only Places reads verified with a short-lived synthetic entry, removed afterwards.
- Two imported non-finite rating strings normalize to null in the view; raw JSONB remains unchanged.
- Nine archive SHA-256 checks reverified. Administrative staging and the temporary PostGIS container
  and credential env files were removed. The canonical admin credential remains root-owned 0600,
  unmounted from API containers.
- Rust 50 unit + 64 API tests, web production build, native app build and 83 TappedData tests passed;
  Rust, Node and native simulator CI passed. App Store distribution remains separate.

## Post-cutover QA follow-up (2026-10-11)

- Email verification failure reproduced in Chrome: generated Firebase email links selected the public
  Maps Embed key (UID `27fa8e80-c627-4fd7-b698-cb6eabb8e967`), which rejected the hosted auth referrer.
  Its restrictions now allow only Maps Embed, Identity Toolkit and Secure Token, with the exact
  `https://in-the-loop-306520.firebaseapp.com/*` referrer added. No Places, Geocoding, Gemini or
  Firestore access was enabled. An unchanged generated link verified a fresh account through the
  hosted page; all temporary identities were deleted. Previous restrictions are backed up privately
  at `/opt/tapped/security-backups/20261011T115307Z-firebase-email-key/before.json` (root, 0600).
- 9,015 obsolete follow notifications were deleted from Postgres, with other type counts unchanged.
  A private, checksum-verified recovery snapshot is retained under
  `/opt/tapped/postgres-maintenance/20261011T105754Z-remove-follow-notifications/`.
- Code fixes (production rollout must be verified separately): cancellable 30-second session-profile refresh,
  fresh Settings loads that preserve unsaved edits, no-store auth failures and public opportunity
  responses, fresh web opportunity reads/404 handling, deterministic initial responsive layout,
  and accessible dialog titles/descriptions. Closed map sidebars no longer eagerly fetch profiles.
- Verification: 204 native app tests passed; 50 Rust library and 66 API tests passed (database-backed
  cases require DATABASE_URL and are not evidence of production rollout). Web typecheck/build and
  seven helper tests passed. A production-mode web preview rendered 250 markers with no hydration
  errors, dialog warnings or API errors; the search dialog had an accessible title and description.
  A missing opportunity page returned HTTP 404.
- Email-verification enforcement policy is unchanged pending a product decision. Native new-account
  onboarding gates on verification, but API writes currently do not; existing native profiles also
  bypass the onboarding verification gate.
- Still not signed off: full gigs swipe/apply UI, premium chat send/receive, real push delivery,
  Spotify linking, in-app account deletion, every web filter and signed-in web flows. Remaining
  Admin SDK webhooks/background writers need a separate retirement audit.

## Confirmed live QA remediation (local changes, not deployed)

- Reproduced area-sheet fan-out in production: an NYC viewport issued 172 profile responses
  (104 HTTP 200, 68 HTTP 429). The old effect requests every ID occurrence concurrently and
  deduplicates only afterwards. The replacement uses explicit-ID Postgres reads at
  `/app/v1/public/data/users?ids=...`, capped at 50 IDs per request, serial client batches,
  deduplication before requests, the existing short-lived profile cache, stable ID-set effect
  dependencies and AbortController cleanup. Missing/deleted profiles are omitted; errors are
  visible instead of silently representing the area as empty. Existing rate limits are unchanged.
  Batches always use the public-profile allowlist, including authenticated callers' own IDs;
  unfiltered user enumeration remains forbidden. OpenAPI is updated.
- imgproxy logs match the reported 25 HTTP 503 images: 64 requests started at 13:10:32 and
  25 reached the ten-second request timeout at 13:10:42. The two-worker proxy drained the
  earlier requests before the queued tail timed out. A failed image's original Storage object
  was still HTTP 200. Map thumbnails now share a four-slot client queue with unmount/load/error
  cleanup and an accessible failure placeholder. No proxy timeout, source allowlist or server
  resource limit was relaxed. Other clients/concurrent traffic can still cause upstream errors;
  production image behavior must be rechecked after rollout.
- The first six `/u/johannes` booking IDs are real, public confirmed bookings (API HTTP 200).
  Their `/booking/:id` links targeted a nonexistent Next.js route, not missing database records.
  Added a public performance-detail route with no-store reads, real notFound handling, explicit
  public fields and safe http(s) event links. Local production preview returns HTTP 200 for a
  known booking and HTTP 404 for a nonexistent one; pending/canceled bookings stay unavailable.
- Chrome reproduced three simultaneous Search Tapped dialogs on `/search`, with the focused
  input inside an aria-hidden dialog. Search now has one root-level modal/shortcut owner,
  explicit idempotent open/close state (not persisted), close-on-selection and focus restoration
  to the opener unless another modal has opened. Titles/ARIA are retained, not suppressed.
- Account deletion previously soft-deleted only the user while leaving the three API-created
  onboarding services active; the retired Firebase deletion trigger no longer cleans these up.
  Postgres now soft-deletes all owned default/custom/imported services in the same transaction.
  Service writes share the owner lock and require an active owner, preventing late/concurrent
  retries from leaving or recreating orphans. Another owner's services and historical bookings
  remain untouched. This is application-data cleanup, not Firebase Auth deletion or hard erasure.
- Local validation: 20 web helper/regression tests, typecheck and production build; optional
  `pnpm test:browser` checks real Chrome focus, slash/Escape, a closed sheet making no profile
  reads, 500 ID occurrences reduced to three batches (145 unique profiles), and 250 thumbnails
  with at most four concurrent requests. Browser API/image/Mapbox fixtures are not live API proof.
  Rust: 51 library + 66 API tests, clippy and formatting passed, with DATABASE_URL set to an
  isolated local PostGIS database so database-backed assertions actually ran. Those include
  public/authenticated batch privacy, omitted deleted profiles, default/custom-service cleanup,
  another owner's services, deletion retries and concurrent/late service creation. No new native
  code was changed; prior main's Node/Rust/iOS CI and API deploy all succeeded, and live readiness
  reports Postgres/search/Redis/mail-store healthy.
- Rollout: these fixes are local jj changes, not pushed or deployed. Deploy the batch-capable
  API **before** the web frontend uses it; the old API intentionally rejects user collection
  reads without this explicit-ID support. Verify live batch counts/privacy, image behavior,
  booking routes, focus and a disposable account's service cleanup after deployment. Keep the
  user's local `.gitignore` change out of published commits.
- Approval/identity blockers: the orphaned Firebase Auth UID/email was not recoverable from
  the available local history; require the exact identity and read-only confirmation before
  deletion. No Auth account was deleted. The macOS blueprint remains unapproved/unimplemented.
  Verified-email enforcement remains unchanged. Product options: keep current onboarding-only
  verification (least friction, unverified API writes remain possible), gate authenticated writes
  only (reduce abuse while preserving public browsing; needs resend/recovery UX and a migration
  decision for existing users), or gate all authenticated reads/writes (strictest but may lock out
  existing clients/users). Do not conflate any of these with the Postgres migration.

## Bundled map and client prefetching (implementation; rollout below)

This supersedes opening-triggered area-sheet batches above: public map/profile data is fetched
before interaction, rather than minimizing reads by waiting for a sheet to open.

- `/app/v1/public/map` returns up to 250 venues, 1,000 deduplicated referenced public profiles
  (first 20 references per venue), genre counts and truncation flags in **one SQL statement**.
  Bounds are required, finite, nonempty and support the date line. Migration
  `20261015000000_map_viewport_index.sql` adds the matching partial geometry GiST index;
  the existing geography/radius index remains. Profiles use the existing public allowlist.
- `/app/v1/public/users/:id/details` is also one SQL statement: a public user, confirmed incoming
  count, deduplicated confirmed history (up to 40 per role), latest public performer-review
  summary, and up to 200 explicitly referenced public profiles (history/reviewer/top 20 performers).
  Deleted/banned users return 404. Private user fields, booking notes/financial/service fields,
  and imported review extension fields are excluded. Both new endpoints send `no-store`.
- Shared client public-profile cache: at most 2,000 entries, ID/case-insensitive username aliases,
  60-second freshness and five-minute retention. Older writes cannot undo a newer missing-profile
  result or steal a reassigned username. Full details have a separate 100-entry metadata cache
  (30 seconds fresh, five minutes retained); related users seed the normalized cache, not duplicate
  arrays in every details entry. Missing referenced profiles are negatively cached.
- Map reads wait for actual bounds and use load/moveend/resize, not render events or an initial
  unbounded search. Superseded reads are cancelled. Eight viewport snapshots are retained for
  five minutes (30 seconds fresh). Complete outer results can answer nearby pans immediately;
  capped outer results cannot pretend to cover a smaller viewport. Previous markers/sidebar
  data remain during navigation and failed refreshes. Opening the area sheet performs no reads.
- Idle prefetch adds a 15% viewport margin after 750ms, at most six speculative map reads/minute.
  Tiny pans inside a still-warm margin do not refetch another buffer. Hover/focus has a 250ms
  dwell, one active details request, one latest waiting intent and eight attempts/minute. Opening
  joins an in-flight prefetch, shows the cached public user immediately and refreshes by ID;
  fresh 404s clear the preview. Hidden tabs, save-data and 2G/3G connections skip speculative work.
  Authenticated/private reads and action eligibility are not served from these public caches.
- Markers, area chips/cards, selected profiles, reviews and booking previews share four remote
  image slots. Visible selected content takes priority over queued markers; offscreen content
  waits for intersection. Native preloads keep their slot until completion even after UI unmount,
  because removing an img element does not necessarily cancel its network request. Server proxy
  workers/timeouts/source allowlists and API rate limits are unchanged.
- Local verification: 39 web tests, typecheck/build; 52 Rust library + 70 API tests with an isolated
  PostGIS DATABASE_URL, formatting and clippy. Chrome fixture suite checks one initial map bundle
  plus one idle buffer, no extra reads on nearby pan/area opening, cached profile rendering while
  details are held, reviewer/top-performer cache reuse, fresh 404 invalidation, save-data guards,
  outage retention, dialog focus, and 250 thumbnails with at most four concurrent requests.
  Synthetic EXPLAIN ANALYZE (100,000 distant venues, 300 NYC venues, 1,000 performers; transaction
  rolled back) used `users_map_location_idx`: 36.5ms execution and 15.0ms planning for the capped
  250-venue/1,000-profile payload. This is a local measurement, not a production latency claim.
- Rollout (2026-10-12): API was deployed first through GHA run `38247149867`, then main was
  published at `4a51eff39833` (Node/Rust CI succeeded; main API deploy run `38248106655` succeeded).
  Live readiness is healthy. NYC map response: 250 venues/171 deduplicated public profiles;
  live details sample: 40 confirmed bookings/44 related public profiles. Both returned no-store
  and passed public-field checks. Web deployment is now handled by manual `Deploy Web` GHA:
  exact checked-out files, successful Node CI required, API capability check, and live commit
  verification. Vercel Git branch lookup is currently broken; no automatic rollout is assumed.
  Production browser/image behavior must still be checked after the web run. Firebase Auth,
  deny-all Firestore rules and separate identity/macOS/verified-email decisions are unchanged.

## Firebase Functions retirement

Target: zero custom and extension-managed Functions while retaining Firebase Auth/email verification.
The founder booking/application/onboarding notification gap is addressed by a local transactional
Postgres outbox and retrying Rust worker; code rollout and live API-action validation are pending.
A labelled real Slack smoke test passed, and production Slack configuration is staged privately.
No functions or source Firestore data were deleted. Remaining Auth, email/push, provider, billing
and extension dependencies are tracked in [FIREBASE_FUNCTIONS_RETIREMENT.md](FIREBASE_FUNCTIONS_RETIREMENT.md).

## Native distribution

A simulator build is not an App Store release. Archive/sign/upload the native app and release it
through App Store Connect separately. Older Flutter/Firestore clients are intentionally unsupported.
