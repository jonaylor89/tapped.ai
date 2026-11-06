import assert from "node:assert/strict";
import { describe, test } from "node:test";
import {
  addSource,
  type Db,
  getEventByIdentity,
  getFetchState,
  listAlerts,
  listEventChanges,
  pendingOutbox,
  saveFetchState,
  upsertVenues,
} from "../src/db.js";
import { computeIdentityKey, normalizeTitle } from "../src/reconcile/identity.js";
import { reconcileSource } from "../src/reconcile/reconcile.js";
import type { ExtractedEvent, Source, ValidatedEvent } from "../src/types.js";
import { validateEvent } from "../src/validate/validate.js";
import { openTestDb } from "./helpers/db.js";

const DAY = 24 * 60 * 60 * 1000;
const T0 = new Date("2026-11-02T15:00:00Z");
const at = (days: number) => new Date(T0.getTime() + days * DAY);

async function setup(): Promise<{ db: Db; source: Source }> {
  const db = await openTestDb();
  await upsertVenues(db, [
    {
      id: "venue-1",
      name: "The Example Room",
      address: null,
      lat: null,
      lng: null,
      website: "https://example-room.test",
      googlePlaceId: null,
      timezone: "America/Chicago",
      syncedAt: 0,
    },
  ]);
  const source = await addSource(
    db,
    {
      id: "src-1",
      venueId: "venue-1",
      kind: "html",
      url: "https://example-room.test/shows",
      timezone: "America/Chicago",
    },
    T0.getTime(),
  );
  return { db, source };
}

function make(
  source: Source,
  title: string,
  start: string,
  now: Date = T0,
  extra: Partial<ExtractedEvent> = {},
): ValidatedEvent {
  const outcome = validateEvent(
    {
      title,
      start,
      timezone: null,
      startInstant: null,
      end: null,
      doors: null,
      description: null,
      imageUrl: null,
      eventUrl: null,
      ticketUrl: null,
      performers: [],
      prices: [],
      isFree: null,
      status: null,
      category: null,
      evidence: [],
      extractor: "jsonld",
      sourceEventId: null,
      rawDateText: null,
      ...extra,
    },
    { source, timezone: source.timezone, now },
  );
  if (!outcome.ok) throw new Error(outcome.reasons.join(","));
  return outcome.event;
}

describe("identity", () => {
  test("normalizeTitle ignores status prefixes, case, punctuation and leading 'the'", () => {
    assert.equal(normalizeTitle("SOLD OUT: The Example Band!"), "example band");
    assert.equal(normalizeTitle("Cancelled - Example Band (21+)"), "example band");
  });

  test("listing sources without a venue scope keys by source", () => {
    const key = computeIdentityKey({ venueId: null, sourceId: "s9", startLocal: "2026-11-07", title: "Show" });
    assert.equal(key, "src:s9|2026-11-07|-|show");
  });
});

