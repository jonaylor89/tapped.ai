import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, test } from "node:test";
import { main } from "../src/cli.js";
import { addSource, type Db, enqueueOutbox, openDb, pendingOutbox, upsertEvent, upsertVenues } from "../src/db.js";
import { findKnownEvent, knownEventsProblem, syncKnownEvents, titlesMatch } from "../src/publish/known-events.js";
import { publishOutbox } from "../src/publish/publisher.js";
import { reconcileSource } from "../src/reconcile/reconcile.js";
import type { ExtractedEvent, Publisher, Source, ValidatedEvent } from "../src/types.js";
import { validateEvent } from "../src/validate/validate.js";

const HOUR = 60 * 60 * 1000;
const T0 = new Date("2026-11-03T15:00:00Z");

function setup(): { db: Db; source: Source } {
  const db = openDb(":memory:");
  upsertVenues(db, [
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
  const source = addSource(
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

/** Rows shaped like `scraped_events` from the read-only Postgres query. */
const LEGACY_ROWS = [
  // Stored by the legacy crawler at 00:00 UTC: 19:00 the previous evening in New York.
  {
    source: "event-crawler",
    source_key: "k1",
    venue_id: "venue-1",
    start_time: new Date("2026-11-08T00:00:00Z"),
    title: "moe. at The Example Room",
    event_url: null,
  },
  // Untitled iCal leftover whose URL is the shared calendar page.
  {
    source: "event-crawler",
    source_key: "k2",
    venue_id: "venue-1",
    start_time: new Date("2026-11-12T23:00:00Z"),
    title: "",
    event_url: "https://example-room.test/shows",
  },
  // This scraper's own earlier delivery.
  {
    source: "event-scraper",
    source_key: "k3",
    venue_id: "venue-1",
    start_time: new Date("2026-11-20T00:30:00Z"),
    title: "Own Show",
    event_url: null,
  },
];

async function synced() {
  const { db, source } = setup();
  const result = await syncKnownEvents(db, { query: async () => ({ rows: LEGACY_ROWS }) }, T0.getTime());
  assert.equal(result.knownEvents, 3);
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

  test("sync is required: never synced, then fresh, then stale after 24h", async () => {
    const { db } = setup();
    assert.equal(knownEventsProblem(db, T0.getTime()), "never_synced");
    await syncKnownEvents(db, { query: async () => ({ rows: [] }) }, T0.getTime());
    assert.equal(knownEventsProblem(db, T0.getTime() + 23 * HOUR), null);
    assert.equal(knownEventsProblem(db, T0.getTime() + 25 * HOUR), "stale");
  });

  test("an event production already has is matched across a shifted legacy instant", async () => {
    const { db, source } = await synced();
    assert.equal(findKnownEvent(db, make(source, "moe.", "2026-11-07T20:00"))?.originKey, "k1");
    assert.equal(findKnownEvent(db, make(source, "moe.", "2026-11-08T20:00"))?.originKey, "k1");
    assert.equal(findKnownEvent(db, make(source, "moe.", "2026-11-14T20:00")), null);
    assert.equal(findKnownEvent(db, make(source, "Other Band", "2026-11-07T20:00")), null);
  });

  test("an untitled stored event matches its URL only on the exact local date", async () => {
    const { db, source } = await synced();
    const url = { eventUrl: "https://example-room.test/shows" };
    assert.equal(findKnownEvent(db, make(source, "Any Band", "2026-11-12T19:00", url))?.originKey, "k2");
    assert.equal(findKnownEvent(db, make(source, "Any Band", "2026-11-13T19:00", url)), null);
  });

  test("reconcile drops events production has: not stored, not queued", async () => {
    const { db, source } = await synced();
    const result = reconcileSource(db, {
      source,
      now: T0,
      events: [make(source, "moe.", "2026-11-07T20:00"), make(source, "Brand New Band", "2026-11-09T20:00")],
    });
    assert.equal(result.counts.alreadyInProduction, 1);
    assert.equal(result.counts.new, 1);
    assert.deepEqual(
      pendingOutbox(db).map((item) => item.event.title),
      ["Brand New Band"],
    );
  });

  test("publish drops rows queued before the sync that another crawler already published; own rows still go", async () => {
    const { db, source } = setup();
    for (const event of [
      make(source, "moe.", "2026-11-07T20:00"),
      make(source, "Own Show", "2026-11-19T19:30"),
      make(source, "Brand New Band", "2026-11-09T20:00"),
    ]) {
      const stored = upsertEvent(db, event, { now: T0.getTime() });
      enqueueOutbox(
        db,
        { eventId: stored.id, change: "new", event, observedAt: T0.getTime(), evidenceSha256: null },
        T0.getTime(),
      );
    }
    await syncKnownEvents(db, { query: async () => ({ rows: LEGACY_ROWS }) }, T0.getTime());
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
    assert.equal(pendingOutbox(db).length, 0);
  });

  test("run-once and publish refuse without a sync; the offline opt-out never applies to postgres publishing", async () => {
    const dir = mkdtempSync(join(tmpdir(), "event-scraper-known-"));
    const base = { EVENT_SCRAPER_DB: join(dir, "db.sqlite"), EVENT_SCRAPER_DATA_DIR: dir, EVENT_SCRAPER_OSM: "0" };
    const errors: string[] = [];
    const io = {
      services: { llm: null, venueSnapshot: null, knownEvents: null, clock: { now: () => T0 } },
      stdout: () => {},
      stderr: (text: string) => errors.push(text),
    };
    assert.equal(await main(["run-once"], { env: base, ...io }), 2);
    assert.match(errors.join(""), /not synced/);
    const postgres = {
      ...base,
      EVENT_SCRAPER_PUBLISH: "postgres",
      INGESTION_DATABASE_URL: "postgres://unused.invalid/none",
      EVENT_SCRAPER_KNOWN_EVENTS: "off",
    };
    const neverSends: Publisher = {
      name: "never",
      publish: async () => {
        throw new Error("must not publish");
      },
    };
    errors.length = 0;
    assert.equal(
      await main(["publish"], { env: postgres, ...io, services: { ...io.services, publisher: neverSends } }),
      2,
    );
    assert.match(errors.join(""), /not synced/);
    assert.equal(await main(["run-once"], { env: { ...base, EVENT_SCRAPER_KNOWN_EVENTS: "off" }, ...io }), 0);
  });
});
