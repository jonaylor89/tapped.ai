import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { describe, test } from "node:test";
import {
  addSource,
  claimJob,
  countJobs,
  dueSources,
  enqueueJob,
  enqueueOutbox,
  eventContentHash,
  extendLease,
  failJob,
  finishJob,
  getCandidate,
  getFetchState,
  getJob,
  getRawPage,
  insertCandidate,
  listAlerts,
  listPlaceAliases,
  listSourceEvents,
  MIGRATIONS,
  markOutboxPublished,
  migrate,
  normalizeName,
  openDb,
  pendingOutbox,
  putRawPage,
  raiseAlert,
  recordEventChange,
  resolveAlerts,
  resolvePlaceId,
  SCHEMA_VERSION,
  saveFetchState,
  schemaVersion,
  stableStringify,
  updateCandidate,
  upsertEvent,
  upsertPlaceAlias,
  upsertVenues,
} from "../src/db.js";
import type { ValidatedEvent } from "../src/types.js";

const T0 = Date.UTC(2026, 10, 2, 12, 0, 0);

function sampleEvent(overrides: Partial<ValidatedEvent> = {}): ValidatedEvent {
  return {
    identityKey: "venue-1|2026-11-07|20:00|the example band",
    sourceId: "src-1",
    venueId: "venue-1",
    title: "The Example Band",
    startLocal: "2026-11-07T20:00",
    startUtc: "2026-11-08T02:00:00.000Z",
    datePrecision: "instant",
    endLocal: null,
    endUtc: null,
    doorsLocal: "2026-11-07T19:00",
    timezone: "America/Chicago",
    description: null,
    imageUrl: null,
    eventUrl: "https://example-room.test/events/the-example-band",
    ticketUrl: "https://www.ticketmaster.com/event/123",
    performers: ["The Example Band"],
    prices: [{ kind: "advance", minCents: 1500, maxCents: 1500, currency: "USD", text: "$15 adv" }],
    isFree: false,
    status: "scheduled",
    category: "music",
    isMusic: true,
    evidence: ["Fri Nov 7 — The Example Band"],
    extractor: "jsonld",
    sourceEventId: null,
    warnings: [],
    ...overrides,
  };
}

function seedSource(db: DatabaseSync) {
  upsertVenues(db, [
    {
      id: "venue-1",
      name: "The Example Room",
      address: "1 Main St",
      lat: 41.9,
      lng: -87.65,
      website: "https://example-room.test",
      googlePlaceId: "ChIJ-room",
      timezone: "America/Chicago",
      syncedAt: T0,
    },
  ]);
  return addSource(
    db,
    {
      id: "src-1",
      venueId: "venue-1",
      kind: "html",
      url: "https://Example-Room.test/calendar#top",
      timezone: "America/Chicago",
    },
    T0,
  );
}

