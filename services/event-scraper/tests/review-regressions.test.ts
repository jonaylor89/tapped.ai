/**
 * Regression tests for the review findings on services/event-scraper (one describe block per finding). All offline:
 * fake fetch / Places / Overpass clients, in-memory or temp-dir SQLite.
 */
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, test } from "node:test";
import { HOUSEKEEPING_KEY, main, runHousekeeping } from "../src/cli.js";
import {
  addSource,
  claimJob,
  countJobs,
  type Db,
  enqueueJob,
  finishJob,
  getKv,
  hostSlotStore,
  insertCandidate,
  listCandidates,
  listSourceEvents,
  one,
  openDb,
  pendingOutbox,
  pruneOutbox,
  run,
  upsertVenues,
} from "../src/db.js";
import { isPrivateAddress, isPrivateHost } from "../src/denylist.js";
import { OverpassHttpClient } from "../src/discovery/osm.js";
import { GooglePlacesClient, PlacesApiError, restrictionRectangle, searchCell } from "../src/discovery/places.js";
import { locationMatch, proveCandidate } from "../src/discovery/prove.js";
import { ingestPlaces } from "../src/discovery/resolve.js";
import { runDiscovery, scheduleDiscovery } from "../src/discovery-runner.js";
import { extractJsonLd } from "../src/extract/jsonld.js";
import { localToInstant } from "../src/extract/time.js";
import { dedupeEvents } from "../src/extract/util.js";
import { FetchBlockedError, PoliteHttpClient } from "../src/fetch.js";
import { hasStarted, reconcileSource } from "../src/reconcile/reconcile.js";
import { createLlmExtractor, dailyLlmBudget, runOnce } from "../src/runner.js";
import type {
  Clock,
  ExtractedEvent,
  OverpassClient,
  PlaceResult,
  PlacesClient,
  Source,
  ValidatedEvent,
} from "../src/types.js";
import { classifyEvent } from "../src/validate/classify.js";
import { parsePriceText } from "../src/validate/price.js";
import { localToUtc } from "../src/validate/time.js";
import { type ValidateContext, validateEvent, validateEvents } from "../src/validate/validate.js";
import { makeCtx, makePage } from "./extract/helpers.js";
import { openTestDb, testDatabaseEnv } from "./helpers/db.js";
import { fakeFetch, fixedClock, NOW_MS, politeClient } from "./helpers/discovery.js";

const DAY = 24 * 60 * 60 * 1000;
const TZ = "America/Chicago";
const NOW = new Date("2026-11-02T15:00:00Z");
const SOURCE = { id: "src-1", venueId: "venue-1", url: "https://example-room.test/shows", timezone: TZ };
const CTX: ValidateContext = {
  source: SOURCE,
  venue: { id: "venue-1", name: "The Example Room" },
  timezone: TZ,
  now: NOW,
};

function ev(overrides: Partial<ExtractedEvent>): ExtractedEvent {
  return {
    title: "The Example Band",
    start: "2026-11-07T20:00",
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
    ...overrides,
  };
}

function valid(e: ExtractedEvent, ctx: ValidateContext = CTX): ValidatedEvent {
  const outcome = validateEvent(e, ctx);
  if (!outcome.ok) assert.fail(`expected valid, got ${outcome.reasons.join(",")}`);
  return outcome.event;
}

function reasons(e: ExtractedEvent, ctx: ValidateContext = CTX): string[] {
  const outcome = validateEvent(e, ctx);
  if (outcome.ok) assert.fail(`expected rejection, got ${JSON.stringify(outcome.event)}`);
  return outcome.reasons;
}

async function venueDb(): Promise<{ db: Db; source: Source }> {
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
      timezone: TZ,
      syncedAt: 0,
    },
  ]);
  const source = await addSource(
    db,
    { id: "src-1", venueId: "venue-1", kind: "html", url: SOURCE.url, timezone: TZ },
    0,
  );
  return { db, source };
}

function place(partial: Partial<PlaceResult> & Pick<PlaceResult, "placeId" | "displayName">): PlaceResult {
  return {
    types: ["establishment"],
    primaryType: null,
    formattedAddress: null,
    lat: null,
    lng: null,
    websiteUri: null,
    businessStatus: "OPERATIONAL",
    ...partial,
  };
}

const INDY = { city: "Indianapolis", timezone: "America/Indiana/Indianapolis", now: NOW_MS };

