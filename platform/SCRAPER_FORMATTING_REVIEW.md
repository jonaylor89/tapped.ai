# Scraper formatting review — 2026-10-19

**Original read-only audit.** This audit did not modify production, Firestore or the restored database.
It read private R2 evidence, not Firestore, and reproduced stored normalized facts for all **80,574**
quarantined observations before simulating changes. Counts below describe that pre-remediation state.

The owner subsequently approved the conservative cleanup and **USD integer-cent storage** (`$1 → 100`).
Implementation uses a new normalization/parser version, retaining original observations/evidence.
The isolated v2 migration/apply/replay is tracked in `pipeline-status.json`; production remains gated.

## Approved implementation checkpoint — 2026-10-19

- `20261029000000_scrape_money_cents.sql` converts canonical prices to bigint cents and records
  normalization version/input unit/notes. All **924,702** existing prices converted exactly on the
  isolated restore; v1 observations and all original event references/native facts were preserved.
- **44** ingestion tests pass, including populated migration, immutable v1 replay, same-capture v2
  precedence, explicit unit/double-conversion guards and fractional-cent quarantine. Fresh-local-DB
  Rust regressions passed (74 library tests, 107 API tests; one manual Slack test intentionally ignored).
- The full R2-only v2 apply completed: **470,597 updated**, **52,430 inserted**, **21,403 quarantined**
  and **2,657 archived history** observations. Compared with v1 this makes **59,148** more current
  observations and **23** more history observations usable, and adds **18,460** exact provenance links
  to existing bookings. No bookings or artist/profile accounts were created.
- **Full v2 rehearsal passed at 2026-10-19T13:54:35Z.** V2 replay and v1 compatibility replay each
  returned **547,087 duplicates**, no materializing actions and no new links. All nine ingestion-entity
  signatures were stable across replays; all ten native-table signatures and 157,120 original event
  IDs/venue references were preserved. All 547,087 original v1 observations retained their prior
  contents, state, identities and evidence pointers.
- Current canonical data contains **1,042,954** USD integer-cent price rows with no invalid/mixed-unit
  projection. There are **332,486** exact booking links and zero incorrect links; no native bookings,
  profiles, accounts or effects were created/modified. Publication remains zero.
- V2 quality: **523,027 accepted / 21,329 quarantined** current observations and **2,657 accepted /
  74 quarantined** history observations. Remaining issues include **8,349 venue conflicts** and
  **9,015 reversed time ranges** (including history), plus malformed URLs/prices and five lineup
  shape/length cases. Reasons overlap. Original v1 quarantines remain immutable historical evidence;
  use `normalization_version=2` for the latest quality queue.
- All apply/replay operations used the original private R2 artifact with **zero Firestore reads**.
  No production migration/import, Firestore deletion, crawler scheduling or publication occurred.
  Remaining quality review, fresh production backup and explicit production approval are still required.

Private aggregate report and candidate identifiers:
`~/.local/share/tapped/scrape-rehearsal-20261016/latest-formatting-audit.json`.
No customer names, source URLs, credentials or raw venue snapshots are included here.

## Conservative first batch

Counts overlap and are not additive. Eligibility below excludes records with remaining errors or
venue conflicts; these are dry-run estimates, not an applied SQL ingestion result.

| Issue | Observations with this shape | Proposed treatment |
|---|---:|---|
| Blank strings inside artist arrays | 46,639 (46,616 current, 23 history) | Omit blank entries; retain real names, spelling and order. An all-blank array becomes `[]`, not an invented artist. |
| Placeholder flier URLs, such as `N/A` | 13,880 | Normalize the optional URL to `null`; preserve the original in evidence. |
| Placeholder event URLs, such as `N/A` | 1,927 | Normalize to `null`; do not invent a destination or change the source key. |
| Plain decimal price strings | 3 distinct observations | Parse unambiguous nonnegative decimal text. Under the subsequently approved USD policy, convert all canonical dollar amounts to integer cents without floating multiplication or implicit rounding. |

Illustrative lineup transformation: `["Known artist", ""]` becomes `["Known artist"]`.
No artist lookup, account creation, fuzzy matching, comma splitting or truncation is proposed.

### Estimated impact

After the proposed formatting rules and existing-venue checks:

- **59,148 current observations** are candidates for materialization:
  - 6,718 already have preserved placeholder event rows;
  - 52,430 currently have no canonical event row;
  - none already has materialized current facts.
- **23 history observations** are candidates for acceptance, still with `materialize=false`.
- **18,460 existing bookings** could gain exact source-key/venue provenance links. These are not new
  bookings; application booking/profile/account data must remain unchanged.
- **689 latent venue conflicts** become visible once formatting errors are removed. Hold these,
  alongside the already known 7,660 conflicts. Do not remap or overwrite original venue references.

## Not in the first batch

| Remaining shape/problem | Count | Why it needs a separate decision |
|---|---:|---|
| Protocol-relative URLs (`//…`) | 1,728 fliers; 5 event URLs | Consider only with a verified captured base/protocol; do not add an arbitrary scheme. |
| Schemeless `www.…` URLs | 1,373 event URLs; 28 fliers | Corroborate against captured source context rather than assume HTTPS. |
| Relative paths | 10 fliers; 4 event URLs | Need a trustworthy base URL; do not guess the host/path. |
| Other malformed strings | 611 event URLs; 599 fliers | Classify further before changing them. |
| Embedded `data:` images | 9 fliers | Preserve in private evidence; not an ordinary public HTTP image URL. |
| Credential-bearing URLs | 2 event URLs | Never publish credentials or silently strip them to invent a new destination. |
| Other unsupported schemes | 6 `mailto:` event URLs; 2 other URLs | Not valid HTTP event/flier links. |
| Scalar rather than array lineups | 2 | Review explicitly; do not split names on punctuation. |
| Overlong artist strings | 3 | Do not truncate or guess where artist names separate. |
| Prices still invalid after decimal parsing | 5 | Negative, boolean, placeholder/free-label or other text values need explicit handling; do not turn unknown/negative prices into free admission. |
| Reversed timestamps | 9,015 (8,941 current, 74 history) | Content ambiguity, not formatting. Do not swap endpoints or add a day automatically. |

Most reversed ranges are 6–24 hours backward (8,414), which may suggest overnight extraction mistakes,
but is not proof. Another 527 exceed one week. Correct dates require authoritative evidence.

## Guardrails for any approved implementation

1. Use a **new explicit normalization/parser version** and new delivery identities. Do not silently
   change v1 behavior or overwrite its immutable observations/evidence.
2. Preserve source keys, source capture times, original event IDs and venue references. Transform
   extraction data after establishing the original source identity, including for history rows.
3. Keep original raw values recoverable and record the normalization policy/changes. Keep unknown
   amounts unknown; USD is the owner's explicit assumption for this ingestion, not an inferred FX
   conversion. No artist identity resolution, date guessing or publication.
4. Run a targeted R2-only rehearsal on the isolated restore first. The actual SQL venue validation
   remains authoritative; 59,148 is an eligibility estimate, not permission to bypass those checks.
5. Verify all native-table signatures/original event references, expected provenance links, no
   publication, and a no-op replay. Report current/latest quality separately from retained v1
   quarantines; historical observations remain immutable rather than being deleted or marked valid.
6. Production import, Firestore deletion, crawler scheduling and publication still require their
   separate approvals.
