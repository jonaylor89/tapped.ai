import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, test } from "node:test";
import { type Db, getCandidate, getRawPage, insertCandidate, updateCandidate } from "../src/db.js";
import { buildReviewList, csvCell, reviewListToCsv, writeReviewList } from "../src/discovery/export.js";
import { DEFAULT_RETRY_AFTER_MS, proveCandidate, runCandidatePipeline } from "../src/discovery/prove.js";
import { recordProbe } from "../src/discovery/resolve.js";
import {
  findEventSources,
  rankCalendarLinks,
  scoreCalendarLink,
  websiteRejection,
} from "../src/discovery/source-finder.js";
import type { LlmClient, LlmJsonRequest } from "../src/types.js";
import { openTestDb } from "./helpers/db.js";
import { fakeFetch, fixedClock, fixtureText, NOW_MS, politeClient } from "./helpers/discovery.js";

const TZ = "America/Indiana/Indianapolis";

function healerSite() {
  return fakeFetch({
    "https://healerindy.com/": fixtureText("healer-home.html"),
    "https://healerindy.com/shows/": fixtureText("healer-shows.html"),
  });
}

function thinSite() {
  return fakeFetch({
    "https://radioradioindy.com/": fixtureText("thin-home.html"),
    "https://radioradioindy.com/events/": fixtureText("thin-events.html"),
  });
}

describe("source finder", () => {
  test("link scoring prefers calendars and penalizes rentals, archives and single events", () => {
    const s = (path: string, text = "") => scoreCalendarLink(new URL(path, "https://v.example"), text);
    assert.ok(s("/events/", "Events") > s("/event/some-show/", "Some Show"));
    assert.ok(s("/calendar") > 0);
    assert.ok(s("/live-music/") > 0);
    assert.ok(s("/whats-on/") > 0);
    assert.ok(s("/private-events/", "Private Events") <= 0);
    assert.ok(s("/shows/past/", "Past shows") <= 0);
    assert.ok(s("/about/", "About") <= 0);
    assert.ok(s("/events/2026/11/07/foo/") < s("/events/"));
  });

  test("ranks same-site calendar links; never ticketing or social links", () => {
    const links = rankCalendarLinks(fixtureText("healer-home.html"), "https://healerindy.com/");
    assert.equal(links[0]?.url, "https://healerindy.com/shows/");
    assert.ok(!links.some((l) => /etix|instagram|private-events|mailto/.test(l.url)));
  });

  test("rejects websites that are not the venue's own", () => {
    assert.equal(websiteRejection(null), "no_website");
    assert.equal(websiteRejection("https://www.ticketweb.com/venue/the-hi-fi"), "ticketing_website");
    assert.equal(websiteRejection("https://www.facebook.com/healerindy"), "social_website");
    assert.equal(websiteRejection("https://linktr.ee/healer"), "social_website");
    assert.equal(websiteRejection("healerindy.com"), null);
  });

  test("proposes the shows page first, homepage last", async () => {
    const net = healerSite();
    const result = await findEventSources(
      { name: "Healer", website: "https://healerindy.com" },
      { http: politeClient(net.fetchImpl) },
    );
    assert.ok(result.ok);
    assert.equal(result.proposals[0]?.url, "https://healerindy.com/shows/");
    assert.equal(result.proposals[0]?.kind, "html");
    assert.equal(result.proposals.at(-1)?.via, "homepage");
    assert.equal(result.llmUsed, false);
    assert.ok(!net.calls.some((c) => c.url.includes("etix")));
  });

  test("structured CMS endpoints on the venue's own domain come first", async () => {
    const net = fakeFetch({ "https://mercuryroomindy.com/": fixtureText("wp-tribe-home.html") });
    const result = await findEventSources(
      { name: "The Mercury Room", website: "https://mercuryroomindy.com/" },
      { http: politeClient(net.fetchImpl) },
    );
    assert.equal(result.proposals[0]?.kind, "wp_tribe");
    assert.match(result.proposals[0]!.url, /^https:\/\/mercuryroomindy\.com\/wp-json\/tribe\/events\/v1\/events/);
    assert.ok(result.proposals.some((p) => p.url === "https://mercuryroomindy.com/calendar/"));
    assert.ok(!result.proposals.some((p) => p.url.includes("rentals")));
  });

  test("asks the LLM only when heuristics are unsure, and validates its answer", async () => {
    const html = `<a href="/music/">Music</a><a href="/entertainment/">Entertainment</a><a href="/about/">About</a>`;
    const net = fakeFetch({ "https://unsure.example/": html });
    const requests: LlmJsonRequest[] = [];
    const llm: LlmClient = {
      completeJson: async (req) => {
        requests.push(req);
        return {
          data: { choice: 1, reason: "entertainment lists shows" },
          model: "fake",
          inputTokens: 1,
          outputTokens: 1,
        };
      },
    };
    const result = await findEventSources(
      { name: "Unsure", website: "https://unsure.example/" },
      { http: politeClient(net.fetchImpl), llm },
    );
    assert.equal(requests.length, 1);
    assert.equal(requests[0]!.schemaName, "event_page_choice");
    assert.equal(result.proposals[0]?.via, "llm");
    assert.equal(result.proposals[0]?.url, "https://unsure.example/entertainment/");

    const bad: LlmClient = {
      completeJson: async () => ({ data: { choice: 99 }, model: "fake", inputTokens: 0, outputTokens: 0 }),
    };
    const fallback = await findEventSources(
      { name: "Unsure", website: "https://unsure.example/" },
      { http: politeClient(net.fetchImpl), llm: bad },
    );
    assert.ok(!fallback.proposals.some((p) => p.via === "llm"), "out-of-range answers are ignored");
  });

  test("ticketing websites, robots blocks and off-site redirects yield no proposals", async () => {
    const empty = fakeFetch({});
    const ticketing = await findEventSources(
      { name: "X", website: "https://www.axs.com/venues/123/the-x" },
      { http: politeClient(empty.fetchImpl) },
    );
    assert.deepEqual([ticketing.ok, ticketing.reason], [false, "ticketing_website"]);
    assert.equal(empty.calls.length, 0);

    const robots = fakeFetch({
      "https://blocked.example/robots.txt": () => new Response("User-agent: *\nDisallow: /\n", { status: 200 }),
    });
    const blocked = await findEventSources(
      { name: "B", website: "https://blocked.example/" },
      { http: politeClient(robots.fetchImpl) },
    );
    assert.equal(blocked.reason, "robots_blocked");
    assert.ok(!robots.calls.some((c) => c.url === "https://blocked.example/"));

    const redirect = fakeFetch({
      "https://bio.example/": () => new Response(null, { status: 301, headers: { location: "https://linktr.ee/bio" } }),
      "https://linktr.ee/bio": "<html></html>",
    });
    const offsite = await findEventSources(
      { name: "R", website: "https://bio.example/" },
      { http: politeClient(redirect.fetchImpl) },
    );
    assert.equal(offsite.reason, "social_website");

    const ticketRedirect = fakeFetch({
      "https://tix.example/": () =>
        new Response(null, { status: 302, headers: { location: "https://www.eventbrite.com/o/123" } }),
    });
    const toTicketing = await findEventSources(
      { name: "T", website: "https://tix.example/" },
      { http: politeClient(ticketRedirect.fetchImpl) },
    );
    assert.equal(toTicketing.reason, "ticketing_website");
    assert.ok(!ticketRedirect.calls.some((c) => c.url.includes("eventbrite")));
  });
});

