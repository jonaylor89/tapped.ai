# Scraper production cutover — 2026-10-21

## Normal release / Firestore closeout — 2026-10-22

**Completed.** The normal registry-backed API, mail and identity release is now
`1f441f884133a107eca983b645e7f193f3ac97cb` on `main` (Deploy API **39793300329**, successful Node/Rust CI).
Migrations 28–30 are in the normal release source; the manually assembled cutover image below is
historical. Deployment/rollback guards enforce the applied migration-bundle minimum. All native and
ingestion/evidence signatures were preserved. The complete remaining quarantine review passed;
Firestore's only two roots/groups match the 547,142-document R2 snapshot.
See [final deletion readiness](FIRESTORE_RETIREMENT_READY.md). Firestore itself has not been deleted.

## Original cutover status

**Production cutover passed at 2026-10-21T21:28:59Z.** The owner explicitly approved the production
migration and R2-only import. Migrations **20261028000000–20261030000000** committed atomically;
all source observations and 959 reviewed captures are applied. Both replays and final reconciliation
passed. API, mail and identity workers run the migration-aware image and are healthy; identity
synchronization has resumed. The authoritative private status is
`~/.local/share/tapped/scrape-rehearsal-20261016/production-status.json`.

## Verified production results

- Recovered the complete **547,142-source-document** R2 snapshot, verifying all 1,102 objects plus
  the root manifest, source-version digests and immutable original delivery identities.
- Base v2 apply: **381,974 inserted**, **141,053 updated**, **21,403 quarantined** and **2,657 archived
  history** observations. Production holds **547,087** base observations plus **959** separate reviewed
  observations: **548,046** total. There was no additional v1 interpretation imported into production.
- Reviewed apply: **959** captures materialized against their original preserved event/venue anchors,
  adding **1,447** exact booking links. Total provenance links: **333,933**. No native bookings,
  profiles, accounts, artist identities or global aliases were created/merged/rewritten.
- Final current-event table: **539,094** rows, including all **157,120** original event/venue references.
  Canonical prices: **1,044,872** USD integer-cent rows. Zero invalid/mixed-unit projections or
  differences between relational prices and current JSON projections were found.
- Scoped replay: **959 duplicates**, zero updates/new links. Full v2 replay: **547,087 duplicates**,
  zero materializing actions/new links. All **ten ingestion/resolution entity signatures** were stable.
  All **547,087 base observations** retained their complete contents/state/evidence through review/replay.
- All **ten native-table signatures** matched the fresh pre-cutover baseline through final verification
  before identity synchronization resumed. Identity business fields were checked again after worker
  resumption and still matched; routine identity scan markers may naturally change afterwards.
- Effective current quality: **523,986 accepted / 20,370 held**. History: **2,657 accepted / 74 held**.
  The **7,390 unresolved venue conflicts** remain quarantined. The 959 superseded base quarantines
  remain immutable historical evidence and are excluded from the effective queue.
- **Zero incorrect booking links, published events, Firestore reads/writes, crawler execution or
  scheduling.** Source deletion and event publication remain separately approved operations.
- All **24** production migration checksums, including the unchanged original APNs/app-config migration,
  were verified after completion. `/health/ready` checks passed for Postgres, search, Redis and mail.
  All three application/worker containers run the same verified migration-aware image.

Private source/apply/recovery/replay receipts, exact-code fingerprints, native/reference signatures,
quality counts and backup pointers are cross-referenced by `production-status.json` and its final
`reconciliation.json`. The original interrupted receipt is retained, not relabeled successful.

## Authorized scope

- Fresh private production backup, migration-ledger preflight, migrations 28–30, normalization-v2
  import from the completed immutable R2 artifact, and 959 previously rehearsed capture-scoped venue
  compatibility decisions. Retain unresolved observations in quarantine.
- Preserve native profiles, accounts, identities, bookings, effects and original event/venue IDs.
- No event publication, crawler execution/scheduling, Firestore reads/deletion or global profile aliases.

## Checkpoints and runtime compatibility

- All **21** previously applied migration checksums matched their original files. Production started
  with **157,120** placeholder events and no scrape observations/runs/provenance links.
