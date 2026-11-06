import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, test } from "node:test";
import { main } from "../src/cli.js";
import { ConfigError, loadConfig, parseConfigFile } from "../src/config.js";
import { addSource, countJobs, getSource, listAlerts, listSourceEvents, openDb, upsertVenues } from "../src/db.js";
import { DAY_MS, HOUR_MS, nextDelay, runOnce } from "../src/runner.js";
import type { Clock, LlmClient } from "../src/types.js";
import { openTestDb, testDatabaseEnv } from "./helpers/db.js";
import { fakeFetch, NOW_MS, politeClient } from "./helpers/discovery.js";

const TZ = "America/Chicago";
const llmFixture = (name: string) => readFileSync(new URL(`./fixtures/llm/${name}`, import.meta.url), "utf8");

async function setup() {
  const db = await openTestDb();
  await upsertVenues(db, [
    {
      id: "v1",
      name: "Redline Tavern",
      address: null,
      lat: null,
      lng: null,
      website: "https://venue.example/",
      googlePlaceId: null,
      timezone: TZ,
      syncedAt: NOW_MS,
    },
  ]);
  let nowMs = NOW_MS;
  const clock: Clock = { now: () => new Date(nowMs) };
  return { db, clock, advance: (ms: number) => (nowMs += ms) };
}

describe("config", () => {
  test("defaults: OSM and listings on; Places, LLM, Bandsintown off; NDJSON dry run", () => {
    const config = loadConfig({ EVENT_SCRAPER_DATABASE_URL: "postgres://unused.invalid/x" }, { configFile: null });
    assert.equal(config.dbSchema, "scraper");
    assert.deepEqual(config.features, { llm: false, places: false, osm: true, listings: true, bandsintown: false });
    assert.equal(config.publish.mode, "ndjson");
    assert.equal(config.discovery.minProvenEvents, 3);
    assert.equal(config.scrape.maxIntervalMs, 7 * DAY_MS);
  });

  test("collects every invalid value, and enabling a paid feed requires its key", () => {
    assert.throws(
      () =>
        loadConfig(
          {
            EVENT_SCRAPER_PLACES: "1",
            EVENT_SCRAPER_LLM: "maybe",
            EVENT_SCRAPER_PUBLISH: "s3",
            EVENT_SCRAPER_CONCURRENCY: "0",
          },
          { configFile: null },
        ),
      (error: unknown) => {
        assert.ok(error instanceof ConfigError);
        assert.equal(error.issues.length, 5);
        assert.ok(error.issues.includes("EVENT_SCRAPER_DATABASE_URL is required"));
        assert.ok(error.issues.some((i) => i.includes("GOOGLE_PLACES_API_KEY")));
        return true;
      },
    );
  });

  test("config file: cities validated, ticketing listings refused", () => {
    const parsed = parseConfigFile({
      cities: [{ name: "Chicago", bbox: { south: 41.6, west: -87.9, north: 42.1, east: -87.5 }, timezone: TZ }],
      listings: [{ url: "https://chicagoreader.example/music", city: "Chicago", timezone: TZ }],
      bandsintownArtists: ["  Wilco "],
    });
    assert.equal(parsed.cities[0]?.name, "Chicago");
    assert.deepEqual(parsed.bandsintownArtists, ["Wilco"]);
    assert.throws(
      () =>
        parseConfigFile({
          listings: [{ url: "https://www.eventbrite.com/d/il--chicago/music", city: "Chicago", timezone: TZ }],
        }),
      /ticketing platform/,
    );
    assert.throws(
      () =>
        parseConfigFile({
          cities: [{ name: "X", bbox: { south: 2, west: 0, north: 1, east: 1 }, timezone: "Mars/Base" }],
        }),
      (error: unknown) => error instanceof ConfigError && error.issues.length === 2,
    );
    const dir = mkdtempSync(join(tmpdir(), "event-scraper-config-"));
    const path = join(dir, "config.json");
    writeFileSync(path, "{not json");
    assert.throws(() => loadConfig({}, { configFile: path }), /not valid JSON/);
  });
});

