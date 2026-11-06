import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { addSource, type Db, enqueueOutbox, pendingOutbox, run, upsertEvent, upsertVenues } from "../src/db.js";
import { findKnownEvent, titlesMatch } from "../src/publish/known-events.js";
import { publishOutbox } from "../src/publish/publisher.js";
import { reconcileSource } from "../src/reconcile/reconcile.js";
import type { ExtractedEvent, Publisher, Source, ValidatedEvent } from "../src/types.js";
import { validateEvent } from "../src/validate/validate.js";
import { openTestDb } from "./helpers/db.js";

const _HOUR = 60 * 60 * 1000;
const T0 = new Date("2026-11-03T15:00:00Z");

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
      timezone: "America/New_York",
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
      timezone: "America/New_York",
    },
    T0.getTime(),
  );
  return { db, source };
}

function make(source: Source, title: string, start: string, extra: Partial<ExtractedEvent> = {}): ValidatedEvent {
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
      performers: ["Someone"],
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
    { source, timezone: source.timezone, now: T0 },
  );
  if (!outcome.ok) throw new Error(outcome.reasons.join(","));
  return outcome.event;
}

/** Rows the way production's `scraped_events` holds them. */
const PRODUCTION_ROWS = [
  // Stored by the legacy crawler at 00:00 UTC: 19:00 the previous evening in New York.
  ["event-crawler", "k1", "venue-1", "2026-11-08T00:00:00Z", "moe. at The Example Room", null],
  // Untitled iCal leftover whose URL is the shared calendar page.
  ["event-crawler", "k2", "venue-1", "2026-11-12T23:00:00Z", "", "https://example-room.test/shows"],
  // This scraper's own earlier delivery.
  ["event-scraper", "k3", "venue-1", "2026-11-20T00:30:00Z", "Own Show", null],
  // Same URL as an incoming event, no venue on the production row, stored with a trailing slash.
  ["event-crawler", "k4", null, "2026-11-25T00:30:00Z", "Listing Show", "https://example-room.test/e/listing/"],
];

async function seedProduction(db: Db) {
  for (const row of PRODUCTION_ROWS) {
    await run(
      db,
      "INSERT INTO scraped_events (source,source_key,venue_id,start_time,title,event_url) VALUES (?,?,?,?::timestamptz,?,?)",
      ...(row as string[]),
    );
  }
}

async function seeded() {
  const { db, source } = await setup();
  await seedProduction(db);
  return { db, source };
}

describe("known production events", () => {
  test("title matching: normalized equality or every word of the shorter title in the longer", () => {
    assert.ok(titlesMatch("moe", "moe at example room"));
    assert.ok(titlesMatch("jazz night", "jazz night"));
    assert.ok(!titlesMatch("jazz night", "blues night"));
    assert.ok(!titlesMatch("", "anything"));
    assert.ok(!titlesMatch("dj", "dj night"));
  });

  test("an event production already has is matched across a shifted legacy instant", async () => {
    const { db, source } = await seeded();
    assert.equal((await findKnownEvent(db, make(source, "moe.", "2026-11-07T20:00")))?.originKey, "k1");
    assert.equal((await findKnownEvent(db, make(source, "moe.", "2026-11-08T20:00")))?.originKey, "k1");
    assert.equal(await findKnownEvent(db, make(source, "moe.", "2026-11-14T20:00")), null);
    assert.equal(await findKnownEvent(db, make(source, "Other Band", "2026-11-07T20:00")), null);
  });

  test("an untitled stored event matches its URL only on the exact local date", async () => {
    const { db, source } = await seeded();
    const url = { eventUrl: "https://example-room.test/shows" };
    assert.equal((await findKnownEvent(db, make(source, "Any Band", "2026-11-12T19:00", url)))?.originKey, "k2");
    assert.equal(await findKnownEvent(db, make(source, "Any Band", "2026-11-13T19:00", url)), null);
  });

  test("a venue-less production row is found by its URL, however it was spelled", async () => {
    const { db, source } = await seeded();
    const url = { eventUrl: "https://example-room.test/e/listing" };
    assert.equal((await findKnownEvent(db, make(source, "Listing Show", "2026-11-24T19:30", url)))?.originKey, "k4");
  });

  test("reconcile drops events production has: not stored, not queued", async () => {
    const { db, source } = await seeded();
    const result = await reconcileSource(db, {
      source,
      now: T0,
      events: [make(source, "moe.", "2026-11-07T20:00"), make(source, "Brand New Band", "2026-11-09T20:00")],
    });
    assert.equal(result.counts.alreadyInProduction, 1);
    assert.equal(result.counts.new, 1);
    assert.deepEqual(
      (await pendingOutbox(db)).map((item) => item.event.title),
      ["Brand New Band"],
    );
  });

  test("publish drops rows another crawler's event now covers; this scraper's own rows still go", async () => {
    const { db, source } = await setup();
    for (const event of [
      make(source, "moe.", "2026-11-07T20:00"),
      make(source, "Own Show", "2026-11-19T19:30"),
      make(source, "Brand New Band", "2026-11-09T20:00"),
    ]) {
      const stored = await upsertEvent(db, event, { now: T0.getTime() });
      await enqueueOutbox(
        db,
        { eventId: stored.id, change: "new", event, observedAt: T0.getTime(), evidenceSha256: null },
        T0.getTime(),
      );
    }
    await seedProduction(db);
    const sent: string[] = [];
    const publisher: Publisher = {
      name: "fake",
      publish: async (items) => {
        sent.push(...items.map((item) => item.event.title));
        return items.map((item) => ({ outboxId: item.id, ok: true }));
      },
    };
    const result = await publishOutbox(db, publisher, { now: () => T0.getTime() });
    assert.equal(result.alreadyInProduction, 1);
    assert.deepEqual(sent.sort(), ["Brand New Band", "Own Show"]);
    assert.equal((await pendingOutbox(db)).length, 0);
  });

  test("the run fails when production's events cannot be read, instead of continuing unchecked", async () => {
    const { db, source } = await setup();
    await run(db, "DROP TABLE scraped_events");
    await assert.rejects(async () =>
      reconcileSource(db, { source, now: T0, events: [make(source, "Brand New Band", "2026-11-09T20:00")] }),
    );
    assert.equal((await pendingOutbox(db)).length, 0);
  });
});
