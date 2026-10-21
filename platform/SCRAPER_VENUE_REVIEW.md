# Venue-conflict audit — 2026-10-21

**Read-only; no resolutions applied.** Audited all **8,349** v2 venue-conflict observations on the isolated
restore, including every archived venue snapshot. No production Postgres access, Firestore reads,
external website/Places lookups, profile merges, venue remaps, booking changes or publications occurred.

Private aggregate report and operator-only pair/case files:
`~/.local/share/tapped/scrape-rehearsal-20261016/latest-venue-audit.json`.
`pairs-private.json` contains public venue labels/configuration plus internal profile IDs;
`cases-private.json` contains observation/event IDs, booking IDs and R2 evidence pointers. They remain
outside the repository in mode-0600 files under a mode-0700 operator directory. No contact details,
account owner identifiers, credentials or raw venue documents are published here.

## Findings

- **27 directed venue pairs**, involving 25 preserved venue IDs, 23 source venue IDs and 47 distinct
  profiles—not 8,349 separate identity decisions.
- Every preserved/source profile exists, is venue-enabled and is neither deleted nor shadow-banned.
  No conflict is a missing-profile/NULL-ID case. No shared account-owner link was found between the
  pairs; absence of a link does not prove different real-world ownership.
- All 8,349 events retain their original baseline event IDs/venue references and have no materialized
  current facts. All **14,598** associated native bookings use the preserved requester venue, and none
  has acquired an import link for these held events.
- **Important limitation:** baseline venue IDs were derived from booking requesters. Their agreement
  is structural consistency, not two independent confirmations of the correct real-world venue.
- Recovered **50** R2 evidence objects (6.35 MB compressed) covering all 8,349 cases. Every archived
  venue ID matches the recorded source venue ID; every archived venue name/place/site matches the
  corresponding source profile where tested. This is not a newly introduced adapter/normalizer-ID bug.

## Reviewed work queues

These are recommendations from stored public venue names, configured sites, place IDs and locations,
not independently verified aliases or permission to change identities. Counts are exclusive.

| Queue | Pairs | Observations | Existing bookings | Recommendation |
|---|---:|---:|---:|---|
| Different venues, branches or venue/promoter profiles | 7 | 5,213 | 9,077 | Never merge by domain. Keep held pending per-event venue evidence. |
| Shared complex, room or parent-space scope | 10 | 2,040 | 3,883 | Preserve room/venue distinctions; shared address/site is insufficient. |
| Plausible name aliases | 8 | 959 | 1,447 | Prioritize explicit pair-by-pair identity review. Not automatically safe. |
| Ambiguous branding/subvenue | 2 | 137 | 191 | Obtain an explicit identity/scope decision. |
| **Total** | **27** | **8,349** | **14,598** | No changes applied. |

### Concrete examples

- **Rock 'n' Bowl de Lafayette → Rock 'n' Bowl New Orleans:** 2,646 observations / 3,445 bookings;
  shared domain but approximately **185 km apart**. A brand domain is not a venue identity.
- **Lincoln Hall → Schubas Tavern:** 2,316 observations / 5,206 bookings; same site, different venues
  roughly 2 km apart. Together these first two pairs account for 4,962 conflicts.
- **The Hi-Fi → HI-FI Annex:** 1,232 observations / 2,465 bookings; same place ID, but the source site
  explicitly describes the outdoor Annex. Do not collapse rooms just because place IDs match.
- **Empire Underground → Empire Live** and **Boch Center Wang Theatre → Shubert Theatre** also share
  place/site signals despite different named spaces. An automated same-place/site test would put them
  in the broad duplicate-candidate bucket; manual review deliberately excludes them from aliases.
- **Abilene Bar and Lounge → Abilene Bar & Lounge:** 519 observations / 869 bookings; same place/site
  and naming variation. This is a plausible alias to review, not an automatic merge.
