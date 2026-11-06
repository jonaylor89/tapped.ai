import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { extractEvents, extractStructured, STRUCTURED_EXTRACTORS } from "../../src/extract/index.js";
import { blankEvent } from "../../src/extract/util.js";
import type { Extractor } from "../../src/types.js";
import { byTitle, FakeHttp, fixture, fixturePage, makeCtx, makePage } from "./helpers.js";

describe("extractStructured", () => {
  test("cheapest-first order", () => {
    assert.deepEqual(
      STRUCTURED_EXTRACTORS.map((e) => e.name),
      ["ical", "wp_tribe", "squarespace", "aeg", "rhp", "webflow_shows", "season_dates", "jsonld", "microdata"],
    );
  });

  test("reports the winning extractor per content type", async () => {
    const cases: [string, string, string][] = [
      ["jsonld-graph-yoast.html", "https://www.redlinetavern.com/shows/", "jsonld"],
      ["microdata-calendar.html", "https://www.bluedoorbar.com/events", "microdata"],
      ["venue-calendar.ics", "https://www.redlinetavern.com/?ical=1", "ical"],
      ["wp-tribe-page1.json", "https://www.saltshedmusic.com/wp-json/tribe/events/v1/events", "wp_tribe"],
      ["squarespace-events.json", "https://www.owllisteningroom.com/shows?format=json", "squarespace"],
      ["aeg-events.json", "https://example-content.test/json/events/51/events.json", "aeg"],
    ];
    for (const [name, url, winner] of cases) {
      const result = await extractStructured(fixturePage(name, url), makeCtx(url));
      assert.equal(result.extractor, winner, name);
      assert.ok(result.events.length > 0, name);
      assert.ok(
        result.events.every((e) => e.extractor === winner),
        name,
      );
      assert.deepEqual(result.errors, [], name);
    }
  });

  test("JSON-LD wins, microdata-only events on the same page are merged in, duplicates collapse", async () => {
    const url = "https://mercurywest.com/shows";
    const result = await extractStructured(fixturePage("jsonld-plus-microdata.html", url), makeCtx(url));
    assert.equal(result.extractor, "jsonld");
    assert.deepEqual(result.attempted, ["jsonld", "microdata"]);
    assert.deepEqual(
      result.events.map((e) => [e.title, e.extractor]),
      [
        ["Hand Habits", "jsonld"],
        ["Wednesday", "jsonld"],
        ["Songwriter Round", "microdata"],
      ],
    );
    const hh = byTitle(result.events, "Hand Habits");
    assert.equal(hh.imageUrl, "https://mercurywest.com/img/hh.jpg", "filled from the duplicate JSON-LD block");
    assert.deepEqual(hh.performers, ["Hand Habits"], "filled from microdata");
    assert.equal(byTitle(result.events, "Songwriter Round").eventUrl, "https://mercurywest.com/shows/songwriter-round");
  });

  test("HTML without structured data follows the venue's own advertised endpoints via ctx.http", async () => {
    const url = "https://www.saltshedmusic.com/events/";
    const api = "https://www.saltshedmusic.com/wp-json/tribe/events/v1/events?per_page=50";
    const http = new FakeHttp({
      [api]: { contentType: "application/json", body: fixture("wp-tribe-page1.json") },
      "https://www.saltshedmusic.com/wp-json/tribe/events/v1/events/?page=2&per_page=3": {
        contentType: "application/json",
        body: fixture("wp-tribe-page2.json"),
      },
    });
    const result = await extractStructured(fixturePage("wp-tribe-venue-page.html", url), makeCtx(url, { http }));
    assert.equal(result.extractor, "wp_tribe");
    assert.equal(result.events.length, 5);
    assert.equal(result.page.url, api, "evidence page is the endpoint response");
    assert.equal(result.followed.length, 1);
    assert.equal(result.followed[0].ok, true);
    assert.equal(result.followed[0].eventCount, 5);
    assert.ok(http.requests.every((r) => r.url.startsWith("https://www.saltshedmusic.com/")));
  });

  test("a failing endpoint falls through to the next one (ICS export)", async () => {
    const url = "https://www.saltshedmusic.com/events/";
    const ics = "https://www.saltshedmusic.com/?post_type=tribe_events&ical=1&eventDisplay=list";
    const http = new FakeHttp({ [ics]: { contentType: "text/calendar", body: fixture("venue-calendar.ics") } });
    const result = await extractStructured(fixturePage("wp-tribe-venue-page.html", url), makeCtx(url, { http }));
    assert.equal(result.extractor, "ical");
    assert.equal(result.followed[0].ok, false);
    assert.equal(result.followed[0].status, 404);
    assert.equal(result.followed[1].endpoint.url, ics);
    assert.equal(http.requests[1].accept?.startsWith("text/calendar"), true);
  });

  test("Google Calendar embed is followed only after the venue's own ICS fails; ticketing links never fetched", async () => {
    const url = "https://velvetroomlouisville.com/calendar";
    const gcal = "https://calendar.google.com/calendar/ical/velvetroomlive%40gmail.com/public/basic.ics";
    const http = new FakeHttp({ [gcal]: { contentType: "text/calendar", body: fixture("google-calendar.ics") } });
    const result = await extractStructured(
      fixturePage("gcal-embed-page.html", url),
      makeCtx(url, { http, timezone: "America/New_York" }),
    );
    assert.equal(result.extractor, "ical");
    assert.equal(result.events.length, 7);
    assert.deepEqual(
      http.requests.map((r) => r.url),
      ["https://velvetroomlouisville.com/calendar/velvet-room.ics", gcal],
    );
  });

  test("no http, no structured data: empty result with endpoints listed but not followed", async () => {
    const url = "https://www.saltshedmusic.com/events/";
    const result = await extractStructured(fixturePage("wp-tribe-venue-page.html", url), makeCtx(url));
    assert.equal(result.extractor, null);
    assert.deepEqual(result.events, []);
    assert.ok(result.endpoints.length >= 3);
    assert.deepEqual(result.followed, []);
  });

  test("followEndpoints=false and maxFollow are honored", async () => {
    const url = "https://www.saltshedmusic.com/events/";
    const http = new FakeHttp({});
    await extractStructured(fixturePage("wp-tribe-venue-page.html", url), makeCtx(url, { http }), {
      followEndpoints: false,
    });
    assert.equal(http.requests.length, 0);
    const result = await extractStructured(fixturePage("wp-tribe-venue-page.html", url), makeCtx(url, { http }), {
      maxFollow: 1,
    });
    assert.equal(http.requests.length, 1);
    assert.equal(result.followed.length, 1);
  });

  test("a throwing extractor is recorded and the next one still runs", async () => {
    const boom: Extractor = {
      name: "boom",
      canHandle: () => true,
      extract: () => {
        throw new Error("kaboom");
      },
    };
    const url = "https://www.redlinetavern.com/shows/";
    const result = await extractStructured(fixturePage("jsonld-graph-yoast.html", url), makeCtx(url), {
      extractors: [boom, ...STRUCTURED_EXTRACTORS],
    });
    assert.equal(result.extractor, "jsonld");
    assert.deepEqual(result.errors, [{ extractor: "boom", message: "kaboom" }]);
  });
});