describe("runner scheduling", () => {
  const opts = { productiveIntervalMs: DAY_MS, maxIntervalMs: 7 * DAY_MS };
  test("adaptive delays", () => {
    assert.equal(nextDelay("productive", 0, opts), DAY_MS);
    assert.equal(nextDelay("unchanged", 1, opts), 2 * DAY_MS);
    assert.equal(nextDelay("unchanged", 2, opts), 4 * DAY_MS);
    assert.equal(nextDelay("unchanged", 5, opts), 7 * DAY_MS, "capped at 7 days");
    assert.equal(nextDelay("failure", 1, opts), HOUR_MS);
    assert.equal(nextDelay("failure", 3, opts), 4 * HOUR_MS);
    assert.equal(nextDelay("failure", 30, opts), DAY_MS);
    assert.equal(nextDelay("robots", 0, opts), 7 * DAY_MS);
  });

  test("HTTP failures back off, alert after 3 in a row, and never cancel events", async () => {
    const { db, clock, advance } = await setup();
    const net = fakeFetch({ "https://venue.example/calendar": () => new Response("down", { status: 503 }) });
    const source = await addSource(db, {
      venueId: "v1",
      kind: "html",
      url: "https://venue.example/calendar",
      timezone: TZ,
    });
    const delays: number[] = [];
    for (let i = 0; i < 3; i++) {
      const run = await runOnce({ db, http: politeClient(net.fetchImpl), clock }, { concurrency: 1 });
      assert.equal(run.results[0]?.outcome, "http_error");
      delays.push(run.results[0]?.nextDelayMs ?? 0);
      advance(DAY_MS);
    }
    assert.deepEqual(delays, [HOUR_MS, 2 * HOUR_MS, 4 * HOUR_MS]);
    assert.equal((await listAlerts(db, { open: true, kind: "fetch_failed", sourceId: source.id })).length, 1);
    assert.equal(
      await countJobs(db, { kind: "fetch_source", status: "queued" }),
      1,
      "exactly one pending job per source",
    );
  });

  test("robots.txt disallow is respected; a redirect to a ticketing platform disables the source", async () => {
    const { db, clock } = await setup();
    const net = fakeFetch({
      "https://blocked.example/robots.txt": () => new Response("User-agent: *\nDisallow: /", { status: 200 }),
      "https://venue.example/shows": () =>
        new Response(null, { status: 302, headers: { location: "https://www.ticketmaster.com/venue/123" } }),
    });
    const robots = await addSource(db, {
      venueId: "v1",
      kind: "html",
      url: "https://blocked.example/events",
      timezone: TZ,
    });
    const redirect = await addSource(db, {
      venueId: "v1",
      kind: "html",
      url: "https://venue.example/shows",
      timezone: TZ,
    });
    const run = await runOnce({ db, http: politeClient(net.fetchImpl), clock }, { concurrency: 1 });
    const by = new Map(run.results.map((r) => [r.sourceId, r]));
    assert.equal(by.get(robots.id)?.outcome, "robots_blocked");
    assert.equal(by.get(robots.id)?.nextDelayMs, 7 * DAY_MS);
    assert.equal(by.get(redirect.id)?.outcome, "disabled");
    assert.equal((await getSource(db, redirect.id))?.enabled, false);
    assert.equal((await listAlerts(db, { kind: "ticketing_blocked" })).length, 1);
    assert.ok(!net.calls.some((c) => c.url.includes("ticketmaster")), "the ticketing hop is never requested");
    assert.ok(!net.calls.some((c) => c.url === "https://blocked.example/events"));
  });

  test("LLM fallback runs only when structured extraction found nothing, and evidence is verified", async () => {
    const { db, clock } = await setup();
    const net = fakeFetch({ "https://venue.example/calendar": llmFixture("venue-calendar.html") });
    await addSource(db, { venueId: "v1", kind: "html", url: "https://venue.example/calendar", timezone: TZ });
    let calls = 0;
    const llm: LlmClient = {
      completeJson: async () => {
        calls++;
        return {
          data: JSON.parse(llmFixture("venue-calendar.response.json")),
          model: "fake",
          inputTokens: 1,
          outputTokens: 1,
        };
      },
    };
    const off = await runOnce({ db, http: politeClient(net.fetchImpl), clock }, { concurrency: 1 });
    assert.equal(off.results[0]?.extractor, null, "no LLM client, no fallback");
    assert.equal(calls, 0);

    const { db: db2 } = await setup();
    const source2 = await addSource(db2, {
      venueId: "v1",
      kind: "html",
      url: "https://venue.example/calendar",
      timezone: TZ,
    });
    const on = await runOnce(
      { db: db2, http: politeClient(net.fetchImpl), llm, clock },
      { concurrency: 1, llmMaxPages: 5 },
    );
    assert.equal(on.results[0]?.extractor, "llm");
    assert.ok(calls >= 1);
    assert.equal(on.llmPages, 1);
    const events = await listSourceEvents(db2, source2.id);
    assert.ok(events.length > 0);
    assert.ok(events.every((e) => e.data.evidence.length > 0));
  });
});

