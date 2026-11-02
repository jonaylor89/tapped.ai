/**
 * End-to-end, fully offline: two venues served from fixtures through the real PoliteHttpClient over a fake network,
 * plus a Places + Overpass fixture city. Drives the real CLI (`main`) for import-venues, add-source, run-once,
 * discover and export-candidates, then inspects the SQLite file and the NDJSON dry-run output.
 */
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, test } from "node:test";
import { main, type Services } from "../src/cli.js";
import {
  getCandidate,
  listCandidates,
  listPlaceAliases,
  listSourceEvents,
  listSources,
  openDb,
  resolvePlaceId,
} from "../src/db.js";
import { isTicketingUrl } from "../src/denylist.js";
import { parseOverpassResponse } from "../src/discovery/osm.js";
import { parsePlace } from "../src/discovery/places.js";
import type { Clock, OverpassClient, PlaceResult, PlacesClient, PlacesTextSearchRequest } from "../src/types.js";
import { fakeFetch, fixtureJson, NOW_MS, politeClient } from "./helpers/discovery.js";

const e2e = (name: string) => new URL(`./fixtures/e2e/${name}`, import.meta.url);
const text = (name: string) => readFileSync(e2e(name), "utf8");

function network() {
  const html = (body: string) => () =>
    new Response(body, { status: 200, headers: { "content-type": "text/html; charset=utf-8", etag: '"v1"' } });
  return fakeFetch({
    "https://thevogue.example/calendar/": html(text("vogue-calendar.html")),
    "https://hifiroom.example/calendar/": html(text("hifi-room-calendar.html")),
    "https://hifiroom.example/calendar.ics": () =>
      new Response(text("hifi-room.ics"), { status: 200, headers: { "content-type": "text/calendar; charset=utf-8" } }),
    // OSM is searched first, so the candidate keeps OSM's website (bare domain); Places adds its aliases.
    "https://mercuryroomindy.com/": html(text("mercury-home.html")),
    "https://mercuryroomindy.com/shows/": html(text("mercury-shows.html")),
  });
}

function fakePlaces() {
  const raw = [
    fixtureJson<{ places: unknown[] }>("places-indy-page1.json"),
    fixtureJson<{ places: unknown[] }>("places-indy-page2.json"),
  ];
  const pages = raw.map((page) => page.places.map((p) => parsePlace(p as never)).filter((p): p is PlaceResult => !!p));
  const requests: PlacesTextSearchRequest[] = [];
  const client: PlacesClient = {
    textSearch: async (request) => {
      requests.push(request);
      if (request.textQuery !== "live music venue") return { places: [], nextPageToken: null };
      if (request.pageToken === "PAGE_TWO_TOKEN") return { places: pages[1]!, nextPageToken: null };
      return { places: pages[0]!, nextPageToken: "PAGE_TWO_TOKEN" };
    },
  };
  return { client, requests };
}