describe("finding: dedupeEvents collapsed recurring occurrences sharing one @id", () => {
  test("two dated occurrences with the same @id stay two events", () => {
    const url = "https://v.com/events/";
    const html = `<script type="application/ld+json">[
      {"@type":"MusicEvent","@id":"https://v.com/events/open-mic/#event","name":"Open Mic","startDate":"2026-11-05T19:00"},
      {"@type":"MusicEvent","@id":"https://v.com/events/open-mic/#event","name":"Open Mic","startDate":"2026-11-12T19:00"}
    ]</script>`;
    const events = extractJsonLd(makePage(html, url), makeCtx(url));
    assert.deepEqual(
      events.map((e) => e.start),
      ["2026-11-05T19:00", "2026-11-12T19:00"],
    );
    // The bare id still dedupes when there is no date at all.
    const undated = dedupeEvents([ev({ start: null, sourceEventId: "x" }), ev({ start: null, sourceEventId: "x" })]);
    assert.equal(undated.length, 1);
  });
});

describe("finding: id/URL identity keys had no start time", () => {
  test("early and late sets sharing one event URL are both kept", () => {
    const result = validateEvents(
      [
        ev({ title: "Jazz Night", start: "2026-11-07T19:00", eventUrl: "https://example-room.test/e/jazz-night" }),
        ev({ title: "Jazz Night", start: "2026-11-07T21:30", eventUrl: "https://example-room.test/e/jazz-night" }),
      ],
      CTX,
    );
    assert.equal(result.valid.length, 2);
    assert.equal(result.duplicates, 0);
    assert.notEqual(result.valid[0]?.identityKey, result.valid[1]?.identityKey);
  });

  test("a same-day time change of one id event is an update, not new + cancel", async () => {
    const { db, source } = await venueDb();
    const ctx = { ...CTX, source };
    const first = valid(ev({ sourceEventId: "wp-1", start: "2026-11-07T20:00" }), ctx);
    await reconcileSource(db, { source, events: [first], now: NOW });
    const moved = valid(ev({ sourceEventId: "wp-1", start: "2026-11-07T21:00" }), ctx);
    const r = await reconcileSource(db, { source, events: [moved], now: new Date(NOW.getTime() + 3600_000) });
    assert.deepEqual(
      r.changes.map((c) => c.kind),
      ["updated"],
    );
    const stored = await listSourceEvents(db, source.id, ["active"]);
    assert.equal(stored.length, 1);
    assert.equal(stored[0]?.startLocal, "2026-11-07T21:00");
  });
});

describe("finding: LLM evidence did not have to support the extracted date", () => {
  const page = "<p>Band A — Nov 15, 8pm</p><p>Band B — Nov 1, 8pm</p>";
  const ctx: ValidateContext = { ...CTX, pageText: page, pageContentType: "text/html" };
  const llm = (o: Partial<ExtractedEvent>) => ev({ extractor: "llm", title: "Band A", ...o });

  test("a swapped date is rejected even though 'Band A — Nov 1' is a substring of the page", () => {
    // Quotes match on word boundaries: "Nov 1" is not found inside "Nov 15".
    assert.deepEqual(reasons(llm({ start: "--11-01T20:00", evidence: ["Band A — Nov 1"] }), ctx), [
      "evidence_not_found:1",
    ]);
    assert.deepEqual(reasons(llm({ start: "--11-01T20:00", evidence: ["Band A"] }), ctx), [
      "evidence_date_unsupported",
    ]);
  });

  test("a quote tying title and date is accepted; a non-verbatim title is rejected", () => {
    const ok = valid(llm({ start: "--11-15T20:00", evidence: ["Band A — Nov 15, 8pm"] }), ctx);
    assert.equal(ok.startLocal, "2026-11-15T20:00");
    assert.deepEqual(
      reasons(llm({ title: "Band A Live", start: "--11-15T20:00", evidence: ["Band A — Nov 15"] }), ctx),
      ["title_not_verbatim"],
    );
  });

  test("rawDateText not found on the page is ignored for weekday inference", () => {
    const e = valid(llm({ start: "--11-15T20:00", evidence: ["Band A — Nov 15"], rawDateText: "Sat, Nov 14" }), ctx);
    assert.ok(e.warnings.includes("raw_date_text_not_found"));
    assert.ok(!e.warnings.includes("weekday_mismatch"));
  });
});

describe("finding: schema.org offset dates hid a wrong '+00:00' offset", () => {
  test("'+00:00' local times for a New York venue keep the wall clock and are flagged", () => {
    const url = "https://v.com/shows/";
    const tz = "America/New_York";
    const html = `<script type="application/ld+json">[
      {"@type":"MusicEvent","name":"Eight O'Clock Show","startDate":"2026-11-07T20:00:00+00:00"},
      {"@type":"MusicEvent","name":"Late Show","startDate":"2026-11-08T00:30:00+00:00"}
    ]</script>`;
    const extracted = extractJsonLd(makePage(html, url), makeCtx(url, { timezone: tz }));
    const ctx: ValidateContext = { source: { ...SOURCE, url, timezone: tz }, timezone: tz, now: NOW };
    const [eight, late] = extracted.map((e) => valid(e, ctx));
    assert.equal(eight?.startLocal, "2026-11-07T20:00");
    assert.equal(eight?.startUtc, "2026-11-08T01:00:00.000Z");
    assert.ok(eight?.warnings.includes("instant_local_mismatch"));
    assert.equal(late?.startLocal, "2026-11-08T00:30", "the late show stays on its own date");
  });

  test("a correct offset is unchanged", () => {
    const url = "https://v.com/shows/";
    const html = `<script type="application/ld+json">{"@type":"MusicEvent","name":"Show","startDate":"2026-11-07T20:00:00-06:00"}</script>`;
    const [e] = extractJsonLd(makePage(html, url), makeCtx(url, { timezone: TZ })).map((x) => valid(x));
    assert.equal(e?.startLocal, "2026-11-07T20:00");
    assert.equal(e?.startUtc, "2026-11-08T02:00:00.000Z");
    assert.ok(!e?.warnings.includes("instant_local_mismatch"));
  });
});