describe("migrations", () => {
  test("fresh database migrates to the latest version and is idempotent", () => {
    const db = openDb(":memory:");
    assert.equal(schemaVersion(db), SCHEMA_VERSION);
    assert.equal(migrate(db), SCHEMA_VERSION);
    assert.equal(migrate(db), SCHEMA_VERSION);
    const tables = (
      db.prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").all() as { name: string }[]
    ).map((row) => row.name);
    for (const table of [
      "alerts",
      "event_changes",
      "events",
      "fetch_state",
      "jobs",
      "publish_outbox",
      "raw_pages",
      "sources",
      "venue_candidates",
      "venue_place_ids",
      "venues",
    ])
      assert.ok(tables.includes(table), `missing table ${table}`);
    db.close();
  });

  test("applies only newer migrations and rolls back a failing one", () => {
    const db = new DatabaseSync(":memory:");
    const extra = [
      ...MIGRATIONS,
      { version: SCHEMA_VERSION + 1, name: "add-note", sql: "ALTER TABLE sources ADD COLUMN note TEXT;" },
    ];
    assert.equal(migrate(db, extra), SCHEMA_VERSION + 1);
    assert.equal(migrate(db, extra), SCHEMA_VERSION + 1);
    const broken = [
      ...extra,
      { version: SCHEMA_VERSION + 2, name: "broken", sql: "CREATE TABLE ok_table (x INTEGER); SELECT * FROM nope;" },
    ];
    assert.throws(() => migrate(db, broken));
    assert.equal(schemaVersion(db), SCHEMA_VERSION + 1);
    const okTable = db.prepare("SELECT name FROM sqlite_master WHERE name='ok_table'").get();
    assert.equal(okTable, undefined, "failed migration must roll back completely");
    db.close();
  });

  test("file-backed database persists across reopen", () => {
    const dir = mkdtempSync(join(tmpdir(), "event-scraper-db-"));
    try {
      const path = join(dir, "nested", "scraper.sqlite");
      const first = openDb(path);
      seedSource(first);
      first.close();
      const second = openDb(path);
      assert.equal(schemaVersion(second), SCHEMA_VERSION);
      assert.equal(dueSources(second, T0).length, 1);
      second.close();
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe("job queue", () => {
  test("claims in run_after order, respects run_after and kinds", () => {
    const db = openDb(":memory:");
    const later = enqueueJob(db, "fetch_source", { sourceId: "b" }, { now: T0, runAfter: T0 + 60_000 });
    const first = enqueueJob(db, "fetch_source", { sourceId: "a" }, { now: T0 });
    enqueueJob(db, "discover_cell", { cell: "x" }, { now: T0 });

    const claimed = claimJob<{ sourceId: string }>(db, { kinds: ["fetch_source"], now: T0 });
    assert.ok(claimed);
    assert.equal(claimed.id, first.id);
    assert.equal(claimed.payload.sourceId, "a");
    assert.equal(claimed.status, "leased");
    assert.equal(claimed.attempts, 1);
    assert.ok(claimed.leaseToken);

    assert.equal(claimJob(db, { kinds: ["fetch_source"], now: T0 }), null, "later job is not yet runnable");
    const due = claimJob(db, { kinds: ["fetch_source"], now: T0 + 60_000 });
    assert.equal(due?.id, later.id);
    assert.equal(claimJob(db, { kinds: ["discover_cell"], now: T0 })?.kind, "discover_cell");
    db.close();
  });

  test("a leased job is not claimable until its lease expires; stale holder cannot finish", () => {
    const db = openDb(":memory:");
    const job = enqueueJob(db, "fetch_source", { sourceId: "a" }, { now: T0 });
    const a = claimJob(db, { now: T0, leaseMs: 1000 });
    assert.equal(a?.id, job.id);
    assert.equal(claimJob(db, { now: T0 + 999 }), null);

    const b = claimJob(db, { now: T0 + 1000, leaseMs: 1000 });
    assert.equal(b?.id, job.id, "expired lease is reclaimed");
    assert.equal(b?.attempts, 2);
    assert.notEqual(b?.leaseToken, a?.leaseToken);

    assert.equal(finishJob(db, job.id, a!.leaseToken!, T0 + 1001), false, "old token lost the lease");
    assert.equal(extendLease(db, job.id, b!.leaseToken!, 5000, T0 + 1500), true);
    assert.equal(claimJob(db, { now: T0 + 2500 }), null, "extended lease still held");
    assert.equal(finishJob(db, job.id, b!.leaseToken!, T0 + 3000), true);
    assert.equal(getJob(db, job.id)?.status, "done");
    assert.equal(claimJob(db, { now: T0 + 10_000_000 }), null);
    db.close();
  });

  test("failures back off, then go dead after max attempts", () => {
    const db = openDb(":memory:");
    const job = enqueueJob(db, "fetch_source", {}, { now: T0, maxAttempts: 2 });
    const first = claimJob(db, { now: T0 })!;
    assert.equal(failJob(db, job.id, first.leaseToken!, "boom", { now: T0 }), "queued");
    const requeued = getJob(db, job.id)!;
    assert.equal(requeued.lastError, "boom");
    assert.ok(requeued.runAfter > T0, "retry is delayed");
    assert.equal(claimJob(db, { now: T0 }), null);

    const second = claimJob(db, { now: requeued.runAfter })!;
    assert.equal(second.attempts, 2);
    assert.equal(failJob(db, job.id, second.leaseToken!, "boom again", { now: requeued.runAfter }), "dead");
    assert.equal(getJob(db, job.id)?.status, "dead");
    assert.equal(failJob(db, job.id, second.leaseToken!, "late"), null, "no lease, no-op");

    const fatal = enqueueJob(db, "fetch_source", {}, { now: T0 });
    const leased = claimJob(db, { now: T0 + 10_000_000 })!;
    assert.equal(leased.id, fatal.id);
    assert.equal(failJob(db, fatal.id, leased.leaseToken!, "blocked", { retry: false }), "dead");
    db.close();
  });

  test("dedupe key collapses open jobs but allows re-enqueue after completion", () => {
    const db = openDb(":memory:");
    const a = enqueueJob(db, "fetch_source", { sourceId: "s" }, { dedupeKey: "fetch:s", now: T0 });
    const b = enqueueJob(db, "fetch_source", { sourceId: "s" }, { dedupeKey: "fetch:s", now: T0 });
    assert.equal(a.id, b.id);
    assert.equal(countJobs(db, { status: "queued" }), 1);
    const claimed = claimJob(db, { now: T0 })!;
    assert.equal(enqueueJob(db, "fetch_source", {}, { dedupeKey: "fetch:s", now: T0 }).id, a.id, "leased is open");
    finishJob(db, claimed.id, claimed.leaseToken!, T0);
    const c = enqueueJob(db, "fetch_source", { sourceId: "s" }, { dedupeKey: "fetch:s", now: T0 });
    assert.notEqual(c.id, a.id);
    db.close();
  });
});

describe("repositories", () => {
  test("sources canonicalize URLs, dedupe, and require a venue unless listing", () => {
    const db = openDb(":memory:");
    const source = seedSource(db);
    assert.equal(source.url, "https://example-room.test/calendar");
    assert.equal(source.venueId, "venue-1");
    const again = addSource(db, {
      venueId: "venue-1",
      kind: "html",
      url: "https://example-room.test/calendar",
      timezone: "America/Chicago",
    });
    assert.equal(again.id, source.id);
    assert.throws(() =>
      addSource(db, { venueId: null, kind: "html", url: "https://x.test/", timezone: "America/Chicago" }),
    );
    const listing = addSource(db, {
      venueId: null,
      kind: "listing",
      url: "https://altweekly.test/music",
      timezone: "America/Chicago",
    });
    assert.equal(listing.venueId, null);

    assert.equal(dueSources(db, T0).length, 2);
    saveFetchState(db, source.id, { lastFetchAt: T0, etag: '"abc"', successfulFetches: 1 });
    assert.deepEqual(
      dueSources(db, T0 + 1000).map((s) => s.id),
      [listing.id],
    );
    assert.equal(dueSources(db, T0 + source.fetchIntervalMs).length, 2);
    const state = getFetchState(db, source.id);
    assert.equal(state.etag, '"abc"');
    assert.equal(state.consecutiveZeroResults, 0);
    saveFetchState(db, source.id, { consecutiveZeroResults: 2 });
    assert.equal(getFetchState(db, source.id).etag, '"abc"', "patch keeps other fields");
    db.close();
  });

  test("raw pages are content addressed", () => {
    const db = openDb(":memory:");
    const bytes = new TextEncoder().encode("<html>hi</html>");
    const sha = putRawPage(db, { url: "https://x.test/", contentType: "text/html", bytes }, T0);
    assert.equal(putRawPage(db, { url: "https://x.test/again", contentType: "text/html", bytes }, T0), sha);
    const page = getRawPage(db, sha);
    assert.equal(new TextDecoder().decode(page!.bytes), "<html>hi</html>");
    db.close();
  });

  test("events upsert, changes and outbox dedupe", () => {
    const db = openDb(":memory:");
    seedSource(db);
    const event = sampleEvent();
    const stored = upsertEvent(db, event, { now: T0 });
    assert.equal(stored.status, "active");
    assert.equal(stored.missCount, 0);
    assert.equal(stored.contentHash, eventContentHash(event));
    assert.deepEqual(stored.data.prices, event.prices);

    const same = upsertEvent(db, { ...event, warnings: ["noise"] }, { now: T0 + 1 });
    assert.equal(same.contentHash, stored.contentHash, "warnings don't change the content hash");
    assert.equal(same.lastChangedAt, T0);

    const changedPrice = sampleEvent({
      prices: [{ kind: "advance", minCents: 1800, maxCents: 1800, currency: "USD", text: "$18 adv" }],
    });
    const updated = upsertEvent(db, changedPrice, { now: T0 + 2 });
    assert.notEqual(updated.contentHash, stored.contentHash, "nested price change alters hash");
    assert.equal(updated.lastChangedAt, T0 + 2);

    recordEventChange(db, {
      eventId: updated.id,
      sourceId: "src-1",
      identityKey: event.identityKey,
      change: "updated",
      before: event,
      after: changedPrice,
    });
    assert.equal(listSourceEvents(db, "src-1", ["active"]).length, 1);

    const first = enqueueOutbox(db, {
      eventId: updated.id,
      change: "new",
      event: changedPrice,
      observedAt: T0,
      evidenceSha256: null,
    });
    assert.ok(first);
    const dup = enqueueOutbox(db, {
      eventId: updated.id,
      change: "new",
      event: changedPrice,
      observedAt: T0 + 5,
      evidenceSha256: null,
    });
    assert.equal(dup, null);
    const pending = pendingOutbox(db);
    assert.equal(pending.length, 1);
    assert.equal(pending[0]?.event.title, "The Example Band");
    markOutboxPublished(db, [first]);
    assert.equal(pendingOutbox(db).length, 0);
    db.close();
  });

  test("alerts dedupe while open", () => {
    const db = openDb(":memory:");
    seedSource(db);
    const a = raiseAlert(db, { kind: "zero_results", sourceId: "src-1", message: "0 events" }, T0);
    const b = raiseAlert(db, { kind: "zero_results", sourceId: "src-1", message: "0 events again" }, T0 + 1);
    assert.equal(a.id, b.id);
    assert.equal(listAlerts(db, { open: true }).length, 1);
    assert.equal(resolveAlerts(db, { sourceId: "src-1", kind: "zero_results" }, T0 + 2), 1);
    const c = raiseAlert(db, { kind: "zero_results", sourceId: "src-1", message: "again" }, T0 + 3);
    assert.notEqual(c.id, a.id);
    db.close();
  });

  test("candidates and place-id aliases resolve many ids to one owner", () => {
    const db = openDb(":memory:");
    const candidate = insertCandidate(
      db,
      {
        name: "The Hi-Fi",
        address: "1043 Virginia Ave, Indianapolis, IN",
        lat: 39.758,
        lng: -86.145,
        website: "https://www.thehifi.com/events",
        primaryPlaceId: "ChIJ-business",
        discoveredFrom: "google_places",
        evidence: { query: "live music venue" },
      },
      T0,
    );
    assert.equal(candidate.normalizedName, "hi fi");
    assert.equal(candidate.websiteDomain, "thehifi.com");
    assert.equal(candidate.status, "new");

    upsertPlaceAlias(db, { placeId: "ChIJ-premise", candidateId: candidate.id, venueId: null, isCanonical: false });
    upsertPlaceAlias(db, {
      placeId: "ChIJ-business",
      candidateId: candidate.id,
      venueId: null,
      isCanonical: true,
      types: ["night_club", "bar"],
    });
    upsertPlaceAlias(db, { placeId: "ChIJ-address", candidateId: candidate.id, venueId: null, isCanonical: false });
    assert.equal(resolvePlaceId(db, "ChIJ-premise")?.candidateId, candidate.id);
    assert.equal(resolvePlaceId(db, "ChIJ-unknown"), null);
    const aliases = listPlaceAliases(db, { candidateId: candidate.id });
    assert.equal(aliases.length, 3);
    assert.equal(aliases.filter((alias) => alias.isCanonical).length, 1);
    assert.equal(aliases[0]?.placeId, "ChIJ-business");
    assert.deepEqual(aliases[0]?.types, ["night_club", "bar"]);

    upsertPlaceAlias(db, { placeId: "ChIJ-premise", candidateId: candidate.id, venueId: null, isCanonical: true });
    assert.equal(listPlaceAliases(db, { candidateId: candidate.id }).filter((a) => a.isCanonical).length, 1);
    assert.throws(() => upsertPlaceAlias(db, { placeId: "x", candidateId: null, venueId: null, isCanonical: false }));

    const updated = updateCandidate(
      db,
      candidate.id,
      { status: "promoted", provenEventCount: 4, website: "https://hifi-annex.test", evidence: { ok: true } },
      T0 + 5,
    );
    assert.equal(updated.status, "promoted");
    assert.equal(updated.websiteDomain, "hifi-annex.test");
    assert.deepEqual(getCandidate(db, candidate.id)?.evidence, { ok: true });
    db.close();
  });
});

test("normalizeName and stableStringify", () => {
  assert.equal(normalizeName("The Hi-Fi"), "hi fi");
  assert.equal(normalizeName("  Café  Wha?  "), "cafe wha");
  assert.equal(normalizeName("Lincoln Hall & Schubas"), "lincoln hall and schubas");
  assert.equal(
    stableStringify({ b: 1, a: { d: [2, { z: 1, y: 2 }], c: undefined } }),
    '{"a":{"d":[2,{"y":2,"z":1}]},"b":1}',
  );
});
