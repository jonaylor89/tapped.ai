# Firestore retirement closeout — 2026-10-22

**Closeout passed at 2026-10-22T14:32:11Z.** The normal API release is deployed and verified;
remaining quarantines are reviewed and preserved outside Firestore. The owner may now delete the
reviewed Firestore `(default)` database, keeping Firebase Auth/project/hooks. **No deletion was executed.**

## Scope

The owner requested the remaining-conflict review and normal API release so the Firestore database
can be deleted. **This closeout does not delete Firestore, publish events, execute/schedule crawlers,
merge profiles, remap venues or change native bookings.** Firebase Auth and its two transport hooks
must remain. Deleting the Firebase/GCP project is not an acceptable substitute for deleting Firestore.

## Remaining quality review completed

Read-only production/R2 review reproduced the exact stored facts and source identities of **all
20,444 effective quarantines**, recovering **636** immutable evidence objects. Before/after quarantine
signatures matched. No Firestore document-body rescan or data correction was performed.

Reasons overlap:

| Reason | Observations | Final disposition |
|---|---:|---|
| Reversed ranges | 9,015 | Keep held; do not swap endpoints or invent an overnight date. |
| Venue conflict | 7,390 | Keep held; original event/booking venue references stay unchanged. |
| Invalid flier URL | 2,375 | Keep held; preserve malformed, credential-bearing or context-dependent originals. |
| Invalid event URL | 2,002 | Keep held; do not invent schemes or destinations. |
| Invalid prices | 5 | Keep held; unknown/negative/boolean/free-label input is not zero-dollar admission. |
| Overlong performer entries | 3 | Keep held; do not truncate or infer identities. |
| Scalar lineups | 2 | Keep held; do not split names on punctuation. |

The 19 remaining directed venue pairs are not additional established aliases:

| Category | Pairs | Observations | Existing bookings |
|---|---:|---:|---:|
| Distinct venues, branches or promoter/venue scopes | 7 | 5,213 | 9,077 |
| Separate rooms, parent spaces or shared complexes | 10 | 2,040 | 3,883 |
| Ambiguous branding/subvenue scope | 2 | 137 | 191 |
| **Total still quarantined** | **19** | **7,390** | **13,151** |

Examples include Lafayette/New Orleans Rock 'n' Bowl, Lincoln Hall/Schubas, HI-FI/Annex,
Empire Underground/Live and Wang/Shubert. Shared domains, addresses or place IDs do not establish
venue equivalence. The Student Prince/Fort and Water Tower/Water Tower Bar remain scope-ambiguous.
No independent event-level authority in the captured evidence justifies changing preserved references.
The previously approved 959 compatibility decisions remain applied; no blanket alias rules were added.

**Held does not mean unmigrated.** Their normalized observations, original venue IDs, errors and
private R2 source pointers are retained in production Postgres, and the complete originals are in R2.
They can be reviewed later without Firestore. Data-quality resolution is not a prerequisite to removing
an already migrated source database.

## Source coverage and live dependencies

Fresh metadata listed exactly two Firestore roots. Four aggregate index counts (not document-body
scans) matched the sealed snapshot:

| Root/group | Live count | Archived count |
|---|---:|---:|
| `crawler` root | 544,356 | 544,356 |
| `rawScrapeData` root | 10 | 10 |
| nested `scrapeRuns` group | 45 | 45 |
| nested `scrapeResults` group | 2,731 | 2,731 |
| **Total** | **547,142** | **547,142** |

The complete R2 artifact was already applied/replayed in production. The later closeout rechecked all
remaining quarantines directly against that artifact. Counts alone are not a content digest; they are
used together with the exact archived-version replay, R2 checksums and retired-writer evidence.
Monitoring returned no write-count series since 2026-10-16; this is supporting telemetry, not a claim
that absence of a metric independently proves absence of writes. Historical deletion/read telemetry
was present. No native Firestore backup exists in `nam5`; do not mistake PITR for a retained backup
that survives database deletion. Recovery here relies on the verified private R2 artifact and Postgres
backups, not Firestore PITR.

All-regions Functions inventory contains only active Auth transports **`onUserCreate` and
`onUserDelete`**. The `us-central1` Cloud Scheduler inventory is empty. The supported API/application
contracts use Postgres; source/config review does not authorize execution of legacy archived scripts.
Crawlers remain unscheduled and their old runtime credentials disabled. Auth and hosted verification
remain Firebase services and must not be removed.

Private evidence, source counts/read times, metric responses, pair/case dispositions, quarantine
signatures and production connection details remain mode 0600 under the mode-0700 operator directory
referenced by `~/.local/share/tapped/scrape-rehearsal-20261016/latest-closeout.json`.

## API release and final deletion gate

The ingestion stack was rebased onto current `main`, preserving the live APNs/identity implementation
and excluding unrelated parent work. Normal API images embed migrations 28–30 and declare migration
bundle `20261030000000`. The deployment guard checks both proposed and rollback images against the
production ledger before allowing an older image. Seven executable guard tests include missing/old
bundles, future ledger versions, malformed metadata and highest-migration/label agreement.

Local verification: **51 ingestion tests**, **74 Rust library tests**, **111 Rust API tests** and
**7 deployment guard tests** passed; one manual Slack test is intentionally ignored. Clippy, formatting,
ingestion lint/build, operator scripts and crawler typechecks passed. CI/release identifiers and final
production readiness must be recorded below before treating the release as complete.

**Release status: deployed and verified.** Revision
`1f441f884133a107eca983b645e7f193f3ac97cb` is on `main` and deployed as
`ghcr.io/jonaylor89/tapped-api:1f441f884133a107eca983b645e7f193f3ac97cb`.
Rust CI **39792255283**, Node CI **39792255389** and Deploy API **39793300329** all succeeded.
API, mail and identity workers run the same image, unpaused, with migration bundle `20261030000000`;
public readiness and the on-server schema guard passed.

The first CI attempt correctly blocked a newly published certificate-validation advisory
**RUSTSEC-2026-0382**. The transitive `rustls-webpki` dependency was pinned from **0.103.15 to 0.103.16**,
and the audit tool is now pinned to **0.22.2**. No security gate was ignored; the patched release passed
all checks and the full local Rust regression suite.

Post-release verification matched all **ten native business-table signatures** (excluding only routine
identity `scan_id` markers), **eleven ingestion/evidence table signatures**, all **24 migration checksums**
and all **157,120 original event/venue references**. The fresh deployment backup is **458,370,710 bytes**,
SHA-256/catalog verified, with two private copies. No ingestion replay or native-data mutation was needed
for the release; the already verified production observations/prices/provenance remain unchanged.
Private final evidence: `~/.local/share/tapped/scrape-rehearsal-20261016/closeout-status.json`.

With those gates passed, the reviewed remaining Firestore data is eligible for the owner's
separate deletion action. Delete only the Firestore **`(default)` database in project
`in-the-loop-306520`**, or its two reviewed roots recursively if retaining an empty database is desired.
Do not delete the Firebase/GCP project, Firebase Auth users/configuration, the two Auth hooks, R2
buckets/evidence, or private Postgres/runtime recovery backups. Deletion is destructive and is not
executed by this task. If new writers/collections appear before deletion, stop and reconcile the delta.

See [production migration results](SCRAPER_PRODUCTION_CUTOVER.md) for the completed import, immutable
observation/replay proofs, original-ID/native-data preservation and bounded provenance-link recovery.
