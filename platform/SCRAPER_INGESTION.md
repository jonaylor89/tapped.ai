# Scraper observations and private R2 evidence

Crawlers capture immutable observations and unpublished relational event facts in Postgres, with
the raw responses kept as private R2 evidence. Nothing here publishes events, creates artists or
bookings, or emits application effects; publication and resolution are separate, reviewed work.
Neither crawler is scheduled; execution needs owner approval. See [Postgres-first](POSTGRES_FIRST.md)
for roles and builds.

Schema: `20261028000000_scrape_observations.sql` (observations, evidence, current facts),
`20261029000000_scrape_money_cents.sql` (versioned normalization, integer-cent prices) and
`20261030000000_reviewed_venue_resolutions.sql` (operator-reviewed venue decisions). The old
`ingest_scraped_event` / `ingest_unclaimed_artist` functions are retired.

## Model

```text
public response / legacy Firestore snapshot
  -> immutable private R2 object (gzip + checksum)
  -> scrape_objects metadata + immutable scrape_results observation
  -> validated current scraped_events facts + event_performers / event_prices
  -> separately approved resolution/publication (not implemented here)
```

- `scrape_runs`: provider scraper identifier, source, parser version, execution status, optional evidence.
  Scraper IDs are not user IDs. Historical unfinished runs are `interrupted`, not successful.
- `scrape_results`: source-scoped delivery identity, capture time, parser version, evidence pointer and
  optional NDJSON line, validation errors, normalized facts and optional current-event reference.
  `normalization_version`, `input_price_unit` and `normalization_notes` record the interpretation.
  Original v1 payloads remain immutable dollar-major historical records, not current price projections.
  `venue_resolution_id` can reference a separate operator-reviewed capture; it never overwrites the
  original observation/source venue or creates a global profile equivalence.
  Raw run results can be archived with `materialize=false` without duplicating current events.
- `scraped_events`: stable existing IDs, typed dates/status/classification/URLs/title/description,
  nullable venue, original venue identifier, first/last seen, last changed and current observation.
  All captures start unpublished; missing venue references do not manufacture public profiles.
  `payload` remains a **derived compatibility snapshot**, not an independently writable document.
- `event_sources`: provider keys/aliases. Original encoded Firestore keys are preserved. No lossy URL
  cleanup or automatic cross-provider event merging. Explicit aliases attach observations without
  creating duplicate events or automatically overriding the original source's facts. New integrations must distinguish individual
  occurrences, including multiple events on one page; URLs are not universal event identities.
- `event_performers`: ordered original names and optional explicitly verified profile resolution.
  Names alone never create or merge artists. Matching existing resolutions survive lineup refreshes.
- `event_prices`: ordered offers, kind, **bigint `amount_min_cents` / `amount_max_cents`**, `currency='USD'`
  and description. On 2026-10-19 the owner approved treating this historical ingestion's dollar amounts
  as USD. `$1` is `100`; unknown amounts stay `null`, not free. These are not performer fees. Current
  event JSON uses `priceUnit: "usd_cent"` and `amountMinCents` / `amountMaxCents`; old ambiguous major-unit
  keys are not used in current projections. Original v1 observation/evidence values are retained.
- `scrape_venue_resolutions`: operator-only decisions scoped to one source delivery/event and exact
  captured facts. Public-profile identity hashes, evidence, policy and original/preserved venue IDs
  are recorded. Producers cannot approve decisions or write the table. Profile drift, changed facts,
  capture/evidence mismatch or revocation blocks new application; retries remain idempotent.
- `booking_imports`: provenance links to existing bookings. No new bookings, status changes or ID rewrites.
- `scrape_targets`: operator-owned discovery/work configuration, next-fetch time, lease token/expiry,
  attempt count and bounded error summary. `claimTargets` / `finishTarget` use SKIP LOCKED and token
  checks so crashed/stale workers cannot acknowledge another worker's lease.

Only queryable facts/relationships are relational. Original malformed values, embedded private venue
snapshots and provider extensions live in evidence; normalized observations have an explicit whitelist.
Unknown classification/status/end time remains unknown. Negative non-music page classifications can
be retained without invented event dates. Invalid event facts are quarantined, not fabricated.
NUL/unpaired-surrogate text is replaced only in quarantined normalized facts; original values remain
in private evidence so one malformed string cannot abort a whole Postgres batch.
Source-key indexes use fixed-size SHA-256 digests to avoid Postgres btree URL-size limits; original
keys remain stored and compared. Existing `scraped-` event IDs are retained, with the original MD5
formula used only for compatibility when creating new event IDs.

Observation delivery retries are idempotent; reuse with different facts/identity is an error. Distinct
captures remain observable even if extraction output is unchanged; response objects deduplicate by
content. Older captures cannot overwrite newer current facts. At an equal capture timestamp,
normalization v2 supersedes v1; the delivery key breaks ties within one normalization version.
Venue corrections are held for reconciliation, not silently applied.

