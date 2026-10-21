# Scraper observations and private R2 evidence

**Production cutover passed on 2026-10-21.** Migrations 28–30, the complete R2-only v2 import and 959
reviewed captures are applied. There are 333,933 exact booking links; original IDs/native data are
preserved and both replays were no-ops. See the [production checkpoint](SCRAPER_PRODUCTION_CUTOVER.md)
for verified results, bounded-link recovery and the minimum runtime migration-ledger requirement.
Events remain unpublished; this cutover did not enable crawlers or delete Firestore.

## Scope and safety

Migration `20261028000000_scrape_observations.sql` prepares the Postgres data model.
`20261029000000_scrape_money_cents.sql` adds versioned normalization and integer-cent prices.
`20261030000000_reviewed_venue_resolutions.sql` permits privileged, event/capture-scoped compatibility
reviews without global profile aliases or venue remaps. These migrations do not run scrapers,
provision credentials/buckets, publish events, create artists/bookings,
replay effects, or delete Firestore. Apply them only through the backed-up/rehearsed migration rollout.
Crawler execution remains separately owner-approved. See [Postgres-first](POSTGRES_FIRST.md).

The old `ingest_scraped_event` / `ingest_unclaimed_artist` functions are retired (including owner
calls); their producer permissions are revoked. Publication/artist resolution/booking reconciliation
must be a separate reviewed implementation. This release deliberately has **no automatic publisher**.
The native app continues to read existing bookings; capturing a new event alone does not publish it.

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
correct bucket/prefix and expire after the rehearsal; never copy a parent's secret into worker config. Configure the runtime bucket name too when available so the adapter
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

## Firestore import rehearsal

Build from the root, then install the standalone operator scripts with their own lockfile:

```sh
pnpm install --frozen-lockfile
pnpm --filter @tapped/postgres-ingestion build
(cd scripts && npm ci)
```

Restore production Postgres into an isolated database and apply the new migration there first. Keep
Firestore producers stopped for a stable snapshot. Use read-only Firestore ADC for the explicit project;
never use the legacy embedded-credential helper. The importer never writes to Firestore.

```sh
# DATABASE_URL points to the isolated restore; dry run also checks Postgres state.
cd scripts
npm run crawler:import -- --dry-run --expect-database restore_check

# Real rehearsal writes only the restored DB and the dedicated PRIVATE archive bucket.
# Secure directory must already exist. Each run requires a NEW manifest filename.
npm run crawler:import -- --apply --expect-database restore_check \
  --manifest /secure/crawler-rehearsal.ndjson
```

The Firestore commands above read the live source and incur document-read/transfer costs. Do not
repeat a full live scan for replay or production. Once the complete snapshot and its `.r2.json` sidecar
exist, use **the exact same immutable R2 input** for validation, replay and the approved production import:

```sh
# Dedicated archive credentials + DATABASE_URL; no Firebase SDK or ADC is used by this command.
npm run crawler:import-r2 -- --dry-run --expect-database restore_check \
  --manifest-ref /secure/complete.ndjson.r2.json

npm run crawler:import-r2 -- --apply --expect-database restore_check \
  --manifest-ref /secure/complete.ndjson.r2.json --receipt /secure/new-replay-receipt.json
```

Production requires separate explicit sign-off, a fresh backup, and its actual `--expect-database`
name; reuse this approved artifact, not another Firestore scan. R2-only mode verifies the completed,
non-limited root manifest, project/parser, object metadata, stored-byte SHA-256, gzip recovery,
document paths/counts and unique coverage while importing. Its private receipt records source-version
digests and `firestoreReads: 0`. Default is read-only dry run; apply requires a new receipt filename.
`--concurrency 1..8` bounds object prefetch (default 4); SQL batches remain sequential and at most 500.

Use `--limit N` for a deliberately partial live-source test (per collection/group). Limited manifests
must never authorize deletion. Batches are capped independently of SDK page size at 500 documents
and split at 16 MiB raw: a streaming retry can return a page larger than the requested limit.