describe("prove", () => {
  async function healerCandidate(db: Db) {
    return (
      await recordProbe(
        db,
        {
          name: "Healer",
          city: "Indianapolis",
          lat: 39.7741,
          lng: -86.1338,
          website: "https://healerindy.com/",
          timezone: TZ,
          discoveredFrom: "listing",
        },
        { now: NOW_MS },
      )
    ).candidate;
  }

  test("promotes with >= 3 valid upcoming events using the real extract + validate pipeline", async () => {
    const db = await openTestDb();
    const candidate = await healerCandidate(db);
    const net = healerSite();
    const result = await proveCandidate(db, candidate.id, { http: politeClient(net.fetchImpl), clock: fixedClock });
    assert.equal(result.status, "promoted", JSON.stringify(result.attempts));
    assert.equal(result.upcoming, 4, "the past show is not counted");
    const stored = (await getCandidate(db, candidate.id))!;
    assert.equal(stored.status, "promoted");
    assert.equal(stored.sourceUrl, "https://healerindy.com/shows/");
    assert.equal(stored.sourceKind, "html");
    assert.equal(stored.provenEventCount, 4);
    assert.equal(stored.attempts, 1);
    assert.equal(stored.nextAttemptAt, null);
    const proof = stored.evidence.proof as {
      sample: { title: string; ticketUrl: string | null }[];
      evidenceSha256: string;
    };
    assert.ok(proof.sample.some((e) => e.title === "Ghost Pepper w/ Static Bloom"));
    assert.ok(await getRawPage(db, proof.evidenceSha256), "evidence page bytes stored");
    assert.ok(!net.calls.some((c) => c.url.includes("etix")), "ticket links are recorded, never fetched");
  });

  test("too few events => no_source, retried in 30 days", async () => {
    const db = await openTestDb();
    const candidate = (
      await recordProbe(
        db,
        {
          name: "Radio Radio",
          lat: 39.77,
          lng: -86.13,
          website: "https://radioradioindy.com",
          timezone: TZ,
          discoveredFrom: "osm",
        },
        { now: NOW_MS },
      )
    ).candidate;
    const net = thinSite();
    const result = await proveCandidate(db, candidate.id, { http: politeClient(net.fetchImpl), clock: fixedClock });
    assert.equal(result.status, "no_source");
    assert.equal(result.reason, "insufficient_events:1/3");
    const stored = (await getCandidate(db, candidate.id))!;
    assert.equal(stored.nextAttemptAt, NOW_MS + DEFAULT_RETRY_AFTER_MS);
    assert.equal(stored.provenEventCount, 1);
    // A lower threshold (configurable) promotes the same site.
    await updateCandidate(db, candidate.id, { status: "resolved", nextAttemptAt: null }, NOW_MS);
    const lenient = await proveCandidate(db, candidate.id, {
      http: politeClient(thinSite().fetchImpl),
      clock: fixedClock,
      minEvents: 1,
    });
    assert.equal(lenient.status, "promoted");
  });

  test("missing website / timezone and finder failures => no_source with a reason", async () => {
    const db = await openTestDb();
    const noSite = await insertCandidate(
      db,
      { name: "No Site", discoveredFrom: "osm", timezone: TZ, status: "resolved" },
      NOW_MS,
    );
    const r1 = await proveCandidate(db, noSite.id, { http: politeClient(fakeFetch({}).fetchImpl), clock: fixedClock });
    assert.deepEqual([r1.status, r1.reason], ["no_source", "no_website"]);
    const noTz = await insertCandidate(
      db,
      // Named like the site's events' location so they count toward the proof.
      { name: "Healer", website: "https://healerindy.com", discoveredFrom: "osm", status: "resolved" },
      NOW_MS,
    );
    const r2 = await proveCandidate(db, noTz.id, { http: politeClient(fakeFetch({}).fetchImpl), clock: fixedClock });
    assert.deepEqual([r2.status, r2.reason], ["no_source", "missing_timezone"]);
    const r3 = await proveCandidate(db, noTz.id, {
      http: politeClient(healerSite().fetchImpl),
      clock: fixedClock,
      defaultTimezone: TZ,
    });
    assert.equal(r3.status, "promoted", "defaultTimezone fills the gap");
  });

  test("injected extract/validate stubs are honored (no network beyond the fake)", async () => {
    const db = await openTestDb();
    const candidate = await healerCandidate(db);
    let validated = 0;
    const result = await proveCandidate(db, candidate.id, {
      http: politeClient(healerSite().fetchImpl),
      clock: fixedClock,
      findSources: async () => ({
        ok: true,
        reason: null,
        homepage: "https://healerindy.com/",
        homepageStatus: 200,
        proposals: [{ kind: "html", url: "https://healerindy.com/shows/", score: 1, via: "link", reason: "stub" }],
        links: [],
        endpoints: [],
        llmUsed: false,
      }),
      extract: async (page) => ({ events: [], page, extractor: null }),
      validate: () => {
        validated++;
        return { valid: [], rejected: [] };
      },
    });
    assert.equal(validated, 1);
    assert.equal(result.reason, "insufficient_events:0/3");
  });

  test("pipeline resolves new candidates, proves due ones, and export lists them for review", async () => {
    const db = await openTestDb();
    await insertCandidate(
      db,
      {
        name: "Healer",
        lat: 39.7741,
        lng: -86.1338,
        website: "https://healerindy.com/",
        timezone: TZ,
        discoveredFrom: "manual",
        status: "new",
      },
      NOW_MS,
    );
    await recordProbe(
      db,
      {
        name: '=HYPERLINK("http://evil")',
        lat: 39.7,
        lng: -86.1,
        discoveredFrom: "google_places",
        reviewReason: "nearby_similar_name",
        reviewDetails: [{ placeId: "x" }],
        places: [{ placeId: "ChIJ_REVIEW", types: ["bar"], displayName: "x", lat: 39.7, lng: -86.1, canonical: true }],
      },
      { now: NOW_MS },
    );
    const summary = await runCandidatePipeline(db, { http: politeClient(healerSite().fetchImpl), clock: fixedClock });
    assert.equal(summary.resolved, 1);
    assert.equal(summary.proved.length, 1);
    assert.equal(summary.proved[0]!.status, "promoted");

    const entries = await buildReviewList(db);
    assert.deepEqual(
      entries.map((e) => e.status),
      ["promoted", "needs_review"],
    );
    assert.equal(entries[0]!.sourceUrl, "https://healerindy.com/shows/");
    assert.equal(entries[0]!.sampleEvents.length, 4);
    assert.deepEqual(entries[1]!.placeIds, ["ChIJ_REVIEW"]);
    assert.deepEqual(entries[1]!.review, [{ placeId: "x" }]);

    const csv = reviewListToCsv(entries);
    const lines = csv.trimEnd().split("\n");
    assert.match(lines[0]!, /^candidateId,status,statusReason,name,/);
    assert.equal(lines.length, 3);
    assert.ok(csv.includes(`"'=HYPERLINK(""http://evil"")"`), "formula injection neutralized and quotes escaped");
    assert.equal(csvCell(-12.5), "-12.5");
    assert.equal(csvCell(["a", "b"]), "a; b");

    const dir = mkdtempSync(join(tmpdir(), "event-scraper-review-"));
    const written = await writeReviewList(db, dir, { now: new Date(NOW_MS) });
    assert.equal(written.count, 2);
    assert.match(written.jsonPath, /venue-review-2026-11-02\.json$/);
    assert.equal(JSON.parse(readFileSync(written.jsonPath, "utf8")).length, 2);
    assert.equal(readFileSync(written.csvPath, "utf8"), csv);
  });
});
