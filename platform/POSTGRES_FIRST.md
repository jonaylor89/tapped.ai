# Postgres-first models and ingestion

## Contract

Postgres owns application facts. Firebase is Auth only (media is in R2; see [Media storage](MEDIA.md)); the two Auth hooks are transports to Rust. StoreKit is unchanged. There is no serving Firestore fallback, synchronization, dual write, secondary search index, or application code on Cloudflare.

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

Event crawler (including supported legacy scrapers) and ticket crawler use `@tapped/postgres-ingestion`. Mandatory `INGESTION_DATABASE_URL`; never reuse the owner/API credential. Missing configuration fails, with no Firebase fallback. Crawlers upload no public media and have no Firebase Auth/Firestore/FCM/Storage client. Private source evidence is uploaded to a separate R2 bucket; see [scraper observations and migration](SCRAPER_INGESTION.md).

After migration `20261028000000`, producers record immutable observations and validated unpublished relational event facts through `record_scrape_observations`. Private R2 evidence is verified before database references are committed. The old side-effecting `ingest_scraped_event` and `ingest_unclaimed_artist` functions are retired. Capturing a source event never creates/cancels bookings, creates artists, or emits application effects. Resolution/publication/booking reconciliation is separately reviewed work, not part of capture. `booking_imports` retains historical provenance. Ticket/door offers preserve unknown currencies and are not performer fees.

Provision a separate LOGIN role outside source control, then grant membership in `tapped_ingestion`. For example, inside an administrative psql session:

```sql
CREATE ROLE tapped_crawler LOGIN;
\password tapped_crawler
GRANT tapped_ingestion TO tapped_crawler;
```

Restrict network access to the private Hetzner/Tailscale network and the database's pg_hba rules. The producer role can read sanitized ingestion profiles/source events, manage scrape runs, claim leased targets, and execute evidence-registration/observation functions. It cannot directly rewrite observations or publish events. It cannot write profiles directly, access accounts/private archives, or create ownership/notifications. Never grant it the API owner role. Provisioning/login secrets are intentionally not committed or automated here.

Build from monorepo root, with exact pnpm lockfile:

```sh
corepack pnpm install --frozen-lockfile
corepack pnpm --filter @tapped/postgres-ingestion build
corepack pnpm --filter node-webcrawler build
corepack pnpm --filter ticket-crawler build
docker build -f services/event-crawler/Dockerfile .
docker build -f services/ticket-crawler/Dockerfile .
```

Neither crawler is scheduled or authorized to run; future execution needs owner approval.