The importer archives all `crawler` documents, the ten `rawScrapeData` metadata parents, runs and
nested results. Collection-group scans include descendants of missing parent documents. Archives
retain full document paths, nanosecond timestamps, references, bytes, geopoints and nonfinite numbers
using tagged values. Both exporters refuse unsafe integers because the pinned Firestore SDK cannot
verify int64 values beyond JavaScript's safe range; obtain a native Firestore export if that guard fires,
never authorize deletion from a rounded archive. The local mode-0600 manifest lists object checksums and document ranges/counts;
on success it is also archived in R2, registered in Postgres, and its reference written to `.r2.json`.
Preserve both files privately. A failed run may have a partial/data-complete local manifest but no success sidecar;
require both the completion footer and `.r2.json`, then verify R2 recovery. Preserve partial manifests
and any durable local capture files on failure. Recover already captured documents from R2/local
checkpoints and query only missing cursor ranges; do not blindly restart a full Firestore scan.
Only a verified, complete, non-limited artifact is accepted by the R2 importer. Concurrent source
changes are not a consistent snapshot and require reconciliation.

All valid current events, including non-music and unresolved venues, are retained. Malformed facts
remain as quarantined observations plus lossless evidence. Historical run results do not create a
second set of current events. Missing scraper users do not exclude run history. Reliable booking
links require exact encoded source-key **and venue** matches; the 1,549 bookings without encoded keys
remain unresolved rather than guessed. Existing conflicting links are not overwritten.

Dry-run `wouldInsert`/`wouldUpdate` counts are advisory valid-fact/source-key comparisons, not a full
simulation of temporal/venue conflict resolution. `linksCurrentlyPossible` describes the current DB,
not a prediction of all post-import links. The restored-database apply is the authoritative rehearsal.
Review actual inserted/updated/duplicate/historical/quarantined counts and errors there.

Before requesting production sign-off:

1. Reconcile source counts and manifest coverage against the stable Firestore inventory, including
   metadata parents, raw-history results and quarantined records. Independently GET/gunzip/check SHA-256
   of archived objects and verify document recovery. HEAD checks alone are not a restore drill.
2. Verify original event IDs and booking/profile/account/outbox counts/statuses are unchanged (except
   expected new current-event rows and provenance links). Investigate venue conflicts/quarantine.
3. Replay the completed R2 snapshot unchanged: all 547,087 observations must report duplicates, no
   materializing actions or additional provenance links, and unchanged entity/application signatures.
   Apply and replay must make zero Firestore calls. Test worker retries, older captures and interrupted uploads.
4. Back up production, obtain sign-off, then use the R2-only command and approved manifest against the
   explicitly named production database. Review counts and recovery before separately approved deletion.

The importer and ZIP exporter perform **no deletion**. `scripts/export_migrated_firestore.ts` also
accepts these roots and nested run/result groups for an independent lossless local archive. Firestore
recursive deletion, final root/group emptiness checks and database shutdown are separate operations.
Firebase Auth and its two transport hooks remain in use.

## Formatting review and USD-cent normalization

The [2026-10-19 formatting audit](SCRAPER_FORMATTING_REVIEW.md) records the read-only pre-remediation
findings. The owner subsequently approved omitting blank artist strings, treating `N/A`-style optional
URL placeholders as `null`, and storing dollar amounts as USD integer cents. Names are not inferred,
split or truncated; empty lineups remain `[]`, not invented artists or a non-music classification.
Dates, malformed/relative URLs, unsupported prices and venue conflicts remain held.

`withFormattingV2(input, "usd_major")` establishes a new delivery identity/parser version while keeping
the original source key, capture time, run/venue and evidence. `normalizeObservation` applies cleanup
and exact decimal conversion once. Explicit `usd_cent` inputs are supported without multiplying again;
mis-tagged or mixed-unit inputs fail closed. Fractional cents are quarantined, never silently rounded.
USD is assumed only for missing currency; explicit non-USD currency is held, not relabeled.

The new schema migration refuses existing fractional-cent or explicit non-USD prices before changing
any values. It converts canonical prices exactly, but never rewrites v1 observations/raw evidence or
native booking/profile/identity amounts. Runtime capture boundaries explicitly select v2 and declare
raw extractor dollar-major inputs; raw extraction/evidence itself stays unchanged.

```sh
# After BOTH schema migrations, on the isolated restore first:
npm run crawler:import-r2 -- --apply --expect-database restore_check \
  --manifest-ref /secure/complete.ndjson.r2.json --receipt /secure/new-v2-receipt.json \
  --normalization-version 2 --input-price-unit usd_major
```

Version 1 remains the CLI default for historical compatibility checks. Production must use the
explicit v2 flags and the approved immutable artifact, only after successful isolated reconciliation,
a fresh production backup and separate sign-off. Inspect `pipeline-status.json` for the active
rehearsal; implementation/tests alone are not an applied/reconciled proof.

