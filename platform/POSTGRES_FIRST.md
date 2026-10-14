# Postgres-first models and ingestion

## Contract

Postgres owns application facts. Firebase is Auth/Storage only; the two Auth hooks are transports to Rust. StoreKit is unchanged. There is no serving Firestore fallback, synchronization, dual write, secondary search index, or application code on Cloudflare.

`users` retains public profile IDs for client compatibility. `accounts` represents authenticated identities; `profile_owners` records ownership. Imported/unclaimed artists and hidden historical-reference stubs never create Firebase accounts, owners, welcome messages or notifications. Current profile creation remains the authenticated UID's primary profile; additional ownership/claims require a separately verified workflow, not an unauthenticated claim-by-name endpoint.

Queryable performer/venue fields are columns with search indexes, not authoritative JSON copies. The remaining JSON holds extensions and legacy client compatibility. New API writes strip canonical scalar fields from extension JSON; role normalization strips promoted fields and counters. `legacy_profile_archive` and `legacy_invalid_records` preserve migration provenance privately. Orphan references become deleted/unclaimed stubs; invalid booking statuses/ranges are archived and made unschedulable. These are not published profiles or Auth identities.

Foreign keys constrain participants, services, reviews, activities, opportunities and ownership. Device tokens/API keys reference accounts rather than requiring a public profile. Legacy account-only references are disabled until reconciled with Auth. Account deletion removes ownership and disables writes; authenticated requests do not reactivate tombstones.

## Derived read models

- `profile_stats`: confirmed received bookings (including future), completed bookings (confirmed with `end_time <= now()`), review counts and mean ratings by role.
- One canonical review per booking/role. Historical duplicates remain in `reviews` with `legacy_duplicate`, excluded from canonical views/statistics.
- `api_services.count`: confirmed bookings referencing that service. The old physical `services.count` is retained only for historical import compatibility; API writes ignore it.
- Venue rankings: five visible performers ranked by confirmed booking count, deterministic ID tie-break. Booking-day histogram: Sunday–Saturday, UTC, confirmed bookings with known starts.
- `api_users` exposes familiar read-only counter/ranking fields. Native profile writes omit them; legacy writes cannot make them authoritative.

All projections rebuild from facts. No client-maintained counters or aggregate caches. Search selects bounded ranked IDs before hydrating aggregate projections. Start with these indexed queries; measure before adding an aggregate cache/materialized view.

## Writes and search

Authenticated `/app/v1` commands: `POST /profiles`, `PUT /profiles/{id}`, `POST /bookings`, `PUT /bookings/{id}`, `POST /bookings/{id}/accept`, `/cancel`, `/reschedule`, `POST /reviews`. Acceptance/cancellation may carry fact edits in the same atomic transaction. Edit cannot change status; reschedule accepts only start/end. Existing collection routes are compatibility adapters to the same authorization/transaction logic, not arbitrary SQL/document writes. Native primary profile/booking/review writes use commands.

Public `GET /app/v1/public/profiles/{id}/stats` exposes current computed statistics. Existing public profile/map bundles use the same canonical projections. Search is Postgres/PostGIS/pg_trgm; web `src/data/search.ts` calls Rust. No Typesense runtime/key/indexing pipeline is required.

## Crawlers

Event crawler (including supported legacy scrapers) and ticket crawler use `@tapped/postgres-ingestion`. Mandatory `INGESTION_DATABASE_URL`; never reuse the owner/API credential. Missing configuration fails, with no Firebase fallback. Google Cloud Storage uploads use ADC (`GOOGLE_APPLICATION_CREDENTIALS` mounted at runtime), with Storage-only permissions; no Auth/Firestore/FCM client.

`ingest_scraped_event` atomically captures public event facts/revisions, deterministic imported bookings and unclaimed artists. Retry is idempotent; corrections cancel removed/non-music relationships and update current facts. `booking_imports` relates bookings to source events, separate from private accounts. Colliding native booking IDs fail rather than overwrite native facts. No business-effect outbox is written. Ticket/door prices are retained as event provenance, not confused with performer fees.

