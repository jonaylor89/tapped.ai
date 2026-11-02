import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import type { EvidenceRef, EvidenceStore, ObservationInput } from "@tapped/postgres-ingestion";
import { normalizeObservation } from "@tapped/postgres-ingestion";
import type { Pool } from "pg";
import {
  addSource,
  enqueueOutbox,
  getVenue,
  listAlerts,
  listPlaceAliases,
  openDb,
  pendingOutbox,
  putRawPage,
  resolvePlaceId,
  upsertEvent,
} from "../src/db.js";
import {
  type CaptureFn,
  localToUtc,
  NdjsonPublisher,
  PostgresIngestionPublisher,
  publishOutbox,
  toObservationInput,
} from "../src/publish/publisher.js";
import {
  JsonFileVenueSnapshot,
  PostgresVenueSnapshot,
  syncVenueSnapshot,
  VENUE_SNAPSHOT_SQL,
} from "../src/publish/venues-snapshot.js";
import type { OutboxItem, Publisher, ValidatedEvent } from "../src/types.js";

const fixtures = fileURLToPath(new URL("./fixtures/publish/", import.meta.url));
const NOW = Date.parse("2026-06-02T18:00:00Z");
const clock = { now: () => new Date(NOW) };

function validated(patch: Partial<ValidatedEvent> = {}): ValidatedEvent {
  return {
    identityKey: "2026-11-07|20:00|nova quartet",
    sourceId: "src-1",
    venueId: "venue-hifi",
    title: "Nova Quartet",
    startLocal: "2026-11-07T20:00",
    startUtc: "2026-11-08T02:00:00.000Z",
    datePrecision: "instant",
    endLocal: null,
    endUtc: null,
    doorsLocal: "2026-11-07T19:00",
    timezone: "America/Chicago",
    description: "Jazz night",
    imageUrl: "https://venue.example/nova.jpg",
    eventUrl: "https://venue.example/events/nova",
    ticketUrl: "https://www.ticketmaster.com/nova",
    performers: ["Nova Quartet"],
    prices: [
      { kind: "advance", minCents: 1500, maxCents: 1500, currency: "USD", text: "$15 adv" },
      { kind: "door", minCents: 2000, maxCents: 2000, currency: null, text: null },
    ],
    isFree: false,
    status: "sold_out",
    category: "music",
    isMusic: true,
    evidence: ["Nova Quartet - Sat Nov 7, 8pm"],
    extractor: "ical",
    sourceEventId: "evt-1@venue.example",
    warnings: [],
    ...patch,
  };
}

function item(id: number, patch: Partial<OutboxItem> = {}, event: Partial<ValidatedEvent> = {}): OutboxItem {
  const ev = validated(event);
  return {
    id,
    eventId: id,
    sourceId: ev.sourceId,
    venueId: ev.venueId,
    identityKey: ev.identityKey,
    change: "new",
    event: ev,
    observedAt: Date.parse("2026-06-01T17:00:00Z"),
    evidenceSha256: "page-sha",
    attempts: 0,
    createdAt: NOW,
    ...patch,
  };
}

const page = { bytes: readFileSync(join(fixtures, "page.ics")), contentType: "text/calendar" };
const evidence = (sha: string) => (sha === "page-sha" ? page : null);

function fakeCapture(fail?: (inputs: ObservationInput[]) => Error | null) {
  const calls: { inputs: ObservationInput[]; raw: Buffer; contentType: string }[] = [];
  const capture: CaptureFn = async (_pool, _store, inputs, raw, options) => {
    const error = fail?.(inputs);
    if (error) throw error;
    for (const input of inputs) normalizeObservation(input);
    calls.push({ inputs, raw, contentType: options.contentType });
    return inputs.map((_, i) => ({ observation_id: `o${i}`, event_id: `e${i}`, action: "inserted", issues: [] }));
  };
  return { capture, calls };
}

const noPool = {} as Pool;
const noStore: EvidenceStore = {
  put: async () => {
    throw new Error("store should not be reached");
  },
};