## Tests

```sh
pnpm --filter @tapped/postgres-ingestion test
# Dedicated LOCAL PostGIS test instance; test creates/drops only a fresh random test DB.
INGESTION_TEST_DATABASE_URL=postgres://...@127.0.0.1:5432/test \
  pnpm --filter @tapped/postgres-ingestion test
```

Node CI runs unit tests and populated-migration/producer-permission integration tests against local
PostGIS. Rust's restricted-ingestion test exercises the same no-business-effects contract. S3 adapter
checks use mocks. Live synthetic R2 upload/download/gunzip, checksum, signed-attachment and bucket/media
isolation checks passed on 2026-10-16. Complete GET/SHA-256/gunzip recovery of the actual source
snapshot and unchanged-input replay also passed in the isolated rehearsal below.

## Operator checkpoint — 2026-10-16

- Created `tapped-scrape-evidence` and `tapped-scrape-archive` in the Tapped account with a Western Europe
  location hint and Standard storage. Both have r2.dev disabled, no custom domains and no CORS policy.
  The only lifecycle default aborts incomplete multipart uploads after seven days; committed objects
  have no deletion/expiration rule.
- Took a fresh private Postgres backup and restored it into an isolated local `restore_check` database.
  No application/identity/mail/crawler worker is connected to that restore.
- Discovered production already owns migration `20261027000000` for APNs/app config. Preserved that
  migration verbatim from the existing repository revision, verified its SHA-384 against production's
  migration ledger, and renumbered scraper ingestion to **`20261028000000`**. Production's ledger was
  not modified. The new migration was applied and recorded only in the isolated restore.
- Before/after signatures and counts match for users, accounts, owners, bookings, activities, effect
  outbox, device tokens, API keys, reviews and Firebase identity records. Baseline includes 118,146
  profiles, 372,150 bookings and 157,120 placeholder source-event IDs, preserved for comparison.
- Token management through the connected Cloudflare identity was initially blocked (9109). The owner
  subsequently supplied separate bucket-scoped S3 credentials in mode-0600 files:
  `~/.config/tapped/scrape-r2-archive.env` and `~/.config/tapped/scrape-r2-evidence.env`. No parent/media
  credential was widened or copied into worker configuration, and no runtime credentials were deployed.
- Live probes passed for both new buckets: verified compressed upload, duplicate upload, GET/SHA-256/
  gunzip recovery, signed attachment download and denied anonymous access. Each credential was denied
  access to the other scraper bucket and both existing media buckets. The private receipt is
  `~/.local/share/tapped/scrape-rehearsal-20261016/r2-proof.json`.
- The complete read-only dry run and limited restored apply passed. The limited apply preserved all
  ten native-table signatures, 157,120 original event IDs/venue references, and zero published events.
  Private logs, manifests, backup checksum and signatures are under
  `~/.local/share/tapped/scrape-rehearsal-20261016/`.
- The first full apply stopped at a locally enforced SQL batch guard: an SDK page contained 580
  distinct documents despite the requested limit of 500. All 580 were already archived. The importer
  now caps chunks independently of SDK page size. Recovery verified/reused 488,580 archived events,
  1,000 history results and 55 metadata/run documents, querying only the missing 57,507 documents in
  disjoint cursor ranges. New captures are checkpointed privately before upload to avoid rereads.
- **Isolated rehearsal passed at 2026-10-16T23:02:51Z.** The completed snapshot contains 544,356 crawler
  documents, 2,731 history results, 45 runs and 10 metadata parents: **547,142 documents**. Every one
  of its 1,102 source objects plus the root manifest was GET/SHA-256/gunzip recovered (88.3 MB
  compressed total). The completed manifest root is also registered in the archive catalog.
- Full restored apply and two complete unchanged-input R2 replays passed, including the final exact
  CLI/reader code. Each replay reported **547,087 duplicates**, zero materializing actions and zero new
  booking links. All nine ingestion-entity signatures, ten native-table signatures, 157,120 original
  event IDs/venue references, and source-version digests were unchanged. Published events remain zero.
  Apply/replay made **zero Firestore calls**. All **38** ingestion unit/integration tests, targeted lint,
  build and operator-script typechecks passed.