describe("end to end (offline)", () => {
  test("run-once scrapes two venues, publishes NDJSON; discover clusters places and promotes one venue", async () => {
    const dir = mkdtempSync(join(tmpdir(), "event-scraper-e2e-"));
    const dbPath = join(dir, "scraper.sqlite");
    const ndjson = join(dir, "publish", "observations.ndjson");
    const net = network();
    const places = fakePlaces();
    const overpassQueries: string[] = [];
    const overpass: OverpassClient = {
      query: async (ql) => {
        overpassQueries.push(ql);
        return parseOverpassResponse(fixtureJson("overpass-indy.json"));
      },
    };
    let nowMs = NOW_MS;
    const clock: Clock = { now: () => new Date(nowMs) };
    const services: Partial<Services> = {
      http: politeClient(net.fetchImpl),
      places: places.client,
      overpass,
      bandsintown: null,
      llm: null,
      venueSnapshot: null,
      clock,
      sleep: async () => {},
    };
    const env = {
      EVENT_SCRAPER_DB: dbPath,
      EVENT_SCRAPER_DATA_DIR: dir,
      EVENT_SCRAPER_CONFIG: e2e("config.json").pathname,
      EVENT_SCRAPER_DRY_RUN_PATH: ndjson,
      EVENT_SCRAPER_PLACES: "1",
      GOOGLE_PLACES_API_KEY: "test-key-not-real",
    };
    const run = async (...argv: string[]) => {
      let stdout = "";
      let stderr = "";
      const code = await main(argv, {
        env,
        services,
        stdout: (t) => {
          stdout += t;
        },
        stderr: (t) => {
          stderr += t;
        },
      });
      return { code, stdout, stderr, json: () => JSON.parse(stdout) };
    };

    // --- venues + sources ---------------------------------------------------------------------------------------
    const imported = await run("import-venues", "--file", e2e("venues.json").pathname);
    assert.equal(imported.code, 0, imported.stderr);
    assert.equal(imported.json().venues, 2);

    assert.equal(
      (await run("add-source", "--venue", "venue-vogue", "--url", "https://thevogue.example/calendar/")).code,
      0,
    );
    assert.equal(
      (await run("add-source", "--venue", "venue-hifi-room", "--url", "hifiroom.example/calendar/")).code,
      0,
    );
    const ticketing = await run(
      "add-source",
      "--venue",
      "venue-vogue",
      "--url",
      "https://www.eventbrite.com/o/vogue-1",
    );
    assert.equal(ticketing.code, 2);
    assert.match(ticketing.stderr, /Ticketing platforms are never used/);
    const noTz = await run("add-source", "--listing", "--url", "https://indyweekly.example/music");
    assert.equal(noTz.code, 2, "listing sources need an explicit timezone");

    // --- run-once -----------------------------------------------------------------------------------------------
    const first = await run("run-once");
    assert.equal(first.code, 0, first.stderr);
    const summary = first.json();
    assert.equal(summary.run.processed, 2);
    const db = openDb(dbPath);
    const [vogue, hifi] = ["venue-vogue", "venue-hifi-room"].map((v) => listSources(db, { venueId: v })[0]!);
    const bySource = new Map(summary.run.sources.map((s: { sourceId: string }) => [s.sourceId, s]));
    const vogueRun = bySource.get(vogue!.id) as Record<string, unknown>;
    const hifiRun = bySource.get(hifi!.id) as Record<string, unknown>;
    assert.equal(vogueRun.extractor, "jsonld");
    assert.equal(vogueRun.extracted, 5);
    assert.equal(vogueRun.valid, 3, "trivia (other) and last month's show are rejected");
    assert.ok((vogueRun.rejected as Record<string, number>).category_other);
    assert.equal(hifiRun.extractor, "ical", "followed the calendar's advertised .ics feed");
    assert.equal(hifiRun.valid, 5, "2 shows + 3 weekly open mics");
    assert.equal(summary.run.totals.new, 8);
    assert.equal(summary.publish.publisher, "ndjson");
    assert.equal(summary.publish.published, 8);

    const vogueEvents = listSourceEvents(db, vogue!.id);
    const nikki = vogueEvents.find((e) => e.title === "Nikki Lane")!;
    assert.equal(Date.parse(nikki.startUtc ?? ""), Date.parse("2026-11-15T01:00:00Z"));
    assert.equal(nikki.startLocal, "2026-11-14T20:00");
    assert.match(nikki.data.ticketUrl ?? "", /ticketmaster\.com/, "ticket links are kept as strings");
    assert.equal(vogueEvents.find((e) => e.title.startsWith("Late Night Laughs"))!.data.category, "comedy");
    const hifiEvents = listSourceEvents(db, hifi!.id);
    const openMics = hifiEvents.filter((e) => e.data.category === "open_mic");
    assert.equal(openMics.length, 3);
    assert.deepEqual(openMics.map((e) => e.startLocal).sort(), [
      "2026-11-04T19:00",
      "2026-11-11T19:00",
      "2026-11-18T19:00",
    ]);

    // NDJSON dry run: exact envelopes, venue from the source row, evidence metadata only.
    const lines = readFileSync(ndjson, "utf8")
      .trim()
      .split("\n")
      .map((l) => JSON.parse(l));
    assert.equal(lines.length, 8);
    for (const line of lines) {
      assert.equal(line.envelope.source, "event-scraper");
      assert.equal(line.envelope.venueRoutingStatus, "resolved");
      assert.ok(["venue-vogue", "venue-hifi-room"].includes(line.envelope.venueId));
      assert.ok(line.evidence?.sha256, "every observation points at stored page bytes");
    }

    // Nothing on a ticketing platform was ever requested.
    assert.ok(net.calls.length > 0);
    assert.ok(!net.calls.some((c) => isTicketingUrl(c.url)), net.calls.map((c) => c.url).join("\n"));

    // --- scheduling: nothing is due right away; two days later the unchanged content backs off ------------------
    const again = await run("run-once");
    assert.equal(again.json().run.processed, 0);
    nowMs += 2 * 24 * 3600_000;
    const later = await run("run-once");
    const laterRun = later.json().run;
    assert.equal(laterRun.processed, 2);
    const vogueLater = laterRun.sources.find((s: { sourceId: string }) => s.sourceId === vogue!.id);
    assert.equal(vogueLater.outcome, "unchanged_bytes", "identical bytes skip extraction (self-contained page)");
    assert.ok(vogueLater.nextFetchInHours >= 48, "unchanged content backs off");
    const hifiLater = laterRun.sources.find((s: { sourceId: string }) => s.sourceId === hifi!.id);
    assert.equal(hifiLater.outcome, "extracted", "followed endpoints are re-extracted even when the page is identical");
    assert.equal(hifiLater.changes.new, 0);
    assert.equal(readFileSync(ndjson, "utf8").trim().split("\n").length, 8, "no duplicate observations");

    // --- discovery ------------------------------------------------------------------------------------------------
    const discovered = await run("discover");
    assert.equal(discovered.code, 0, discovered.stderr);
    const d = discovered.json();
    assert.equal(overpassQueries.length, 1);
    assert.ok(d.placesRequests > 0 && d.placesRequests <= d.placesBudget);
    assert.deepEqual(
      places.requests.map((r) => r.textQuery),
      ["live music venue", "live music venue", "comedy club"],
      "configured queries, paginated",
    );
    assert.equal(d.pipeline.proved.promoted, 1);
    assert.equal(d.promoted.length, 1);

    const promoted = getCandidate(db, d.promoted[0])!;
    assert.match(promoted.name, /Mercury Room/);
    assert.equal(promoted.status, "promoted");
    assert.equal(promoted.sourceUrl, "https://mercuryroomindy.com/shows/");
    assert.equal(promoted.provenEventCount, 4);
    // Multi place-id resolution: the business, its building/premise and the "events" listing are one venue.
    for (const placeId of ["ChIJ_MERCURY_BIZ", "ChIJ_MERCURY_PREMISE", "ChIJ_MERCURY_EVENTS"]) {
      assert.equal(resolvePlaceId(db, placeId)?.candidateId, promoted.id, placeId);
    }
    const canonical = listPlaceAliases(db, { candidateId: promoted.id }).filter((a) => a.isCanonical);
    assert.deepEqual(
      canonical.map((a) => a.placeId),
      ["ChIJ_MERCURY_BIZ"],
    );
    for (const area of ["ChIJ_FOUNTAIN_SQUARE", "ChIJ_INDIANAPOLIS"]) {
      assert.equal(resolvePlaceId(db, area), null, `${area} is a geocode area, never an identity`);
    }
    // Same building, similar names (rooms in one building): never auto-merged, a human decides.
    const hifiRooms = listCandidates(db).filter((c) => /hi-fi/i.test(c.name));
    assert.deepEqual(hifiRooms.map((c) => c.name).sort(), ["Hi-Fi Annex", "The Hi-Fi"]);
    assert.ok(hifiRooms.every((c) => c.status === "needs_review"));
    assert.equal(resolvePlaceId(db, "ChIJ_HIFI_BIZ"), null, "no alias is assigned while identity is in doubt");
    // OSM's "Mercury Room" merged into the Places candidate instead of creating a duplicate.
    assert.equal(listCandidates(db).filter((c) => /mercury/i.test(c.name)).length, 1);
    assert.ok(listCandidates(db).some((c) => c.name === "Radio Radio" && c.discoveredFrom === "osm"));
    // Everyone else is no_source (their sites are 404 here) and will be retried monthly.
    const others = listCandidates(db).filter((c) => c.status === "no_source");
    assert.ok(others.length > 0);
    assert.ok(others.every((c) => (c.nextAttemptAt ?? 0) > nowMs + 25 * 24 * 3600_000));

    // A second discover right away does not hit Places or Overpass again (refresh interval).
    const second = (await run("discover", "--skip-prove")).json();
    assert.equal(second.placesRequests, 0);
    assert.equal(overpassQueries.length, 1);

    // --- review export + approve flow guard -------------------------------------------------------------------
    const exported = await run("export-candidates", "--out", join(dir, "review"));
    assert.equal(exported.code, 0, exported.stderr);
    const files = exported.json();
    assert.ok(files.count >= 1);
    assert.ok(existsSync(files.csvPath));
    assert.match(readFileSync(files.csvPath, "utf8"), /Mercury Room/);
    const approve = await run("add-source", "--candidate", String(promoted.id));
    assert.equal(approve.code, 2, "no production venue profile exists yet: a human creates it first");

    const status = (await run("status")).json();
    assert.equal(status.sources.enabled, 2);
    assert.equal(status.pendingOutbox, 0);
    assert.ok(!net.calls.some((c) => isTicketingUrl(c.url)));
    db.close();
  });
});