describe("envelope mapping", () => {
  test("maps a validated event to a v2 usd_cent observation envelope", () => {
    const input = toObservationInput(item(1));
    assert.equal(input.source, "event-scraper");
    assert.equal(input.sourceKey, "src-1#2026-11-07|20:00|nova quartet");
    assert.equal(input.observedAt, "2026-06-01T17:00:00.000Z");
    assert.equal(input.parserVersion, "event-scraper-v1:ical");
    assert.equal(input.normalizationVersion, 2);
    assert.equal(input.inputPriceUnit, "usd_cent");
    assert.equal(input.venueRoutingStatus, "resolved");
    assert.equal(input.venueId, "venue-hifi");
    assert.match(input.deliveryKey, /^[a-f0-9]{64}$/);

    const normalized = normalizeObservation(input);
    assert.deepEqual(normalized.errors, []);
    const facts = normalized.facts as unknown as Record<string, unknown>;
    assert.equal(facts.startTime, "2026-11-08T02:00:00.000Z");
    assert.equal(facts.musicClassification, "music");
    assert.equal(facts.status, "scheduled", "sold_out still takes place");
    assert.equal(facts.datePrecision, "instant");
    assert.equal(facts.flierUrl, "https://venue.example/nova.jpg");
    assert.deepEqual(facts.prices, [
      { kind: "ticket", amountMinCents: 1500, amountMaxCents: 1500, currency: "USD", description: "$15 adv" },
      { kind: "door", amountMinCents: 2000, amountMaxCents: 2000, currency: "USD", description: null },
    ]);
    // The ticket link is provenance only; it is never the event URL.
    assert.equal(input.data.ticketUrl, "https://www.ticketmaster.com/nova");
    assert.equal(facts.url, "https://venue.example/events/nova");
  });

  test("delivery key is stable across retries and outbox ids, and changes with content", () => {
    const a = toObservationInput(item(1));
    assert.equal(toObservationInput(item(99, { attempts: 3 })).deliveryKey, a.deliveryKey);
    assert.notEqual(toObservationInput(item(1, {}, { title: "Nova Quartet (late show)" })).deliveryKey, a.deliveryKey);
    assert.notEqual(toObservationInput(item(1, { observedAt: NOW })).deliveryKey, a.deliveryKey);
  });

  test("date-only events become local midnight instants with date precision", () => {
    const input = toObservationInput(item(1, {}, { startLocal: "2026-11-07", startUtc: null, datePrecision: "date" }));
    const normalized = normalizeObservation(input);
    assert.deepEqual(normalized.errors, []);
    assert.equal(normalized.facts.startTime, "2026-11-07T06:00:00.000Z");
    assert.equal(normalized.facts.datePrecision, "date");
  });

  test("canceled changes, free events and non-music kept categories", () => {
    const canceled = normalizeObservation(toObservationInput(item(1, { change: "canceled" })));
    assert.equal(canceled.facts.status, "canceled");
    const free = normalizeObservation(
      toObservationInput(item(2, {}, { prices: [], isFree: true, category: "comedy", isMusic: false })),
    );
    assert.equal(free.facts.musicClassification, "non_music");
    assert.deepEqual(free.facts.prices, [
      { kind: "ticket", amountMinCents: 0, amountMaxCents: 0, currency: "USD", description: "free" },
    ]);
  });

  test("non-USD currency is held by production normalization, not relabeled", () => {
    const input = toObservationInput(
      item(1, {}, { prices: [{ kind: "ticket", minCents: 1000, maxCents: 1000, currency: "EUR", text: null }] }),
    );
    assert.ok(normalizeObservation(input).errors.includes("unsupported_currency"));
  });

  test("localToUtc handles DST and rejects malformed input", () => {
    assert.equal(localToUtc("2026-07-04T20:00", "America/Chicago"), "2026-07-05T01:00:00.000Z");
    assert.equal(localToUtc("2026-03-08T03:30", "America/Chicago"), "2026-03-08T08:30:00.000Z");
    assert.equal(localToUtc("2026-11-01T01:30", "America/New_York")?.slice(0, 13), "2026-11-01T05");
    assert.equal(localToUtc("Nov 7", "America/Chicago"), null);
    assert.equal(localToUtc("2026-11-07", "Not/AZone"), null);
  });
});