- Quality review: 463,879 current observations accepted; 80,477 quarantined. History retained 2,634
  accepted and 97 quarantined observations without creating current events. Quarantine reasons
  overlap; major current reasons include 46,619 invalid performers, 16,255 invalid flier URLs,
  8,941 reversed times and 7,660 venue conflicts. Raw originals remain in the private snapshot.
- Original placeholders: 134,335 now have current facts; 22,785 remain preserved but unmaterialized.
  All 366,596 bookings with usable encoded keys still match source events: **314,026** have exact
  source-key/venue provenance links; **52,570** remain unlinked because their source observations are
  quarantined. Audit found zero incorrect links and no other encoded-key resolution category. The
  1,549 legacy bookings lacking usable encoded keys remain unresolved rather than guessed. All
  628,059 performer-name rows remain unclaimed; no artist/profile accounts were manufactured.
- Private status and reconciliation: `~/.local/share/tapped/scrape-rehearsal-20261016/pipeline-status.json`.
  The completed input is `snapshot-completion/complete.ndjson.r2.json` in that operator directory;
  use that same approved artifact for production, never another full Firestore scan. The run directory
  also contains `quality-impact-review.json` and the final exact-code replay receipt.
- **At this original rehearsal checkpoint, still required:** explicit quality acceptance or separately
  approved quarantine remediation, especially venue conflicts/unlinked bookings; a fresh production backup; and
  explicit production migration/import sign-off. That rehearsal pipeline contains **no production step**.
  No production ingestion, Firestore deletion, bucket-object deletion, crawler scheduling or publication
  was performed during the rehearsal. The subsequent explicitly approved production cutover is recorded
  separately in [the production checkpoint](SCRAPER_PRODUCTION_CUTOVER.md).

## Venue audit — 2026-10-21

The [read-only venue-conflict audit](SCRAPER_VENUE_REVIEW.md) covered all 8,349 held records:
27 directed profile pairs affecting 14,598 existing bookings. It distinguishes separate branches/
rooms from eight plausible alias-review pairs (959 records), and documents the shared-domain routing
hazard. That audit applied no remaps or aliases; all ingestion/native signatures remained unchanged.
The owner subsequently delegated conservative review/remediation. The isolated scoped-resolution
rehearsal **passed**: 959 exact captures materialized without changing source/original venue lineage,
adding 1,447 provenance links (333,933 total). No profiles were merged or native references rewritten.
Plan replay yielded 959 duplicates; full v2 replay yielded 547,087 duplicates, with zero new actions/
links. All 1,094,174 prior observations and native-table signatures were preserved. 7,390 venue conflicts
remain actively held. Routing ambiguity guards, 51 ingestion tests and the full Rust regressions passed;
no production writes, Firestore reads, crawler execution or publication occurred. See the detailed
[resolution checkpoint](SCRAPER_VENUE_REVIEW.md) and private exact-code reconciliation.

For active v2 venue holds, count base rows with `normalization_version=2` and `venue_conflict` only if
there is no accepted observation whose `venue_resolution_id` joins a decision targeting that base row.
Raw historical quarantine counts intentionally do not shrink when a new reviewed observation is added.

## Operator checkpoint — 2026-10-19, approved formatting v2

The isolated v2 rehearsal **passed at 13:54:35Z**. Both v2 and v1 compatibility replays returned
547,087 duplicates with zero additional materialization/links. Original v1 observation contents,
all ten native-table signatures and 157,120 original event IDs/venue references were preserved.

Canonical prices now use USD integer cents: 924,702 existing offers converted exactly before the
R2-only reprocessing; the completed projection contains 1,042,954 offers. No mixed/invalid money
projections or incorrect booking links were found. The cleanup made 59,148 additional current
observations and 23 history observations usable, adding 18,460 provenance links (332,486 total).
No native bookings, artists/profiles, accounts or effects were created/modified; publication stays zero.

Latest v2 quality is 523,027 accepted / 21,329 quarantined current observations plus 2,657 accepted /
74 quarantined history observations. Old v1 quarantines remain immutable history, not the active
quality queue. Venue conflicts (8,349) and reversed times (9,015 including history) remain held; no
venue/date guessing was introduced. See [the detailed review](SCRAPER_FORMATTING_REVIEW.md).

44 ingestion tests, 74 Rust library tests and 107 Rust API tests passed; one manual Slack test remains
intentionally ignored. Build, lint and operator/crawler typechecks passed. Apply/replay used the same
R2 snapshot with **zero Firestore reads**. Production remains untouched and requires remaining quality
review, a fresh backup and explicit migration/import approval.