describe("cli", () => {
  test("the example deploy config is valid", () => {
    const parsed = parseConfigFile(
      JSON.parse(readFileSync(new URL("../examples/config.example.json", import.meta.url), "utf8")),
    );
    assert.equal(parsed.cities.length, 1);
  });

  test("loop runs a tick, publishes, and stops on abort", async () => {
    const dir = mkdtempSync(join(tmpdir(), "event-scraper-loop-"));
    const controller = new AbortController();
    const net = fakeFetch({ "https://venue.example/calendar": llmFixture("venue-calendar.html") });
    const databaseEnv = await testDatabaseEnv();
    const env = { ...databaseEnv, EVENT_SCRAPER_DATA_DIR: dir, EVENT_SCRAPER_OSM: "0" };
    const services = {
      http: politeClient(net.fetchImpl),
      clock: { now: () => new Date(NOW_MS) },
      sleep: async () => controller.abort(),
      llm: null,
      venueSnapshot: null,
    };
    const quiet = { stdout: () => {}, stderr: () => {} };
    const db = await openDb({ url: env.EVENT_SCRAPER_DATABASE_URL, schema: env.EVENT_SCRAPER_DB_SCHEMA });
    await upsertVenues(db, [
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
    await db.close();
    assert.equal(
      await main(["add-source", "--venue", "v1", "--url", "https://venue.example/calendar"], {
        env,
        services,
        ...quiet,
      }),
      0,
    );
    const code = await main(["loop", "--no-discover"], { env, services, signal: controller.signal, ...quiet });
    assert.equal(code, 0);
    assert.equal(controller.signal.aborted, true);
    assert.ok(net.calls.some((c) => c.url === "https://venue.example/calendar"));
    assert.equal(await main(["bogus"], { env, services, ...quiet }), 2);
  });
});

describe("multi-venue source", () => {
  const card = (title: string, date: string, venue: string) => `
    <div class="rhpSingleEvent">
      <div class="singleEventDate">${date}</div>
      <a id="eventTitle" class="url" href="https://group.example/event/${title.toLowerCase().replace(/ /g, "-")}/${venue}/city/">
        <h2 class="rhp-event__title--list">${title}</h2></a>
      <span class="rhp-event__time-text--list">Door: 7 pm</span>
      <a class="venueLink" href="https://group.example/venue/${venue}/">${venue}</a>
    </div>`;
  const page = (...cards: string[]) => `<html><body>${cards.join("")}</body></html>`;

  async function multiVenue() {
    const context = await setup();
    await upsertVenues(context.db, [
      {
        id: "v2",
        name: "Second Room",
        address: null,
        lat: null,
        lng: null,
        website: null,
        googlePlaceId: null,
        timezone: TZ,
        syncedAt: NOW_MS,
      },
    ]);
    const source = await addSource(context.db, {
      kind: "multi_venue",
      venueId: null,
      venueRoutes: { "room-one": "v1", "room-two": "v2", elsewhere: null },
      url: "https://group.example/events/",
      timezone: TZ,
    });
    return { ...context, source };
  }

  test("each show lands on its own venue; ignored and unknown venues do not, and unknown raises an alert", async () => {
    const { db, clock, source } = await multiVenue();
    const net = fakeFetch({
      "https://group.example/events/": page(
        card("Alpha Band", "Dec 05", "room-one"),
        card("Beta Band", "Dec 06", "room-two"),
        card("Gamma Band", "Dec 07", "elsewhere"),
        card("Delta Band", "Dec 08", "new-room"),
      ),
    });
    const run = await runOnce({ db, http: politeClient(net.fetchImpl), clock }, { concurrency: 1 });
    assert.equal(run.results[0]?.extractor, "rhp");
    assert.deepEqual((await listSourceEvents(db, source.id)).map((event) => [event.title, event.venueId]).sort(), [
      ["Alpha Band", "v1"],
      ["Beta Band", "v2"],
    ]);
    assert.equal(run.results[0]?.rejectedReasons.route_ignored, 1);
    assert.equal(run.results[0]?.rejectedReasons.route_unknown, 1);
    const alerts = await listAlerts(db, { open: true, kind: "unrouted_venue", sourceId: source.id });
    assert.equal(alerts.length, 1);
    assert.match(alerts[0]?.message ?? "", /new-room/);
  });
});