describe("reconcileSource", () => {
  test("new -> unchanged -> updated, with change log and outbox", async () => {
    const { db, source } = await setup();
    const a = make(source, "Band A", "2026-11-07T20:00");
    const b = make(source, "Band B", "2026-11-08T20:00");

    const first = await reconcileSource(db, { source, events: [a, b], now: T0, evidenceSha256: "abc" });
    assert.equal(first.counts.new, 2);
    assert.equal((await pendingOutbox(db)).length, 2);
    assert.equal((await pendingOutbox(db))[0]?.evidenceSha256, "abc");

    const second = await reconcileSource(db, { source, events: [a, b], now: at(0.25) });
    assert.equal(second.counts.unchanged, 2);
    assert.equal((await pendingOutbox(db)).length, 2);

    const a2 = { ...a, description: "Now with special guests" };
    const third = await reconcileSource(db, { source, events: [a2, b], now: at(0.5) });
    assert.equal(third.counts.updated, 1);
    assert.equal(third.counts.unchanged, 1);
    assert.deepEqual(
      (await listEventChanges(db, { sourceId: source.id })).map((c) => c.change),
      ["new", "new", "updated"],
    );
    assert.equal((await pendingOutbox(db)).length, 3);
    assert.equal((await getFetchState(db, source.id)).maxEventCount, 2);
  });

  test("cancel only after 2 consecutive successful misses; a sighting resets the counter", async () => {
    const { db, source } = await setup();
    const a = make(source, "Band A", "2026-11-07T20:00");
    const b = make(source, "Band B", "2026-11-08T20:00");
    const c = make(source, "Band C", "2026-11-20T20:00");
    await reconcileSource(db, { source, events: [a, b, c], now: T0 });

    let r = await reconcileSource(db, { source, events: [a, c], now: at(0.25) });
    assert.equal(r.counts.missed, 1);
    assert.equal(r.counts.canceled, 0);
    assert.equal((await getEventByIdentity(db, source.id, b.identityKey))?.missCount, 1);

    // Seen again: counter resets.
    await reconcileSource(db, { source, events: [a, b, c], now: at(0.5) });
    assert.equal((await getEventByIdentity(db, source.id, b.identityKey))?.missCount, 0);

    await reconcileSource(db, { source, events: [a, c], now: at(0.75) });
    r = await reconcileSource(db, { source, events: [a, c], now: at(1) });
    assert.equal(r.counts.canceled, 1);
    const stored = await getEventByIdentity(db, source.id, b.identityKey);
    assert.equal(stored?.status, "canceled");
    const outbox = (await pendingOutbox(db)).filter((o) => o.change === "canceled");
    assert.equal(outbox.length, 1);
    assert.equal(outbox[0]?.event.status, "canceled");

    // It comes back.
    r = await reconcileSource(db, { source, events: [a, b, c], now: at(1.25) });
    assert.equal(r.counts.reappeared, 1);
    assert.equal((await getEventByIdentity(db, source.id, b.identityKey))?.status, "active");
  });

  test("zero results on a productive source raise an alert and cancel nothing", async () => {
    const { db, source } = await setup();
    const a = make(source, "Band A", "2026-11-07T20:00");
    await reconcileSource(db, { source, events: [a], now: T0 });
    for (let i = 1; i <= 3; i++) {
      const r = await reconcileSource(db, { source, events: [], now: at(i * 0.1) });
      assert.equal(r.zeroResults, true);
      assert.ok(r.alert);
    }
    assert.equal((await getEventByIdentity(db, source.id, a.identityKey))?.status, "active");
    assert.equal((await getEventByIdentity(db, source.id, a.identityKey))?.missCount, 0);
    const alerts = await listAlerts(db, { open: true, kind: "zero_results" });
    assert.equal(alerts.length, 1);
    assert.equal((await getFetchState(db, source.id)).consecutiveZeroResults, 3);

    // Productive again: alert resolved, counter reset.
    await reconcileSource(db, { source, events: [a], now: at(0.5) });
    assert.equal((await listAlerts(db, { open: true, kind: "zero_results" })).length, 0);
    assert.equal((await getFetchState(db, source.id)).consecutiveZeroResults, 0);
  });

  test("zero results on a never-productive source: no alert", async () => {
    const { db, source } = await setup();
    const r = await reconcileSource(db, { source, events: [], now: T0 });
    assert.equal(r.alert, null);
    assert.equal((await listAlerts(db)).length, 0);
  });

  test("past events are never canceled; they expire to 'past'", async () => {
    const { db, source } = await setup();
    const soon = make(source, "Band A", "2026-11-03T20:00");
    const later = make(source, "Band B", "2026-11-20T20:00");
    await reconcileSource(db, { source, events: [soon, later], now: T0 });

    // After the show starts it drops off the page: not a miss.
    const afterShow = new Date("2026-11-04T05:00:00Z"); // 23:00 Chicago on Nov 3
    await reconcileSource(db, { source, events: [later], now: afterShow });
    await reconcileSource(db, { source, events: [later], now: new Date(afterShow.getTime() + 3600_000) });
    assert.equal((await getEventByIdentity(db, source.id, soon.identityKey))?.status, "active");
    assert.equal((await getEventByIdentity(db, source.id, soon.identityKey))?.missCount, 0);

    // Two days later it is expired to 'past'.
    const r = await reconcileSource(db, { source, events: [later], now: at(3) });
    assert.equal(r.counts.expired, 1);
    assert.equal((await getEventByIdentity(db, source.id, soon.identityKey))?.status, "past");
    assert.equal((await pendingOutbox(db)).filter((o) => o.change === "canceled").length, 0);
  });

  test("events beyond the window covered by this fetch are not counted as missing", async () => {
    const { db, source } = await setup();
    const a = make(source, "Band A", "2026-11-07T20:00");
    const far = make(source, "Band Far", "2027-03-01T20:00");
    await reconcileSource(db, { source, events: [a, far], now: T0 });
    // Page now only shows November.
    await reconcileSource(db, { source, events: [a], now: at(0.25) });
    const r = await reconcileSource(db, { source, events: [a], now: at(0.5) });
    assert.equal(r.counts.outsideWindow, 1);
    assert.equal((await getEventByIdentity(db, source.id, far.identityKey))?.status, "active");
  });

  test("site-declared cancellation is immediate; brand-new identities are 'new'", async () => {
    const { db, source } = await setup();
    const a = make(source, "Band A", "2026-11-07T20:00");
    await reconcileSource(db, { source, events: [a], now: T0 });
    const canceled = make(source, "CANCELED: Band A", "2026-11-07T20:00");
    assert.equal(canceled.identityKey, a.identityKey);
    const r = await reconcileSource(db, { source, events: [canceled], now: at(0.25) });
    assert.equal(r.counts.canceled, 1);
    assert.equal((await getEventByIdentity(db, source.id, a.identityKey))?.status, "canceled");
  });

  test("enqueue:false records changes without outbox rows; updateFetchState:false leaves counts alone", async () => {
    const { db, source } = await setup();
    await saveFetchState(db, source.id, { maxEventCount: 7 });
    const a = make(source, "Band A", "2026-11-07T20:00");
    await reconcileSource(db, { source, events: [a], now: T0, enqueue: false, updateFetchState: false });
    assert.equal((await pendingOutbox(db)).length, 0);
    assert.equal((await listEventChanges(db)).length, 1);
    assert.equal((await getFetchState(db, source.id)).lastEventCount, null);
  });
});
