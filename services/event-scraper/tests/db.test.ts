import assert from "node:assert/strict";
import { describe, test } from "node:test";
import {
  addSource,
  all,
  claimJob,
  countJobs,
  type Db,
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
  getKv,
  getRawPage,
  insertCandidate,
  listAlerts,
  listPlaceAliases,
  listSourceEvents,
  MIGRATIONS,
  markOutboxPublished,
  migrate,
  normalizeName,
  one,
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
  setKv,
  stableStringify,
  transaction,
  updateCandidate,
  upsertEvent,
  upsertPlaceAlias,
  upsertVenues,
} from "../src/db.js";
import type { ValidatedEvent } from "../src/types.js";
import { createTestSchema, openTestDb, testDatabaseUrl } from "./helpers/db.js";

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

async function seedSource(db: Db) {
  await upsertVenues(db, [
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
  test("fresh schema migrates to the latest version and is idempotent", async () => {
    const db = await openTestDb();
    assert.equal(await schemaVersion(db), SCHEMA_VERSION);
    assert.equal(await migrate(db), SCHEMA_VERSION);
    assert.equal(await migrate(db), SCHEMA_VERSION);
    const tables = (
      await all(db, "SELECT table_name AS name FROM information_schema.tables WHERE table_schema=?", db.schema)
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
    await db.close();
  });

  test("applies only newer migrations and rolls back a failing one", async () => {
    const db = await openTestDb();
    const extra = [
      ...MIGRATIONS,
      { version: SCHEMA_VERSION + 1, name: "add-note", sql: "ALTER TABLE sources ADD COLUMN note TEXT;" },
    ];
    assert.equal(await migrate(db, extra), SCHEMA_VERSION + 1);
    assert.equal(await migrate(db, extra), SCHEMA_VERSION + 1);
    const broken = [
      ...extra,
      { version: SCHEMA_VERSION + 2, name: "broken", sql: "CREATE TABLE ok_table (x BIGINT); SELECT * FROM nope;" },
    ];
    await assert.rejects(async () => migrate(db, broken));
    assert.equal(await schemaVersion(db), SCHEMA_VERSION + 1);
    const okTable = await one(
      db,
      "SELECT 1 FROM information_schema.tables WHERE table_schema=? AND table_name='ok_table'",
      db.schema,
    );
    assert.equal(okTable, undefined, "failed migration must roll back completely");
    await db.close();
  });

  test("state persists across reopen, and a missing schema is refused rather than created", async () => {
    const schema = await createTestSchema();
    const first = await openDb({ url: testDatabaseUrl(), schema });
    await seedSource(first);
    await first.close();
    const second = await openDb({ url: testDatabaseUrl(), schema });
    assert.equal(await schemaVersion(second), SCHEMA_VERSION);
    assert.equal((await dueSources(second, T0)).length, 1);
    await second.close();
    await assert.rejects(async () => openDb({ url: testDatabaseUrl(), schema: "no_such_schema" }), /does not exist/);
  });

  test("the writer lock serializes transactions across connections", async () => {
    const db = await openTestDb();
    const order: string[] = [];
    await Promise.all(
      ["a", "b", "c"].map((name) =>
        transaction(db, async () => {
          order.push(`${name}:start`);
          await new Promise((done) => setTimeout(done, 20));
          order.push(`${name}:end`);
        }),
      ),
    );
    for (let i = 0; i < order.length; i += 2)
      assert.equal(order[i]?.split(":")[0], order[i + 1]?.split(":")[0], order.join(" "));
    await db.close();
  });

  test("text with NUL bytes is stored without them", async () => {
    const db = await openTestDb();
    await setKv(db, "nul", "a\0b");
    assert.equal(await getKv(db, "nul"), "ab");
    await db.close();
  });
});

describe("job queue", () => {
  test("claims in run_after order, respects run_after and kinds", async () => {
    const db = await openTestDb();
    const later = await enqueueJob(db, "fetch_source", { sourceId: "b" }, { now: T0, runAfter: T0 + 60_000 });
    const first = await enqueueJob(db, "fetch_source", { sourceId: "a" }, { now: T0 });
    await enqueueJob(db, "discover_cell", { cell: "x" }, { now: T0 });

    const claimed = await claimJob<{ sourceId: string }>(db, { kinds: ["fetch_source"], now: T0 });
    assert.ok(claimed);
    assert.equal(claimed.id, first.id);
    assert.equal(claimed.payload.sourceId, "a");
    assert.equal(claimed.status, "leased");
    assert.equal(claimed.attempts, 1);
    assert.ok(claimed.leaseToken);

    assert.equal(await claimJob(db, { kinds: ["fetch_source"], now: T0 }), null, "later job is not yet runnable");
    const due = await claimJob(db, { kinds: ["fetch_source"], now: T0 + 60_000 });
    assert.equal(due?.id, later.id);
    assert.equal((await claimJob(db, { kinds: ["discover_cell"], now: T0 }))?.kind, "discover_cell");
    await db.close();
  });

  test("a leased job is not claimable until its lease expires; stale holder cannot finish", async () => {
    const db = await openTestDb();
    const job = await enqueueJob(db, "fetch_source", { sourceId: "a" }, { now: T0 });
    const a = await claimJob(db, { now: T0, leaseMs: 1000 });
    assert.equal(a?.id, job.id);
    assert.equal(await claimJob(db, { now: T0 + 999 }), null);

    const b = await claimJob(db, { now: T0 + 1000, leaseMs: 1000 });
    assert.equal(b?.id, job.id, "expired lease is reclaimed");
    assert.equal(b?.attempts, 2);
    assert.notEqual(b?.leaseToken, a?.leaseToken);

    assert.equal(await finishJob(db, job.id, a!.leaseToken!, T0 + 1001), false, "old token lost the lease");
    assert.equal(await extendLease(db, job.id, b!.leaseToken!, 5000, T0 + 1500), true);
    assert.equal(await claimJob(db, { now: T0 + 2500 }), null, "extended lease still held");
    assert.equal(await finishJob(db, job.id, b!.leaseToken!, T0 + 3000), true);
    assert.equal((await getJob(db, job.id))?.status, "done");
    assert.equal(await claimJob(db, { now: T0 + 10_000_000 }), null);
    await db.close();
  });

  test("failures back off, then go dead after max attempts", async () => {
    const db = await openTestDb();
    const job = await enqueueJob(db, "fetch_source", {}, { now: T0, maxAttempts: 2 });
    const first = (await claimJob(db, { now: T0 }))!;
    assert.equal(await failJob(db, job.id, first.leaseToken!, "boom", { now: T0 }), "queued");
    const requeued = (await getJob(db, job.id))!;
    assert.equal(requeued.lastError, "boom");
    assert.ok(requeued.runAfter > T0, "retry is delayed");
    assert.equal(await claimJob(db, { now: T0 }), null);

    const second = (await claimJob(db, { now: requeued.runAfter }))!;
    assert.equal(second.attempts, 2);
    assert.equal(await failJob(db, job.id, second.leaseToken!, "boom again", { now: requeued.runAfter }), "dead");
    assert.equal((await getJob(db, job.id))?.status, "dead");
    assert.equal(await failJob(db, job.id, second.leaseToken!, "late"), null, "no lease, no-op");

    const fatal = await enqueueJob(db, "fetch_source", {}, { now: T0 });
    const leased = (await claimJob(db, { now: T0 + 10_000_000 }))!;
    assert.equal(leased.id, fatal.id);
    assert.equal(await failJob(db, fatal.id, leased.leaseToken!, "blocked", { retry: false }), "dead");
    await db.close();
  });

  test("dedupe key collapses open jobs but allows re-enqueue after completion", async () => {
    const db = await openTestDb();
    const a = await enqueueJob(db, "fetch_source", { sourceId: "s" }, { dedupeKey: "fetch:s", now: T0 });
    const b = await enqueueJob(db, "fetch_source", { sourceId: "s" }, { dedupeKey: "fetch:s", now: T0 });
    assert.equal(a.id, b.id);
    assert.equal(await countJobs(db, { status: "queued" }), 1);
    const claimed = (await claimJob(db, { now: T0 }))!;
    assert.equal(
      (await enqueueJob(db, "fetch_source", {}, { dedupeKey: "fetch:s", now: T0 })).id,
      a.id,
      "leased is open",
    );
    await finishJob(db, claimed.id, claimed.leaseToken!, T0);
    const c = await enqueueJob(db, "fetch_source", { sourceId: "s" }, { dedupeKey: "fetch:s", now: T0 });
    assert.notEqual(c.id, a.id);
    await db.close();
  });
});

describe("repositories", () => {
  test("sources canonicalize URLs, dedupe, and require a venue unless listing", async () => {
    const db = await openTestDb();
    const source = await seedSource(db);
    assert.equal(source.url, "https://example-room.test/calendar");
    assert.equal(source.venueId, "venue-1");
    const again = await addSource(db, {
      venueId: "venue-1",
      kind: "html",
      url: "https://example-room.test/calendar",
      timezone: "America/Chicago",
    });
    assert.equal(again.id, source.id);
    await assert.rejects(async () =>
      addSource(db, { venueId: null, kind: "html", url: "https://x.test/", timezone: "America/Chicago" }),
    );
    const listing = await addSource(db, {
      venueId: null,
      kind: "listing",
      url: "https://altweekly.test/music",
      timezone: "America/Chicago",
    });
    assert.equal(listing.venueId, null);

    assert.equal((await dueSources(db, T0)).length, 2);
    await saveFetchState(db, source.id, { lastFetchAt: T0, etag: '"abc"', successfulFetches: 1 });
    assert.deepEqual(
      (await dueSources(db, T0 + 1000)).map((s) => s.id),
      [listing.id],
    );
    assert.equal((await dueSources(db, T0 + source.fetchIntervalMs)).length, 2);
    const state = await getFetchState(db, source.id);
    assert.equal(state.etag, '"abc"');
    assert.equal(state.consecutiveZeroResults, 0);
    await saveFetchState(db, source.id, { consecutiveZeroResults: 2 });
    assert.equal((await getFetchState(db, source.id)).etag, '"abc"', "patch keeps other fields");
    await db.close();
  });

  test("raw pages are content addressed", async () => {
    const db = await openTestDb();
    const bytes = new TextEncoder().encode("<html>hi</html>");
    const sha = await putRawPage(db, { url: "https://x.test/", contentType: "text/html", bytes }, T0);
    assert.equal(await putRawPage(db, { url: "https://x.test/again", contentType: "text/html", bytes }, T0), sha);
    const page = await getRawPage(db, sha);
    assert.equal(new TextDecoder().decode(page!.bytes), "<html>hi</html>");
    await db.close();
  });

  test("events upsert, changes and outbox dedupe", async () => {
    const db = await openTestDb();
    await seedSource(db);
    const event = sampleEvent();
    const stored = await upsertEvent(db, event, { now: T0 });
    assert.equal(stored.status, "active");
    assert.equal(stored.missCount, 0);
    assert.equal(stored.contentHash, eventContentHash(event));
    assert.deepEqual(stored.data.prices, event.prices);

    const same = await upsertEvent(db, { ...event, warnings: ["noise"] }, { now: T0 + 1 });
    assert.equal(same.contentHash, stored.contentHash, "warnings don't change the content hash");
    assert.equal(same.lastChangedAt, T0);

    const changedPrice = sampleEvent({
      prices: [{ kind: "advance", minCents: 1800, maxCents: 1800, currency: "USD", text: "$18 adv" }],
    });
    const updated = await upsertEvent(db, changedPrice, { now: T0 + 2 });
    assert.notEqual(updated.contentHash, stored.contentHash, "nested price change alters hash");
    assert.equal(updated.lastChangedAt, T0 + 2);

    await recordEventChange(db, {
      eventId: updated.id,
      sourceId: "src-1",
      identityKey: event.identityKey,
      change: "updated",
      before: event,
      after: changedPrice,
    });
    assert.equal((await listSourceEvents(db, "src-1", ["active"])).length, 1);

    const first = await enqueueOutbox(db, {
      eventId: updated.id,
      change: "new",
      event: changedPrice,
      observedAt: T0,
      evidenceSha256: null,
    });
    assert.ok(first);
    const dup = await enqueueOutbox(db, {
      eventId: updated.id,
      change: "new",
      event: changedPrice,
      observedAt: T0 + 5,
      evidenceSha256: null,
    });
    assert.equal(dup, null);
    const pending = await pendingOutbox(db);
    assert.equal(pending.length, 1);
    assert.equal(pending[0]?.event.title, "The Example Band");
    await markOutboxPublished(db, [first]);
    assert.equal((await pendingOutbox(db)).length, 0);
    await db.close();
  });

  test("alerts dedupe while open", async () => {
    const db = await openTestDb();
    await seedSource(db);
    const a = await raiseAlert(db, { kind: "zero_results", sourceId: "src-1", message: "0 events" }, T0);
    const b = await raiseAlert(db, { kind: "zero_results", sourceId: "src-1", message: "0 events again" }, T0 + 1);
    assert.equal(a.id, b.id);
    assert.equal((await listAlerts(db, { open: true })).length, 1);
    assert.equal(await resolveAlerts(db, { sourceId: "src-1", kind: "zero_results" }, T0 + 2), 1);
    const c = await raiseAlert(db, { kind: "zero_results", sourceId: "src-1", message: "again" }, T0 + 3);
    assert.notEqual(c.id, a.id);
    await db.close();
  });

  test("candidates and place-id aliases resolve many ids to one owner", async () => {
    const db = await openTestDb();
    const candidate = await insertCandidate(
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

    await upsertPlaceAlias(db, {
      placeId: "ChIJ-premise",
      candidateId: candidate.id,
      venueId: null,
      isCanonical: false,
    });
    await upsertPlaceAlias(db, {
      placeId: "ChIJ-business",
      candidateId: candidate.id,
      venueId: null,
      isCanonical: true,
      types: ["night_club", "bar"],
    });
    await upsertPlaceAlias(db, {
      placeId: "ChIJ-address",
      candidateId: candidate.id,
      venueId: null,
      isCanonical: false,
    });
    assert.equal((await resolvePlaceId(db, "ChIJ-premise"))?.candidateId, candidate.id);
    assert.equal(await resolvePlaceId(db, "ChIJ-unknown"), null);
    const aliases = await listPlaceAliases(db, { candidateId: candidate.id });
    assert.equal(aliases.length, 3);
    assert.equal(aliases.filter((alias) => alias.isCanonical).length, 1);
    assert.equal(aliases[0]?.placeId, "ChIJ-business");
    assert.deepEqual(aliases[0]?.types, ["night_club", "bar"]);

    await upsertPlaceAlias(db, {
      placeId: "ChIJ-premise",
      candidateId: candidate.id,
      venueId: null,
      isCanonical: true,
    });
    assert.equal((await listPlaceAliases(db, { candidateId: candidate.id })).filter((a) => a.isCanonical).length, 1);
    await assert.rejects(async () =>
      upsertPlaceAlias(db, { placeId: "x", candidateId: null, venueId: null, isCanonical: false }),
    );

    const updated = await updateCandidate(
      db,
      candidate.id,
      { status: "promoted", provenEventCount: 4, website: "https://hifi-annex.test", evidence: { ok: true } },
      T0 + 5,
    );
    assert.equal(updated.status, "promoted");
    assert.equal(updated.websiteDomain, "hifi-annex.test");
    assert.deepEqual((await getCandidate(db, candidate.id))?.evidence, { ok: true });
    await db.close();
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