## Reviewed venue compatibility and routing guards

`approve_scrape_venue_resolution` is operator-only. A decision is bound to one immutable source
capture, its exact facts/evidence, existing event ID, original source venue and preserved event venue.
`withVenueResolution` creates a separate replayable observation; it does not change source identity,
capture time, extracted dates/prices/names, original observations, profiles or native bookings.
Approval pins public-profile identity fingerprints and records policy/evidence. Producers may consume
an exact approved decision but cannot approve, broaden or write decisions. There are no global aliases.

```sh
# Private plan + archive credentials; dry run is default. Only after the new review migration.
cd scripts
npm run crawler:resolve-venues -- --plan /secure/reviewed-captures.json \
  --expect-database restore_check --receipt /secure/new-review-dry-run.json
npm run crawler:resolve-venues -- --plan /secure/reviewed-captures.json \
  --expect-database restore_check --apply --receipt /secure/new-review-apply.json
```

The operator CLI prevalidates/reproduces every planned capture from the same complete R2 snapshot,
then approves/materializes the bounded plan atomically in a serializable transaction. It only adds
exact source-key/venue provenance links for the reviewed events. Replaying the plan and the unchanged
full v2 archive must both be no-ops; old v1/v2 quarantines remain immutable audit history.

For active quarantine counts, exclude a base observation only when a linked reviewed observation
has actually been accepted; an approval alone is not a successful resolution. Do not simply count
all retained `processing_state='quarantined'` rows as unresolved work.

Future crawler routing uses explicit discovery context and a catalog of all known active public
venue websites, not a last-writer-wins domain map or just the selected crawl chunk. Competing profile
IDs on a seed's hostname (including `www` aliases) stop the batch **before fetching**. Paths alone do
not distinguish venue identity. Unique hosts still require a matching configured discovery seed;
cross-host redirects, unknown/unseeded scopes or invalid URLs do not inherit a venue. Reached-but-
unresolved extractions are quarantined with a routing reason. Enqueued links inherit only discovery
scope, not their parent's observed-at timestamp; redirects cannot expand traversal to another host.
These guards do not authorize execution/scheduling or resolve shared-brand event-level ambiguity.

## R2 provisioning (operator action, not performed by code)

Create **two dedicated private buckets**: `tapped-scrape-evidence` for routine public-page captures
and `tapped-scrape-archive` for historical snapshots/manifests containing private venue fields. Do not
use `tapped-media` or its archive. Disable r2.dev/public access, attach no public custom domain, and
configure no browser CORS on either bucket. Use separate bucket-scoped Object Read & Write credentials,
not account-wide/admin/media credentials. Ordinary workers must have no access to the archive bucket.

The crawler requires:

```text
SCRAPE_R2_ACCOUNT_ID=<Cloudflare account ID>
SCRAPE_R2_BUCKET=tapped-scrape-evidence
SCRAPE_R2_ACCESS_KEY_ID=<bucket-scoped credential>
SCRAPE_R2_SECRET_ACCESS_KEY=<bucket-scoped credential>
```

The operator importer instead uses `SCRAPE_R2_ACCOUNT_ID`, `SCRAPE_R2_ARCHIVE_BUCKET`,
`SCRAPE_R2_ARCHIVE_ACCESS_KEY_ID` and `SCRAPE_R2_ARCHIVE_SECRET_ACCESS_KEY` through `r2ArchiveStore`.
There is no fallback from archive credentials to worker/media credentials. Never deploy archive
credentials to scraper workers. Short-lived R2 credentials are supported with the matching optional
`SCRAPE_R2_SESSION_TOKEN` or `SCRAPE_R2_ARCHIVE_SESSION_TOKEN`. They must be separately scoped to the
correct bucket/prefix and expire after use; never copy a parent's secret into worker config. Configure the runtime bucket name too when available so the adapter
can reject accidental bucket reuse.

`INGESTION_DATABASE_URL` is the restricted runtime producer login. `DATABASE_URL` is the operator's
migration connection for the standalone importer. Never reuse API/owner credentials in a crawler.
No credentials are baked into images, committed, logged, or read from the public-media configuration.

Objects are bounded to 32 MiB uncompressed and gzip-compressed deterministically. These prefixes
live in their respective isolated buckets:

```text
archive/{sha256-prefix}/{sha256-of-stored-bytes}.gz   historical source + import manifests
evidence/{sha256-prefix}/{sha256-of-stored-bytes}.gz  routine captures
```