describe("finding: keyword rules overrode structured hints and dropped concerts", () => {
  test("music hints and clear music words win over venue names and soft non-event words", () => {
    const cases: Array<[string, string | null]> = [
      ["Jason Isbell at the Ryman Theater", null],
      ["Fair Play", null],
      ["Comic Book Heroes", null],
      ["Blue Oyster Cult", null],
      ["Poker Face: Lady Gaga Tribute", null],
      ["Happy Hour Jazz Trio", null],
      ["The Band @ The Vogue Theatre", "The Vogue Theatre"],
    ];
    for (const [title, venueName] of cases) {
      const c = classifyEvent({ title, hint: "music", venueName });
      assert.equal(c.category, "music", `${title}: ${c.reason}`);
      assert.equal(c.isMusic, true, title);
    }
    assert.equal(classifyEvent({ title: "Hamlet: A Play in Five Acts", hint: "music" }).category, "theater");
    assert.equal(classifyEvent({ title: "Stand-Up Saturday" }).category, "comedy");
    assert.equal(classifyEvent({ title: "Trivia Night", hint: "music" }).category, "other");
  });
});

describe("finding: price parsing", () => {
  test("thousands separators are not decimal marks", () => {
    assert.equal(parsePriceText("$1,500 VIP table").prices[0]?.minCents, 150_000);
    assert.equal(parsePriceText("VIP table $1,000").prices[0]?.minCents, 100_000);
  });

  test("each amount is labeled by its own words", () => {
    assert.deepEqual(
      parsePriceText("$15 adv $20 dos").prices.map((p) => [p.kind, p.minCents]),
      [
        ["advance", 1500],
        ["door", 2000],
      ],
    );
    assert.deepEqual(
      parsePriceText("adv $15 dos $20").prices.map((p) => [p.kind, p.minCents]),
      [
        ["advance", 1500],
        ["door", 2000],
      ],
    );
  });
});

describe("finding: date-only events were 'missing' on their own day", () => {
  test("hasStarted is true all day for date-only events", () => {
    assert.equal(hasStarted({ startUtc: null, startLocal: "2026-11-07" }, NOW, "2026-11-07"), true);
    assert.equal(hasStarted({ startUtc: null, startLocal: "2026-11-08" }, NOW, "2026-11-07"), false);
  });

  test("two same-day fetches without a date-only event do not cancel it", async () => {
    const { db, source } = await venueDb();
    const ctx = { ...CTX, source };
    const allDay = valid(ev({ title: "All Day Fest", start: "2026-11-07" }), ctx);
    const other = valid(ev({ title: "Other Show", start: "2026-11-09T20:00" }), ctx);
    await reconcileSource(db, { source, events: [allDay, other], now: NOW });
    const onTheDay = [new Date("2026-11-07T18:00:00Z"), new Date("2026-11-07T21:00:00Z")];
    for (const now of onTheDay) {
      const r = await reconcileSource(db, { source, events: [{ ...other }], now });
      assert.equal(r.counts.canceled, 0);
    }
    assert.ok((await listSourceEvents(db, source.id, ["active"])).some((e) => e.title === "All Day Fest"));
  });
});

describe("finding: extract/time.ts and validate/time.ts disagreed on ambiguous times", () => {
  test("the first occurrence wins in zones east and west of UTC", () => {
    for (const [local, zone, expected] of [
      ["2026-10-25T02:30", "Europe/Berlin", "2026-10-25T00:30:00.000Z"],
      ["2026-11-01T01:30", "America/New_York", "2026-11-01T05:30:00.000Z"],
    ] as const) {
      assert.equal(localToInstant(local, zone)?.toISOString(), expected, zone);
      assert.equal(localToUtc(local, zone), expected, zone);
    }
  });
});