describe("PostgresIngestionPublisher", () => {
  test("groups by evidence page and sends raw page bytes as one capture call", async () => {
    const { capture, calls } = fakeCapture();
    const publisher = new PostgresIngestionPublisher({ pool: noPool, store: noStore, capture });
    const outcomes = await publisher.publish(
      [item(1), item(2, { identityKey: "b" }, { identityKey: "b", title: "Second" })],
      evidence,
    );
    assert.deepEqual(
      outcomes.map((o) => o.ok),
      [true, true],
    );
    assert.equal(calls.length, 1);
    assert.equal(calls[0].contentType, "text/calendar");
    assert.deepEqual(calls[0].raw, page.bytes);
    assert.equal(calls[0].inputs.length, 2);
    assert.equal(outcomes[0].message, "inserted=2");
  });

  test("missing evidence falls back to an NDJSON evidence object with evidence lines", async () => {
    const { capture, calls } = fakeCapture();
    const publisher = new PostgresIngestionPublisher({ pool: noPool, store: noStore, capture });
    await publisher.publish([item(1, { evidenceSha256: null }), item(2, { evidenceSha256: "pruned" })], evidence);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].contentType, "application/x-ndjson");
    assert.deepEqual(
      calls[0].inputs.map((input) => input.evidenceLine),
      [1, 2],
    );
    const lines = calls[0].raw.toString("utf8").trim().split("\n");
    assert.equal(JSON.parse(lines[1]).title, "Nova Quartet");
  });

  test("failures are per call, secret-free, and venue-less listing events are skipped", async () => {
    const secret = Object.assign(new Error("password=hunter2 host=db.internal"), { code: "28P01" });
    const { capture } = fakeCapture((inputs) => (inputs.some((i) => i.data.title === "Bad") ? secret : null));
    const publisher = new PostgresIngestionPublisher({ pool: noPool, store: noStore, capture });
    const outcomes = await publisher.publish(
      [
        item(1, { evidenceSha256: null }, { title: "Bad" }),
        item(2),
        item(3, { venueId: null }, { venueId: null }),
        item(4, { observedAt: Date.parse("2100-01-01T00:00:00Z") }),
      ],
      evidence,
    );
    assert.equal(outcomes[0].ok, false);
    assert.equal(outcomes[0].message, "capture_failed: Error code=28P01");
    assert.ok(!JSON.stringify(outcomes).includes("hunter2"));
    assert.equal(outcomes[1].ok, true);
    assert.deepEqual(outcomes[2], { outboxId: 3, ok: true, message: "skipped_no_venue" });
    assert.equal(outcomes[3].ok, false);
    assert.match(outcomes[3].message ?? "", /^invalid_envelope/);
  });

  test("works end to end with the real captureObservations against a fake pool and evidence store", async () => {
    const queries: { sql: string; params: unknown[] }[] = [];
    const pool = {
      query: async (sql: string, params: unknown[]) => {
        queries.push({ sql, params });
        if (sql.includes("register_scrape_object")) return { rows: [{ id: "evidence-1" }] };
        return { rows: [{ observation_id: "o1", event_id: "e1", action: "inserted", issues: [] }] };
      },
    } as unknown as Pool;
    const stored: { raw: Buffer; contentType: string }[] = [];
    const store: EvidenceStore = {
      put: async (raw, options): Promise<EvidenceRef> => {
        stored.push({ raw, contentType: options.contentType });
        return {
          bucket: "tapped-scrape-private-test",
          key: `evidence/aa/${"a".repeat(64)}.gz`,
          sha256: "a".repeat(64),
          bytes: raw.length,
          contentType: options.contentType,
          contentEncoding: "gzip",
        };
      },
    };
    const outcomes = await new PostgresIngestionPublisher({ pool, store }).publish([item(1)], evidence);
    assert.deepEqual(outcomes, [{ outboxId: 1, ok: true, message: "inserted=1" }]);
    assert.equal(stored.length, 1);
    assert.equal(stored[0].contentType, "text/calendar");
    assert.equal(queries.length, 2, "evidence registered, then observations recorded");
    const batch = JSON.parse(String(queries[1].params[0]));
    assert.equal(batch[0].evidenceId, "evidence-1");
    assert.equal(batch[0].source, "event-scraper");
    assert.equal(batch[0].facts.priceUnit, "usd_cent");
    assert.equal(batch[0].venueId, "venue-hifi");
  });
});