- **The Flatiron Room - NoMad → The Flatiron Room NoMad:** 382 observations / 488 bookings; same
  configured page and nearby coordinates, but different place IDs. Needs explicit place/identity review.
- **Nighthorse → Songbyrd Music House:** 25 observations / 85 bookings, different domains and cities
  approximately 331 km apart. Native booking title/start/end all agree with the captured event facts
  for these 85 bookings, while the captured venue identity points elsewhere. This is strong consistency
  evidence of historical venue tagging contamination, not independent proof authorizing a remap.

The eight alias-review labels are **P004, P005, P017, P019, P022, P024, P025 and P027**. Their private
matrix includes names, exact site/place evidence, distances, affected IDs and counts for owner review.

## Likely mechanism and current routing hazard

**8,324 / 8,349** conflicts (26 pairs) share a non-social website hostname between the profiles.
Both profiles' sites therefore agree with the requested domain, even for separate branches/rooms.
The other 25 are the cross-domain Nighthorse/Songbyrd cases.

Current code has a concrete ambiguity hazard:

- `services/event-crawler/src/utils/database.ts`, `buildDomainMap`: assigns one value to
  `result[getBaseDomain(url.href)]`; a later venue on the same domain overwrites the earlier venue.
- `services/event-crawler/src/main.ts`: selects venue context by the loaded URL's base domain.
- Across the restored active venue profiles, **309** base-domain groups have multiple profile IDs.
  This is a profile-configuration risk count, not a claim that all are in one configured crawl batch.

This can conflate shared-brand/umbrella sites. It is a **plausible contributor**, not proven historical
causation: archived venue associations may also come from older per-scraper contexts. Do not treat
an affected domain as proof that either profile is the correct venue for a particular event.

Longest-path matching alone is not a sufficient repair: exact non-root configured-path prefixes
support the source profile alone in only 16 cases and disambiguate neither profile in 8,333 cases.
Venue marketing URLs are often not event-detail URL prefixes. Future routing should reject ambiguity
and retain explicit discovery/event-level venue context, rather than choose the last hostname match.
No crawler code was changed or executed by this audit.

## Event-content cautions

- Only **3,814 / 8,349** captured records have both an exact normalized title and start-time match to
  at least one associated booking. No fuzzy title/artist matching was used.
- Across bookings with both values available, 6,478 start times match and 8,037 differ; 10,556 titles
  match and 3,582 differ. Differences can reflect extraction, timezone/slot interpretation or changed
  source content. They are not authorization to overwrite native booking details.
- No conflict key's existing booking start-time span exceeds 36 hours. This does not prove URL-based
  occurrence identity is universally safe or that a current capture describes a historical booking.
- Booking content can derive from an earlier scrape. Its agreement is consistency evidence, not an
  independent website/venue verification. Alias approval must not implicitly approve date corrections.

## Recommended next actions

1. Before enabling future crawlers, separately approve hardening shared-domain routing: ambiguous
   domains must not silently select a venue. Domain/longest-path guesses are not identity resolution.
2. Review the eight plausible-alias pairs first. Any approved equivalence must preserve existing
   event IDs, booking references and profile accounts; retain the original source venue in evidence.
   Do not apply a blanket global source-profile redirect or merge co-located rooms/theatres.
3. Keep the other queues held unless event-level/source-owner evidence resolves them. Explicitly
   accepting the remaining quarantine is an available production decision; no need to fabricate data.
4. Rehearse any separately approved resolution policy from R2 with new versioned provenance and no
   native-data changes before production approval. Firestore deletion, scheduling and publication
   remain separately gated.

## Verification

All **nine ingestion-entity signatures** still match the passed v2 rehearsal; all **ten native-table
signatures** still match the original restore baseline. All audited event IDs/venue references are
preserved. Database sessions were read-only, Firestore reads were zero, external website fetches were
zero, and no resolution/alias was applied. The v2 rehearsal status remains passed and unchanged.