test("a ticketing-platform event URL is demoted to ticketUrl", async () => {
  const html = `<html><head><script type="application/ld+json">{"@type":"MusicEvent","name":"Big Show",
    "startDate":"2026-11-20T20:00:00-06:00","url":"https://www.eventbrite.com/e/big-show-123"}</script></head></html>`;
  const url = "https://venue.com/events";
  const result = await extractStructured(makePage(html, url), makeCtx(url));
  assert.equal(result.events[0].eventUrl, null);
  assert.equal(result.events[0].ticketUrl, "https://www.eventbrite.com/e/big-show-123");
});

describe("extractEvents", () => {
  test("uses the fallback only when structured extraction found nothing", async () => {
    let calls = 0;
    const fallback: Extractor = {
      name: "llm",
      canHandle: () => true,
      extract: () => {
        calls++;
        return [{ ...blankEvent("llm"), title: "Live Music Every Friday", start: "--11-06T21:00" }];
      },
    };
    const plainUrl = "https://cornerpub.com/events";
    const plain = await extractEvents(fixturePage("plain-no-structured.html", plainUrl), makeCtx(plainUrl), {
      fallback,
    });
    assert.equal(plain.extractor, "llm");
    assert.equal(plain.events.length, 1);
    assert.deepEqual(plain.attempted, ["llm"]);

    const url = "https://www.redlinetavern.com/shows/";
    const structured = await extractEvents(fixturePage("jsonld-graph-yoast.html", url), makeCtx(url), { fallback });
    assert.equal(structured.extractor, "jsonld");
    assert.equal(calls, 1);
  });
});