describe("finding: the Places budget ignored requests made by failed cells", () => {
  const city = {
    name: "Gridville",
    timezone: TZ,
    bbox: { south: 39.6, west: -86.3, north: 39.9, east: -86.0 },
  };

  test("every request counts, including ones in cells that fail; the cap holds", async () => {
    const db = await openTestDb();
    let calls = 0;
    const places: PlacesClient = {
      textSearch: async (request) => {
        calls++;
        if (calls % 3 === 0) throw new PlacesApiError(500, "boom");
        return {
          places: [
            place({
              placeId: `p${calls}`,
              displayName: `Venue ${calls}`,
              types: ["night_club", "establishment"],
              lat: request.center.lat,
              lng: request.center.lng,
            }),
          ],
          nextPageToken: null,
        };
      },
    };
    const summary = await runDiscovery(
      { db, http: politeClient(fakeFetch({}).fetchImpl), places, clock: fixedClock, sleep: async () => {} },
      { cities: [city], listings: [], placesBudget: 42, placesMaxPages: 1, skipProve: true },
    );
    assert.equal(summary.placesRequests, calls);
    assert.ok(calls <= 42, `made ${calls} requests`);
    assert.equal(summary.placesBudgetExhausted, true);
    // Places returned before a failure in the same cell are kept.
    assert.ok((await listCandidates(db)).length >= Math.floor((calls * 2) / 3) - 1);
  });

  test("a 403/429 stops the rest of the Places work for the run", async () => {
    const db = await openTestDb();
    let calls = 0;
    const places: PlacesClient = {
      textSearch: async () => {
        calls++;
        throw new PlacesApiError(429, "quota");
      },
    };
    const summary = await runDiscovery(
      { db, http: politeClient(fakeFetch({}).fetchImpl), places, clock: fixedClock, sleep: async () => {} },
      { cities: [city], listings: [], placesBudget: 200, skipProve: true },
    );
    assert.equal(calls, 1);
    assert.equal(summary.placesRequests, 1);
    assert.equal(summary.placesHalted, "http_429");
  });
});

describe("finding: premise ids attached to the first venue blocked later businesses", () => {
  test("a second business in the same building is not parked in review", async () => {
    const db = await openTestDb();
    const premise = place({
      placeId: "PREMISE",
      displayName: "1043 Virginia Ave",
      types: ["premise"],
      lat: 39.75709,
      lng: -86.14,
    });
    await ingestPlaces(
      db,
      [
        place({ placeId: "HIFI", displayName: "The Hi-Fi", types: ["live_music_venue"], lat: 39.757, lng: -86.14 }),
        premise,
      ],
      INDY,
    );
    await ingestPlaces(
      db,
      [
        place({
          placeId: "BREWERY",
          displayName: "Fountain Square Brewery",
          types: ["bar", "establishment"],
          lat: 39.75713,
          lng: -86.14,
        }),
        premise,
      ],
      INDY,
    );
    const brewery = (await listCandidates(db)).find((c) => c.name === "Fountain Square Brewery");
    assert.ok(brewery);
    assert.notEqual(brewery.status, "needs_review", brewery.statusReason ?? "");
    assert.notEqual((await listCandidates(db)).find((c) => c.name === "The Hi-Fi")?.status, "needs_review");
  });
});

describe("finding: social / link-in-bio websites counted as identities", () => {
  test("a Places listing whose website is the venue's Facebook page still matches the venue", async () => {
    const db = await openTestDb();
    await upsertVenues(db, [
      {
        id: "v-hifi",
        name: "The Hi-Fi",
        address: null,
        lat: 39.757,
        lng: -86.14,
        website: "https://hifiindy.com",
        googlePlaceId: null,
        timezone: INDY.timezone,
        syncedAt: NOW_MS,
      },
    ]);
    await ingestPlaces(
      db,
      [
        place({
          placeId: "HIFI_FB",
          displayName: "HI-FI",
          types: ["live_music_venue"],
          lat: 39.757,
          lng: -86.14,
          websiteUri: "https://www.facebook.com/hifiindy",
        }),
      ],
      INDY,
    );
    const [candidate] = await listCandidates(db);
    assert.equal(candidate?.matchedVenueId, "v-hifi");
    assert.equal(candidate?.statusReason, "matched_venue:geo_name");
  });
});

describe("finding: same-domain merging depended on batch order", () => {
  const a = place({
    placeId: "MURAT_A",
    displayName: "Murat Theatre",
    types: ["performing_arts_theater"],
    lat: 39.775,
    lng: -86.1515,
    websiteUri: "https://www.oldnationalcentre.com/",
  });
  const b = place({
    placeId: "MURAT_B",
    displayName: "Murat Theatre",
    types: ["performing_arts_theater"],
    lat: 39.7761,
    lng: -86.1515,
    websiteUri: "https://www.oldnationalcentre.com/murat",
  });
  const live = async (db: Db) => (await listCandidates(db)).filter((c) => c.status !== "rejected");

  test("one batch and two batches give the same single candidate", async () => {
    const together = await openTestDb();
    await ingestPlaces(together, [a, b], INDY);
    const apart = await openTestDb();
    await ingestPlaces(apart, [a], INDY);
    await ingestPlaces(apart, [b], INDY);
    assert.equal((await live(together)).length, 1);
    assert.equal((await live(apart)).length, 1);
  });
});