The adapter uses the [R2-supported S3 operations](https://developers.cloudflare.com/r2/api/s3/api/):
Content-MD5 for transport integrity and atomic conditional create, then verifies HEAD
size, encoding, MIME type and SHA-256 metadata. ETag is not treated as a checksum. Postgres receives
an object reference **only after upload verification**. A failed database transaction can leave an
unreferenced upload; retrying reuses the same object. No cross-store transaction is claimed.

Default retention is conservative: **no automatic deletion**. Never expire `archive/` as routine cache.
Choose routine-evidence retention explicitly before introducing lifecycle rules, including how expired
references are represented. An operator orphan sweep may compare R2 inventory with `scrape_objects`
after a generous grace period; registry-only archive/manifest objects are intentional, not orphans.
Do not delete merely because an object has no `scrape_results` reference. No deletion/sweeper runs here.

Diagnostic downloads use the adapter's signed URLs (60-second default, 300-second maximum), forced
attachment/octet-stream. Never render captured HTML inline or expose it through the public media host.

## Shared producer contract

`packages/postgres-ingestion` exports `captureObservations`, `recordObservations`, normalization,
R2 adapter, and target lease helpers. `captureObservations` accepts 1–500 extraction envelopes and
one evidence buffer/object. Include a stable source-scoped delivery ID, actual capture time, parser
version, source key, optional run/venue, and original extraction. A batch object's `evidenceLine`
identifies the extraction's 1-based NDJSON line when applicable. Partial/failed extraction can still
be captured and quarantined. Do not put request credentials/cookies in evidence from public scrapes.

Event crawler handlers now persist response bytes plus original extraction immediately, without
buffering a whole run or copying venue profiles. Persistence errors are retried by Crawlee. Fetch
concurrency is bounded and same-domain requests throttled. Database connections are independently
bounded. Recent-source lookups use indexed source-aware point queries (six-hour freshness), not a
full processed-URL preload or a permanent blacklist. A separately approved scheduler should tune
refresh/backoff by source, classification, and event age using `scrape_targets`; no scheduler is enabled.
Compatibility legacy scraper wrappers also capture observations, using durable run-start timestamps.
Ticket discovery still only discovers pages: implementing its event extraction/output is separate work.

No blanket JSON GIN indexes, partitioning, broker, or second database is introduced. Measure queue
age, capture throughput/bytes, retry rate, quarantine reasons, unresolved venues, and query latency.
Partition/expire observation history when measured retention/volume warrants it, not current events.

## Normalization v2

Blank artist strings are omitted, `N/A`-style optional URLs become `null`, and dollar amounts are
stored as USD integer cents. Names are never inferred, split or truncated; dates, malformed URLs,
unsupported prices and venue conflicts are held rather than guessed.

`withFormattingV2(input, "usd_major")` establishes a new delivery identity/parser version while keeping
the original source key, capture time, run/venue and evidence. `normalizeObservation` applies cleanup
and exact decimal conversion once. Explicit `usd_cent` inputs are supported without multiplying again;
mis-tagged or mixed-unit inputs fail closed. Fractional cents are quarantined, never silently rounded.
USD is assumed only for missing currency; explicit non-USD currency is held, not relabeled.

## Legacy Firestore data

The legacy `crawler` and `rawScrapeData` collections (547,142 documents) were imported on 2026-10-21
from an immutable snapshot in the private `tapped-scrape-archive` bucket, using normalization v2 and
USD-cent prices. Firestore has since been deleted; the originals live in that R2 snapshot (plus an
offline ZIP copy). Replays use the same artifact and are idempotent, but a full replay would re-create
the non-music events removed on 2026-10-26 (below):

```sh
pnpm --filter @tapped/postgres-ingestion build
cd scripts && npm ci
# Dry run is the default. Apply requires --apply, a fresh backup and a new receipt filename.
npm run crawler:import-r2 -- --dry-run --expect-database <db> \
  --manifest-ref /secure/complete.ndjson.r2.json \
  --normalization-version 2 --input-price-unit usd_major
```

Held (quarantined) observations keep their original facts and evidence. They were reviewed and
deliberately left unresolved: reversed time ranges, invalid flier/event URLs, invalid prices and
lineups, and **7,390 venue conflicts**. The conflicts are 19 profile pairs that share a website but
are different venues, rooms or branches (for example Lincoln Hall/Schubas Tavern, the two Rock 'n' Bowl
locations, The Hi-Fi/HI-FI Annex). Shared domains, addresses or place IDs do not prove venue identity,
so original event and booking venue references are unchanged. Resolve them only with event-level
evidence via `crawler:resolve-venues` below; never with a global alias or profile merge.

On 2026-10-26 the owner removed non-music events except comedy, open mic, theatre and dance (91,789
events with their observations, performers and prices; events linked to bookings or venue decisions
were kept), and assigned the 48 venue-less Flash DC events and the 436 Jungle Room RVA run results to
their venue profiles. A full pre-change dump is under `/root/scrape-cutover-backups/` on the server.

## Tests

```sh
pnpm --filter @tapped/postgres-ingestion test
# Dedicated LOCAL PostGIS test instance; test creates/drops only a fresh random test DB.
INGESTION_TEST_DATABASE_URL=postgres://...@127.0.0.1:5432/test \
  pnpm --filter @tapped/postgres-ingestion test
```