describe("NdjsonPublisher", () => {
  test("appends the exact envelopes with evidence metadata, never raw bytes", async () => {
    const dir = mkdtempSync(join(tmpdir(), "event-scraper-ndjson-"));
    try {
      const path = join(dir, "nested", "out.ndjson");
      const publisher = new NdjsonPublisher(path);
      assert.deepEqual(
        (await publisher.publish([item(1)], evidence)).map((o) => o.ok),
        [true],
      );
      await publisher.publish([item(2, { evidenceSha256: null })], evidence);
      const lines = readFileSync(path, "utf8")
        .trim()
        .split("\n")
        .map((line) => JSON.parse(line));
      assert.equal(lines.length, 2);
      assert.equal(lines[0].envelope.deliveryKey, toObservationInput(item(1)).deliveryKey);
      assert.deepEqual(lines[0].evidence, {
        sha256: "page-sha",
        bytes: page.bytes.byteLength,
        contentType: "text/calendar",
      });
      assert.equal(lines[1].evidence, null);
      assert.ok(!readFileSync(path, "utf8").includes("BEGIN:VCALENDAR"));
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe("publishOutbox", () => {
  function seed() {
    const db = openDb(":memory:");
    addSource(
      db,
      {
        id: "src-1",
        venueId: "venue-hifi",
        kind: "ical",
        url: "https://venue.example/cal.ics",
        timezone: "America/Chicago",
      },
      NOW,
    );
    const sha = putRawPage(
      db,
      { url: "https://venue.example/cal.ics", contentType: "text/calendar", bytes: page.bytes },
      NOW,
    );
    const ids: number[] = [];
    for (const [key, title] of [
      ["a", "Nova Quartet"],
      ["b", "Bad"],
    ]) {
      const ev = validated({ identityKey: key, title });
      const stored = upsertEvent(db, ev, { now: NOW });
      ids.push(
        enqueueOutbox(
          db,
          { eventId: stored.id, change: "new", event: ev, observedAt: NOW - 1000, evidenceSha256: sha },
          NOW,
        ) as number,
      );
    }
    return { db, ids };
  }

  test("marks successes published, records failures, alerts, and retries later", async () => {
    const { db, ids } = seed();
    let failing = true;
    const seen: string[] = [];
    const publisher: Publisher = {
      name: "fake",
      publish: async (items, lookup) => {
        for (const i of items)
          seen.push(new TextDecoder().decode(lookup(i.evidenceSha256 as string)?.bytes).slice(0, 15));
        return items.map((i) => ({ outboxId: i.id, ok: !(failing && i.event.title === "Bad"), message: "x" }));
      },
    };
    const first = await publishOutbox(db, publisher, { now: () => NOW });
    assert.deepEqual(
      { considered: first.considered, published: first.published, failed: first.failed },
      { considered: 2, published: 1, failed: 1 },
    );
    assert.equal(seen[0], "BEGIN:VCALENDAR");
    assert.deepEqual(
      pendingOutbox(db).map((row) => [row.id, row.attempts]),
      [[ids[1], 1]],
    );
    const alerts = listAlerts(db, { open: true, kind: "publish_failed" });
    assert.equal(alerts.length, 1);

    failing = false;
    const second = await publishOutbox(db, publisher, { now: () => NOW });
    assert.equal(second.published, 1);
    assert.equal(pendingOutbox(db).length, 0);
    assert.equal(listAlerts(db, { open: true, kind: "publish_failed" }).length, 0, "clean run resolves the alert");
  });

  test("a throwing publisher never throws out of the run and stops retrying at maxAttempts", async () => {
    const { db } = seed();
    const publisher: Publisher = {
      name: "down",
      publish: async () => {
        throw new Error("ECONNREFUSED with secret");
      },
    };
    for (let attempt = 0; attempt < 3; attempt++)
      await publishOutbox(db, publisher, { maxAttempts: 2, now: () => NOW });
    assert.equal(pendingOutbox(db, 100, 2).length, 0);
    assert.equal(pendingOutbox(db, 100, 10).length, 2);
    const alert = listAlerts(db, { open: true, kind: "publish_failed" })[0];
    assert.ok(!JSON.stringify(alert).includes("secret"));
  });
});

describe("venue snapshot", () => {
  test("loads a JSON file, normalizes fields, and drops invalid entries", async () => {
    const venues = await new JsonFileVenueSnapshot(join(fixtures, "venues.json"), clock).listVenues();
    assert.deepEqual(
      venues.map((v) => v.id),
      ["venue-hifi", "venue-annex", "venue-nogeo"],
    );
    assert.equal(venues[0].website, "https://thehifi.example/");
    assert.equal(venues[0].googlePlaceId, "ChIJhifi");
    assert.equal(venues[0].timezone, "America/Indiana/Indianapolis");
    assert.equal(venues[1].name, "HI-FI Annex");
    assert.equal(venues[1].website, "https://thehifi.example/annex", "credentials stripped");
    assert.equal(venues[1].lat, 39.769);
    assert.equal(venues[1].timezone, null, "invalid IANA zone dropped");
    assert.equal(venues[2].name, "nogeo");
    assert.equal(venues[2].lat, null, "0,0 is not a location");
    assert.equal(venues[2].website, null, "non-http website dropped");
    assert.equal(venues[0].syncedAt, NOW);
  });

  test("Postgres source runs exactly the documented read-only query", async () => {
    const seen: string[] = [];
    const snapshot = new PostgresVenueSnapshot(
      {
        query: async (sql) => {
          seen.push(sql);
          return {
            rows: [
              {
                id: "v1",
                username: "hifi",
                name: "",
                website: "thehifi.example",
                lat: 39.7,
                lng: -86.1,
                place_id: "P1",
              },
            ],
          };
        },
      },
      clock,
    );
    const venues = await snapshot.listVenues();
    assert.deepEqual(seen, [VENUE_SNAPSHOT_SQL]);
    assert.match(VENUE_SNAPSHOT_SQL, /FROM ingestion_profiles/);
    assert.doesNotMatch(VENUE_SNAPSHOT_SQL, /\b(INSERT|UPDATE|DELETE)\b/i);
    assert.equal(venues[0].name, "hifi");
    assert.equal(venues[0].googlePlaceId, "P1");
  });

  test("sync upserts venues and records place ids without stealing another venue's alias", async () => {
    const db = openDb(":memory:");
    const result = await syncVenueSnapshot(db, new JsonFileVenueSnapshot(join(fixtures, "venues.json"), clock), NOW);
    assert.equal(result.venues, 3);
    assert.equal(result.placeAliasesAdded, 1);
    assert.deepEqual(result.placeAliasConflicts, [
      { placeId: "ChIJhifi", venueId: "venue-annex", ownerVenueId: "venue-hifi" },
    ]);
    assert.equal(resolvePlaceId(db, "ChIJhifi")?.venueId, "venue-hifi");
    assert.equal(listPlaceAliases(db, { venueId: "venue-hifi" })[0].isCanonical, true);
    assert.equal(getVenue(db, "venue-annex")?.name, "HI-FI Annex");
    // Re-running is idempotent.
    const again = await syncVenueSnapshot(db, new JsonFileVenueSnapshot(join(fixtures, "venues.json"), clock), NOW);
    assert.equal(again.placeAliasesAdded, 0);
  });
});