Provision a separate LOGIN role outside source control, then grant membership in `tapped_ingestion`. For example, inside an administrative psql session:

```sql
CREATE ROLE tapped_crawler LOGIN;
\password tapped_crawler
GRANT tapped_ingestion TO tapped_crawler;
```

Restrict network access to the private Hetzner/Tailscale network and the database's pg_hba rules. The producer role can read sanitized ingestion profiles/source events, manage scrape runs/results, and execute ingestion functions. It cannot write profiles directly, access accounts/private archives, or create ownership/notifications. Never grant it the API owner role. Provisioning/login secrets are intentionally not committed or automated here.

Build from monorepo root, with exact pnpm lockfile:

```sh
corepack pnpm install --frozen-lockfile
corepack pnpm --filter @tapped/postgres-ingestion build
corepack pnpm --filter node-webcrawler build
corepack pnpm --filter ticket-crawler build
docker build -f services/event-crawler/Dockerfile .
docker build -f services/ticket-crawler/Dockerfile .
```

Old Firestore migration scripts are historical, non-runtime source under `services/event-crawler/archive/firestore-migrations`; do not run them against production. Existing source Firestore/provider archives are not deleted or replayed.

## Production rollout

Deployed 2026-10-14: API/identity/mail image `f0a96e4bed95f2bff27a67c5d66f7907d35fe8e1` (workflow `38624411904`), website revision `7b6574bd2ecafe75f0e2ff279d4daec9a0c35c3f` via local `vercel deploy --target production`, and native iOS release archive uploaded successfully to App Store Connect (Apple processing pending at upload completion). The native upload is not an App Store public release.

Production backup restored and both migrations rehearsed against all imported data before rollout. Private archives contain 118,104 original profiles and 14,629 invalid-record snapshots; all 12,927 reviews remain, with 118 legacy duplicates excluded from read models. All constraints validate. Fresh synthetic Auth/signup/profile/Stream revocation/hosted-verification/deletion checks passed; zero pending external effects. Public normalized search/statistics and API readiness passed.

Typesense container, search tunnel ingress/DNS and obsolete environment entries were removed. Historical index files remain. No application code was deployed to Cloudflare; Postmark and StoreKit were untouched.

**Owner deployment scope is iOS, website and API only. Neither event nor ticket crawler was run or scheduled.** Image preparation is not execution. The unused crawler runtime configuration/credentials were moved to private backup; its Postgres login and Storage service account are disabled. Future crawler execution requires new owner approval. The 157,120 processed-URL baseline records derive only from existing Postgres booking provenance; no sites were crawled, no original booking IDs were rewritten, and no notifications were replayed.

Historical rollout procedure (crawler execution is NOT approved):

1. Back up Postgres and test restore. Pause crawler producers and identity worker; keep writes quiescent while applying `20261024000000` and `20261024010000`. These migrations preserve source/provenance and do not replay historical effects. Do not rerun the old Firestore import after canonical cutover.
2. Deploy the matching Rust image and restart the identity worker, then check readiness, counts, normalized filters, visibility and disabled-account behavior. Do not roll an old identity worker back across this boundary without reconciling account state.
3. Only after separate owner approval: provision restricted crawler credentials/Storage ADC and validate producer deduplication before executing any job. Do not resume/start either crawler as part of the app/website/API deployment.
4. Apply updated Compose. Explicitly stop/remove the old Typesense container and remove its tunnel ingress/DNS route in the infrastructure configuration. Preserve `/opt/typesense/data`, source Firestore and analytics/billing archives. Removing the service from Compose alone does not stop an orphaned running container. No blanket `--remove-orphans` or volume deletion.
5. Remove obsolete Typesense environment entries after their consumers are confirmed absent. Never print credentials. Postmark remains owner-managed and is untouched.

Private recovery checkpoints remain under `/root/postgres-first-backup/`. App Store Connect processing/TestFlight availability and App Store publication must be verified separately; successful upload alone does not establish them.