describe("finding: prove counted other venues' events", () => {
  test("locationMatch", () => {
    const candidate = { name: "Lobby Bar", address: "10 Main St, Indianapolis", lat: 39.77, lng: -86.15 };
    assert.equal(locationMatch(null, candidate), "unknown");
    assert.equal(
      locationMatch({ name: "Lobby Bar", address: null, lat: null, lng: null, url: null }, candidate),
      "match",
    );
    assert.equal(
      locationMatch({ name: null, address: "10 Main St", lat: null, lng: null, url: null }, candidate),
      "match",
    );
    assert.equal(
      locationMatch({ name: "Grand Ballroom", address: null, lat: null, lng: null, url: null }, candidate),
      "elsewhere",
    );
    assert.equal(
      locationMatch({ name: "Somewhere", address: null, lat: 39.7701, lng: -86.15, url: null }, candidate),
      "match",
    );
  });

  test("a parent site's events at another room do not promote the candidate", async () => {
    const run = async (location: ExtractedEvent["location"]) => {
      const db = await openTestDb();
      const candidate = await insertCandidate(
        db,
        {
          name: "Lobby Bar",
          address: "10 Main St, Indianapolis",
          lat: 39.77,
          lng: -86.15,
          website: "https://grandhotel.example/",
          timezone: TZ,
          discoveredFrom: "osm",
          status: "resolved",
        },
        NOW_MS,
      );
      const net = fakeFetch({ "https://grandhotel.example/events/": "<html><body>events</body></html>" });
      return proveCandidate(db, candidate.id, {
        http: politeClient(net.fetchImpl),
        clock: fixedClock,
        findSources: async () => ({
          ok: true,
          reason: null,
          homepage: "https://grandhotel.example/",
          homepageStatus: 200,
          proposals: [{ kind: "html", url: "https://grandhotel.example/events/", score: 1, via: "link", reason: "x" }],
          links: [],
          endpoints: [],
          llmUsed: false,
        }),
        extract: async (page) => ({
          page,
          extractor: "jsonld",
          events: [10, 11, 12, 13, 14].map((d) =>
            ev({
              title: `Show ${d}`,
              performers: [`Band ${d}`],
              start: `2026-11-${d}T20:00`,
              location,
              sourceEventId: `e${d}`,
            }),
          ),
        }),
      });
    };
    const elsewhere = await run({ name: "Grand Ballroom", address: "500 Other St", lat: null, lng: null, url: null });
    assert.equal(elsewhere.status, "no_source");
    assert.equal(elsewhere.reason, "insufficient_events:0/3");
    assert.equal(elsewhere.attempts[0]?.elsewhere, 5);
    const here = await run(null);
    assert.equal(here.status, "promoted");
  });
});