- Native business data matched the restore. The identity worker's periodic `scan_id` markers were the
  only drift; comparing every other identity column proved the business identity records unchanged.
  The worker was temporarily paused for exact native before/after signatures; the API remained available
  except for its bounded runtime replacement. Normal identity synchronization resumed after verification.
- Fresh backup: **190,421,535 bytes**, SHA-256 checked, catalog verified, two private copies (operator
  workstation and `/root/scrape-cutover-backups/` on the server). Environment/container configuration
  backups remain private on the server; they contain credentials and must not be published.
- The live API revision was **`9dedca278a160034e43d544e96c198b9214055cc`**. The deployed runtime was
  built from that exact revision plus **only the three approved SQL migrations**. No Rust source,
  dependency, APNs, native booking, identity or mail behavior changes were taken from the working branch.
- Runtime image: `tapped-api:scrape-cutover-2026-10-21t18-47-00-138z`, image ID
  `sha256:aca2290f1705a4ab788a4a8c8b65504dd00bae6084621b060058d01412c6d969`.
  Its migration-bundle label is `20261030000000`. The runtime archive also has two checksum-verified
  private copies. Exact original source hashes and added-migration checksums are in the operator receipt.

**Next deployments must embed migrations through `20261030000000`, including the unchanged original
APNs/app-config migration 27.** Old binaries reject unknown ledger versions on worker startup; merely
retagging an old image is not safe. Promote the migration-only additions into the normal API release
source before another automated deployment. **This promotion and guarded normal deployment completed
on 2026-10-22; no outstanding migration-source promotion remains.** The existing schema-epoch label
alone does not prove the embedded-ledger requirement; the tested bundle guard now checks it.

## Bounded booking-link recovery

The first import retained all **547,087** source observations, then its final bulk provenance-link
statement exceeded the operator connection's two-minute limit (`57014`). That statement rolled back;
no source observations were rolled back and no native bookings were changed. Its original receipt
and failed-attempt log remain intact rather than being relabeled successful.

After analyzing the relevant tables, recovery independently selected the exact eligible booking/event
pairs and added **332,486** provenance links in **67 bounded batches**, rechecking source key and venue
in each insertion. Session-local `work_mem=128MB`, `jit=off` and `max_parallel_workers_per_gather=0`
avoid both large hash-join spills and the container's small shared-memory limit. Global Postgres/API
settings were not changed. An initial parallel recovery attempt failed before inserting any links;
serial recovery passed. The reviewed venue batch then added **1,447** links and its replay added zero.

All ten native-table signatures and all 157,120 original event/venue references matched after recovery,
reviewed apply and full-source replay. Full-source replay reproduced the exact approved archive digests
and returned only duplicates; price and linkage checks passed before worker resumption. The interrupted
receipt, SQLSTATE, recovery receipt and final reconciliation are cross-referenced privately; a historical
running receipt is not evidence of an active importer.

## Source and recovery

The import uses the same **547,142-document / 1,102-object** private R2 snapshot used in rehearsal,
with explicit `--normalization-version 2 --input-price-unit usd_major`. It does not import an extra v1
interpretation merely to reproduce the rehearsal's historical row counts. Metadata parents/runs are
archived separately from **547,087** event/history observations. Reviewed captures add separate
observations without modifying their original base observations or source venue provenance.

Operator files remain outside the repository, mode 0600 in mode-0700 directories. Production status,
receipts, source-version digests, preserved-reference/native signatures and backup pointers are separate
from the passed isolated-rehearsal status. Inspect the stage/receipt before retrying an interruption;
imports are idempotent, but receipts must use new filenames. Never rerun a full Firestore export.

Do not automatically restore a whole database backup over subsequent legitimate native writes, delete
quarantine/evidence to improve counts, or roll back to a binary with an older embedded migration ledger.
A failed stage requires inspection and an explicit recovery/fix-forward decision.

See [ingestion](SCRAPER_INGESTION.md), [formatting review](SCRAPER_FORMATTING_REVIEW.md) and
[venue review](SCRAPER_VENUE_REVIEW.md) for normalization, provenance and held-quality policies.
