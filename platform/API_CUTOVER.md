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

Web deployment is a separate Vercel step; a successful Node CI build does not deploy app.tapped.ai.
No Vercel token/project login is available locally, in GitHub secrets, or in the browser session.
Do not claim the production website was updated until its production deployment and API-only reads
are verified. The legacy client Typesense search key was revoked (old clients may fail); key metadata
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

## Native distribution

A simulator build is not an App Store release. Archive/sign/upload the native app and release it
through App Store Connect separately. Older Flutter/Firestore clients are intentionally unsupported.