describe("finding: Overpass runtime errors with HTTP 200 counted as success", () => {
  test("a 'runtime error' remark fails the query", async () => {
    const client = new OverpassHttpClient({
      fetchImpl: async () =>
        new Response(
          JSON.stringify({
            elements: [],
            remark: 'runtime error: Query timed out in "query" at line 3 after 91 seconds.',
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      clock: fixedClock,
      sleep: async () => {},
      minIntervalMs: 0,
    });
    await assert.rejects(client.query("[out:json];node(1);out;"), /runtime error/);
  });

  test("a failed OSM unit is retried after feedRetryMs, not the refresh interval", async () => {
    const db = await openTestDb();
    const overpass: OverpassClient = {
      query: async () => {
        throw new Error("Overpass runtime error: Query timed out");
      },
    };
    const city = { name: "Indy", timezone: TZ, bbox: { south: 39.7, west: -86.2, north: 39.8, east: -86.1 } };
    const summary = await runDiscovery(
      { db, http: politeClient(fakeFetch({}).fetchImpl), overpass, clock: fixedClock },
      { cities: [city], listings: [], skipProve: true, feedRetryMs: DAY, osmRefreshMs: 30 * DAY },
    );
    assert.equal(summary.units[0]?.ok, false);
    const job = await one(db, "SELECT run_after FROM jobs WHERE kind='discover_osm' AND status='queued'");
    assert.equal(Number(job?.run_after), NOW_MS + DAY);
  });
});

describe("finding: Places locationRestriction was ~2x the cell", () => {
  test("the cell's own bbox is sent as the rectangle", async () => {
    const box = { south: 39.7, west: -86.2, north: 39.72, east: -86.17 };
    assert.deepEqual(restrictionRectangle({ lat: 39.71, lng: -86.185 }, 2000, box).rectangle, {
      low: { latitude: 39.7, longitude: -86.2 },
      high: { latitude: 39.72, longitude: -86.17 },
    });
    let body: { locationRestriction?: unknown } = {};
    const client = new GooglePlacesClient({
      apiKey: "test-key-not-real",
      fetchImpl: async (_url, init) => {
        body = JSON.parse(String(init?.body));
        return new Response(JSON.stringify({ places: [] }), { status: 200 });
      },
    });
    await searchCell(
      client,
      { center: { lat: 39.71, lng: -86.185 }, radiusMeters: 2000, bbox: box },
      {
        queries: ["jazz club"],
        maxPages: 1,
      },
    );
    assert.deepEqual(body.locationRestriction, {
      rectangle: { low: { latitude: 39.7, longitude: -86.2 }, high: { latitude: 39.72, longitude: -86.17 } },
    });
  });
});

describe("finding: fetch jobs could lose their lease during long politeness waits", () => {
  const page = readFileSync(new URL("./fixtures/extract/jsonld-graph-yoast.html", import.meta.url), "utf8");

  async function setup() {
    const { db, source } = await venueDb();
    await run(db, "UPDATE sources SET enabled=FALSE WHERE id=?", source.id);
    let nowMs = NOW_MS;
    const clock: Clock = { now: () => new Date(nowMs) };
    return { db, clock, advance: (ms: number) => (nowMs += ms) };
  }

  test("a long wait renews the lease and the job finishes normally", async () => {
    const { db, clock, advance } = await setup();
    const source = await addSource(db, {
      venueId: "venue-1",
      kind: "html",
      url: "https://venue.example/shows/",
      timezone: TZ,
    });
    const net = fakeFetch({
      "https://venue.example/shows/": () => {
        advance(20 * 60 * 1000); // a 20-minute politeness wait, longer than the 15-minute lease
        return new Response(page, { status: 200, headers: { "content-type": "text/html" } });
      },
    });
    const run = await runOnce({ db, http: politeClient(net.fetchImpl), clock }, { concurrency: 1 });
    assert.equal(run.results[0]?.outcome !== "lease_lost", true);
    assert.ok((await listSourceEvents(db, source.id)).length > 0);
    assert.equal(await countJobs(db, { kind: "fetch_source", status: "queued" }), 1);
  });

  test("when another worker took the job, this one skips reconcile and does not enqueue a second job", async () => {
    const { db, clock, advance } = await setup();
    const source = await addSource(db, {
      venueId: "venue-1",
      kind: "html",
      url: "https://venue.example/shows/",
      timezone: TZ,
    });
    const net = fakeFetch({
      "https://venue.example/shows/": async () => {
        advance(20 * 60 * 1000);
        // Another worker reclaims the expired lease and finishes the job with its own schedule.
        const stolen = await claimJob(db, { kinds: ["fetch_source"], now: clock.now().getTime(), leaseMs: 60_000 });
        assert.ok(stolen);
        await finishJob(db, stolen.id, stolen.leaseToken as string, clock.now().getTime());
        await enqueueJob(db, "fetch_source", stolen.payload, {
          dedupeKey: stolen.dedupeKey ?? undefined,
          runAfter: clock.now().getTime() + DAY,
          now: clock.now().getTime(),
        });
        return new Response(page, { status: 200, headers: { "content-type": "text/html" } });
      },
    });
    const run = await runOnce({ db, http: politeClient(net.fetchImpl), clock }, { concurrency: 1, maxJobs: 1 });
    assert.equal(run.results[0]?.outcome, "lease_lost");
    assert.equal((await listSourceEvents(db, source.id)).length, 0, "no reconcile without the lease");
    assert.equal(await countJobs(db, { kind: "fetch_source", status: "queued" }), 1);
  });
});

describe("finding: discovery drained queued units the configuration no longer wants", () => {
  const indy = { name: "Indy", timezone: TZ, bbox: { south: 39.7, west: -86.2, north: 39.8, east: -86.1 } };
  const chi = { name: "Chicago", timezone: TZ, bbox: { south: 41.8, west: -87.7, north: 41.9, east: -87.6 } };

  test("a removed listing URL is retired and never fetched", async () => {
    const db = await openTestDb();
    const net = fakeFetch({});
    const http = politeClient(net.fetchImpl);
    const listing = { url: "https://weekly.example/music", city: "Indy", timezone: TZ };
    await scheduleDiscovery(db, {}, { cities: [], listings: [listing] }, NOW_MS);
    assert.equal(await countJobs(db, { kind: "discover_listing", status: "queued" }), 1);
    const summary = await runDiscovery({ db, http, clock: fixedClock }, { cities: [], listings: [], skipProve: true });
    assert.equal(summary.retired, 1);
    assert.equal(await countJobs(db, { kind: "discover_listing", status: "queued" }), 0);
    assert.ok(!net.calls.some((c) => c.url.includes("weekly.example")));
  });

  test("listings disabled: queued listing units never run", async () => {
    const db = await openTestDb();
    const net = fakeFetch({});
    const listing = { url: "https://weekly.example/music", city: "Indy", timezone: TZ };
    await scheduleDiscovery(db, {}, { cities: [], listings: [listing] }, NOW_MS);
    await runDiscovery(
      { db, http: politeClient(net.fetchImpl), clock: fixedClock },
      { cities: [], listings: [listing], listingsEnabled: false, skipProve: true },
    );
    assert.ok(!net.calls.some((c) => c.url.includes("weekly.example")));
  });

  test("--city only drains that city's units", async () => {
    const db = await openTestDb();
    const queried: string[] = [];
    const overpass: OverpassClient = {
      query: async (ql) => {
        queried.push(ql);
        return [];
      },
    };
    const http = politeClient(fakeFetch({}).fetchImpl);
    await scheduleDiscovery(db, { overpass }, { cities: [indy, chi] }, NOW_MS);
    const summary = await runDiscovery(
      { db, http, overpass, clock: fixedClock },
      { cities: [indy, chi], city: "indy", skipProve: true },
    );
    assert.equal(queried.length, 1);
    assert.deepEqual(
      summary.units.map((u) => u.key),
      ["discover_osm:indy"],
    );
    assert.equal(await countJobs(db, { kind: "discover_osm", status: "queued" }), 2, "Chicago stays queued");
  });
});

describe("finding: private-host check missed IPv6 forms and DNS answers", () => {
  test("IPv4-mapped, compatible, NAT64 and unspecified IPv6 literals are private", () => {
    for (const url of [
      "http://[::ffff:169.254.169.254]/latest/meta-data/",
      "http://[::ffff:127.0.0.1]:8080/",
      "http://[::]/",
      "http://[::1]/",
      "http://[64:ff9b::a9fe:a9fe]/",
      "http://[fd00::1]/",
      "http://[fe80::1]/",
      "http://2130706433/",
      "http://0.0.0.0/",
    ]) {
      assert.equal(isPrivateHost(url), true, url);
    }
    assert.equal(isPrivateHost("http://[2606:4700::1111]/"), false);
    assert.equal(isPrivateHost("http://[::ffff:8.8.8.8]/"), false);
    assert.equal(isPrivateAddress("10.1.2.3"), true);
    assert.equal(isPrivateAddress("93.184.216.34"), false);
  });

  test("a hostname resolving to a private address is blocked before connecting, on every hop", async () => {
    const answers: Record<string, string[]> = {
      "127.0.0.1.nip.io": ["127.0.0.1"],
      "venue.example": ["93.184.216.34"],
      "rebind.example": ["::ffff:a9fe:a9fe"],
    };
    const net = fakeFetch({
      "https://venue.example/shows": () =>
        new Response(null, { status: 302, headers: { location: "https://rebind.example/latest/meta-data/" } }),
    });
    const client = new PoliteHttpClient({
      fetchImpl: net.fetchImpl,
      clock: fixedClock,
      sleep: async () => {},
      minHostIntervalMs: 0,
      respectRobots: false,
      resolveHost: async (host) => answers[host] ?? [],
    });
    await assert.rejects(
      client.get({ url: "http://127.0.0.1.nip.io/" }),
      (error: unknown) => error instanceof FetchBlockedError && error.reason === "private_host",
    );
    await assert.rejects(
      client.get({ url: "https://venue.example/shows" }),
      (error: unknown) => error instanceof FetchBlockedError && error.reason === "private_host",
    );
    assert.deepEqual(
      net.calls.map((c) => c.url),
      ["https://venue.example/shows"],
      "neither private target is ever requested",
    );
  });
});

describe("finding: housekeeping only ran in loop mode; standalone mode filled the outbox", () => {
  test("runHousekeeping prunes old rows, rate-limits itself, and expires unpublished rows only when publishing is off", async () => {
    const { db, source } = await venueDb();
    const old = NOW_MS - 40 * DAY;
    const e = valid(ev({ start: "2026-11-07T20:00" }), { ...CTX, source, now: new Date(old) });
    await reconcileSource(db, { source, events: [e], now: new Date(old) });
    assert.equal((await pendingOutbox(db)).length, 1);
    const job = await enqueueJob(db, "fetch_source", { sourceId: source.id }, { now: old, runAfter: old });
    const claimed = await claimJob(db, { now: old });
    await finishJob(db, claimed?.id ?? job.id, claimed?.leaseToken as string, old);

    const on = await runHousekeeping(db, { now: NOW_MS, publishOff: false });
    assert.equal(on?.jobs, 1);
    assert.equal(on?.outbox, 0, "pending rows are kept while a publisher can still drain them");
    assert.equal(await runHousekeeping(db, { now: NOW_MS + 60_000, publishOff: true }), null, "rate-limited");
    const off = await runHousekeeping(db, { now: NOW_MS + 7 * 60 * 60 * 1000, publishOff: true });
    assert.equal(off?.outbox, 1);
    assert.equal((await pendingOutbox(db)).length, 0);
    assert.equal(await pruneOutbox(db, { publishedBefore: NOW_MS }), 0);
  });

  test("run-once housekeeps, and with EVENT_SCRAPER_PUBLISH=off nothing is queued for publishing", async () => {
    const dir = mkdtempSync(join(tmpdir(), "event-scraper-standalone-"));
    const databaseEnv = await testDatabaseEnv();
    const open = async () =>
      openDb({ url: databaseEnv.EVENT_SCRAPER_DATABASE_URL, schema: databaseEnv.EVENT_SCRAPER_DB_SCHEMA });
    const env = {
      ...databaseEnv,
      EVENT_SCRAPER_DATA_DIR: dir,
      EVENT_SCRAPER_OSM: "0",
      EVENT_SCRAPER_PUBLISH: "off",
    };
    const page = readFileSync(new URL("./fixtures/extract/jsonld-graph-yoast.html", import.meta.url), "utf8");
    const net = fakeFetch({ "https://venue.example/shows/": page });
    const services = {
      http: politeClient(net.fetchImpl),
      clock: fixedClock,
      sleep: async () => {},
      llm: null,
      venueSnapshot: null,
    };
    const quiet = { stdout: () => {}, stderr: () => {} };
    const setupDb = await open();
    await upsertVenues(setupDb, [
      {
        id: "v1",
        name: "Redline Tavern",
        address: null,
        lat: null,
        lng: null,
        website: null,
        googlePlaceId: null,
        timezone: TZ,
        syncedAt: NOW_MS,
      },
    ]);
    await addSource(setupDb, { venueId: "v1", kind: "html", url: "https://venue.example/shows/", timezone: TZ });
    await setupDb.close();
    assert.equal(await main(["run-once"], { env, services, ...quiet }), 0);
    const db = await open();
    try {
      const sourceEvents = await one(db, "SELECT COUNT(*) AS n FROM events");
      assert.ok(Number(sourceEvents?.n) > 0, "events were scraped");
      assert.equal((await pendingOutbox(db)).length, 0);
      assert.equal(await getKv(db, HOUSEKEEPING_KEY), String(NOW_MS));
    } finally {
      await db.close();
    }
  });
});

describe("finding: the LLM page cap reset on every runOnce", () => {
  test("the daily budget is shared by every extractor on one database and resets the next UTC day", async () => {
    const db = await openTestDb();
    let nowMs = NOW_MS;
    const clock: Clock = { now: () => new Date(nowMs) };
    const a = dailyLlmBudget(db, 3, clock);
    const b = dailyLlmBudget(db, 3, clock);
    assert.deepEqual(
      [await a.tryConsume(), await b.tryConsume(), await a.tryConsume(), await b.tryConsume()],
      [true, true, true, false],
    );
    nowMs += DAY;
    assert.equal(await a.tryConsume(), true);
  });

  test("a fresh extractor per run cannot exceed the shared cap", async () => {
    const db = await openTestDb();
    const llmCalls: number[] = [];
    const ctx = {
      ...makeCtx("https://venue.example/calendar"),
      llm: {
        completeJson: async () => {
          llmCalls.push(1);
          return { data: { events: [] }, model: "fake", inputTokens: 1, outputTokens: 1 };
        },
      },
    };
    const page = makePage("<p>Some calendar text</p>", "https://venue.example/calendar");
    for (let run = 0; run < 3; run++) {
      const extractor = createLlmExtractor({ budget: dailyLlmBudget(db, 2, fixedClock) });
      await extractor.extract(page, ctx);
    }
    assert.equal(llmCalls.length, 2);
  });
});

describe("finding: per-host politeness was per process", () => {
  test("two clients on one SQLite file share host slots and Retry-After", async () => {
    const db = await openTestDb();
    const slept: number[] = [];
    let first = true;
    const net = fakeFetch({
      "https://venue.example/a": () => {
        if (!first) return new Response("ok", { status: 200 });
        first = false;
        return new Response("busy", { status: 503, headers: { "retry-after": "60" } });
      },
    });
    const make = () =>
      new PoliteHttpClient({
        fetchImpl: net.fetchImpl,
        clock: fixedClock,
        sleep: async (ms) => {
          slept.push(ms);
        },
        minHostIntervalMs: 5_000,
        respectRobots: false,
        slotStore: hostSlotStore(db),
      });
    const runOnceProcess = make();
    const discoverProcess = make();
    await runOnceProcess.get({ url: "https://venue.example/a" });
    await discoverProcess.get({ url: "https://venue.example/a" });
    assert.deepEqual(slept, [60_000], "the second process waits for the first one's Retry-After");
    await discoverProcess.get({ url: "https://venue.example/a" });
    assert.equal(slept[1], 65_000, "and queues behind its own slot after that");
  });
});
