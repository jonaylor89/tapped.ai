import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { discoverStructuredEndpoints, googleCalendarIcsUrl } from "../../src/extract/endpoints.js";
import { extractSquarespace, squarespaceExtractor, squarespaceJsonUrl } from "../../src/extract/squarespace.js";
import { extractWpTribe, tribeEventsApiUrl, tribeNextPageUrl, wpTribeExtractor } from "../../src/extract/wp-tribe.js";
import { byTitle, FakeHttp, fixture, fixturePage, makeCtx } from "./helpers.js";

const TRIBE_P1 = "https://www.saltshedmusic.com/wp-json/tribe/events/v1/events?per_page=3";
const TRIBE_P2 = "https://www.saltshedmusic.com/wp-json/tribe/events/v1/events/?page=2&per_page=3";

describe("The Events Calendar (wp_tribe)", () => {
  test("single page without http: maps every field", async () => {
    const page = fixturePage("wp-tribe-page1.json", TRIBE_P1);
    const ctx = makeCtx(TRIBE_P1);
    assert.equal(wpTribeExtractor.canHandle(page, ctx), true);
    const events = await extractWpTribe(page, ctx);
    assert.equal(events.length, 3);

    const neko = byTitle(events, "Neko Case – Live in Concert");
    assert.equal(neko.extractor, "wp_tribe");
    assert.equal(neko.start, "2026-11-08T19:30");
    assert.equal(neko.startInstant, "2026-11-09T01:30:00.000Z");
    assert.equal(neko.end, "2026-11-08T22:30");
    assert.equal(neko.description, "Neko Case returns with her full band.\n\nSeated show & bar.");
    assert.equal(neko.eventUrl, "https://www.saltshedmusic.com/event/neko-case/");
    assert.equal(neko.imageUrl, "https://www.saltshedmusic.com/wp-content/uploads/2026/09/neko.jpg");
    assert.equal(neko.ticketUrl, "https://www.axs.com/events/123456/neko-case-tickets");
    assert.deepEqual(neko.prices, [
      { kind: "ticket", minCents: 4500, maxCents: 6500, currency: "USD", text: "$45 – $65" },
    ]);
    assert.equal(neko.isFree, false);
    assert.equal(neko.category, "music");
    assert.equal(neko.sourceEventId, "wp:4821");
    assert.deepEqual(neko.location, {
      name: "The Salt Shed",
      address: "1357 N Elston Ave, Chicago, IL, 60642, United States",
      lat: 41.9069,
      lng: -87.6614,
      url: "https://www.saltshedmusic.com/",
    });

    const comedy = byTitle(events, "Comedy Night: Hannah Gadsby");
    assert.equal(comedy.isFree, true);
    assert.equal(comedy.end, null, "end equal to start is no end");
    assert.equal(comedy.category, "comedy");
    assert.equal(comedy.description, "Stand-up in the Shed.");
    assert.equal(comedy.imageUrl, null);
    assert.equal(comedy.location, null);

    const day = byTitle(events, "Neighborhood Day");
    assert.equal(day.start, "2026-11-14");
    assert.equal(day.end, null);
    assert.equal(day.startInstant, null);
  });

  test("follows next_rest_url through ctx.http; title status prefix; misconfigured UTC+0 site zone", async () => {
    const http = new FakeHttp({
      [TRIBE_P2]: { contentType: "application/json", body: fixture("wp-tribe-page2.json") },
    });
    const events = await extractWpTribe(fixturePage("wp-tribe-page1.json", TRIBE_P1), makeCtx(TRIBE_P1, { http }));
    assert.equal(events.length, 5);
    assert.deepEqual(
      http.requests.map((r) => r.url),
      [TRIBE_P2],
    );
    assert.equal(http.requests[0].accept, "application/json");

    const holdSteady = byTitle(events, "The Hold Steady");
    assert.equal(holdSteady.status, "canceled");
    assert.equal(holdSteady.prices[0].minCents, 3500);

    const vinyl = byTitle(events, "Vinyl Night w/ DJ Sadie & Friends");
    assert.equal(vinyl.start, "2026-11-21T21:00", "wall-clock start_date wins over a bogus UTC+0 conversion");
    assert.equal(vinyl.startInstant, null);
    assert.equal(vinyl.end, "2026-11-22T02:00");
    assert.deepEqual(
      vinyl.prices.map((p) => [p.kind, p.minCents]),
      [
        ["advance", 1000],
        ["door", 1500],
      ],
    );
    assert.equal(vinyl.category, "music");
  });

  test("pagination stops at maxPages and never leaves the host", async () => {
    const http = new FakeHttp({
      [TRIBE_P2]: { contentType: "application/json", body: fixture("wp-tribe-page2.json") },
    });
    const events = await extractWpTribe(fixturePage("wp-tribe-page1.json", TRIBE_P1), makeCtx(TRIBE_P1, { http }), 1);
    assert.equal(events.length, 3);
    assert.equal(http.requests.length, 0);
    assert.equal(tribeNextPageUrl({ next_rest_url: "https://evil.example.net/wp-json/x" }, TRIBE_P1), null);
    assert.equal(tribeNextPageUrl({ next_rest_url: "https://www.eventbrite.com/x" }, TRIBE_P1), null);
    assert.equal(tribeNextPageUrl({}, TRIBE_P1), null);
  });

  test("tribeEventsApiUrl builds the endpoint from site, wp-json root, events page or subdirectory installs", () => {
    assert.equal(
      tribeEventsApiUrl("https://venue.com/"),
      "https://venue.com/wp-json/tribe/events/v1/events?per_page=50",
    );
    assert.equal(
      tribeEventsApiUrl("https://venue.com/wp-json/", { startDate: "2026-11-02", perPage: 20 }),
      "https://venue.com/wp-json/tribe/events/v1/events?per_page=20&start_date=2026-11-02",
    );
    assert.equal(
      tribeEventsApiUrl("https://venue.com/blog/events/list/"),
      "https://venue.com/blog/wp-json/tribe/events/v1/events?per_page=50",
    );
    assert.equal(
      tribeEventsApiUrl("https://venue.com/wp-json/tribe/events/v1/"),
      "https://venue.com/wp-json/tribe/events/v1/events?per_page=50",
    );
    assert.equal(tribeEventsApiUrl("mailto:x@y.com"), null);
  });
});

describe("Squarespace events collection", () => {
  const URL = "https://www.owllisteningroom.com/shows?format=json";

  test("upcoming items: epoch instants, entities, ticket link from body, default map pin ignored, past ignored", () => {
    const page = fixturePage("squarespace-events.json", URL);
    const ctx = makeCtx(URL);
    assert.equal(squarespaceExtractor.canHandle(page, ctx), true);
    assert.equal(wpTribeExtractor.canHandle(page, ctx), false);
    const events = extractSquarespace(page, ctx);
    assert.equal(events.length, 3);
    assert.equal(
      events.find((e) => e.title === "Some Past Show"),
      undefined,
    );

    const molly = byTitle(events, "Molly Tuttle & Golden Highway");
    assert.equal(molly.extractor, "squarespace");
    assert.equal(molly.start, "2026-11-10T19:00");
    assert.equal(molly.startInstant, "2026-11-11T01:00:00.000Z");
    assert.equal(molly.end, "2026-11-10T22:00");
    assert.equal(molly.eventUrl, "https://www.owllisteningroom.com/shows/molly-tuttle");
    assert.equal(molly.imageUrl, "https://images.squarespace-cdn.com/content/v1/abc/molly.jpg");
    assert.equal(molly.ticketUrl, "https://www.eventbrite.com/e/molly-tuttle-tickets-1234");
    assert.deepEqual(
      molly.prices.map((p) => [p.kind, p.minCents, p.currency]),
      [
        ["advance", 2800, "USD"],
        ["door", 3200, "USD"],
      ],
    );
    assert.equal(molly.category, "music");
    assert.equal(molly.location?.lat, 36.1489);
    assert.equal(molly.sourceEventId, "sqs:64aa01");

    const poetry = byTitle(events, "Poetry & Open Mic");
    assert.equal(poetry.category, "open_mic");
    assert.equal(poetry.isFree, true);
    assert.equal(poetry.location, null);
    assert.equal(poetry.end, null);
    assert.equal(poetry.imageUrl, null);

    const nye = byTitle(events, "New Year's Eve with The Tulsa Allstars");
    assert.equal(nye.start, "2026-12-31T21:00");
    assert.equal(nye.end, "2027-01-01T01:00");
    assert.equal(nye.description, "Party favors included.");
  });

  test("squarespaceJsonUrl", () => {
    assert.equal(squarespaceJsonUrl("https://venue.com/shows?view=calendar#x"), "https://venue.com/shows?format=json");
  });
});

describe("discoverStructuredEndpoints", () => {
  test("WordPress + TEC page: tribe API first, list ICS exports, no off-site or ticketing links", () => {
    const url = "https://www.saltshedmusic.com/events/";
    const endpoints = discoverStructuredEndpoints(fixture("wp-tribe-venue-page.html"), url);
    assert.equal(endpoints[0].kind, "wp_tribe");
    assert.equal(endpoints[0].url, "https://www.saltshedmusic.com/wp-json/tribe/events/v1/events?per_page=50");
    const urls = endpoints.map((e) => e.url);
    assert.ok(urls.includes("https://www.saltshedmusic.com/?post_type=tribe_events&ical=1&eventDisplay=list"));
    assert.ok(urls.includes("https://www.saltshedmusic.com/events/list/?ical=1"));
    assert.ok(!urls.some((u) => u.includes("axs.com") || u.includes("google.com")));
    assert.ok(endpoints.every((e) => e.sameSite));
  });

  test("Squarespace home: events nav link becomes ?format=json; Squarespace list page points at itself", () => {
    const home = discoverStructuredEndpoints(
      fixture("squarespace-venue-home.html"),
      "https://www.owllisteningroom.com/",
    );
    assert.deepEqual(
      home.map((e) => [e.kind, e.url]),
      [["squarespace", "https://www.owllisteningroom.com/shows?format=json"]],
    );
    const list = discoverStructuredEndpoints(
      fixture("squarespace-events-page.html"),
      "https://www.owllisteningroom.com/shows",
    );
    assert.equal(list[0].url, "https://www.owllisteningroom.com/shows?format=json");
    assert.equal(list[0].confidence, 0.9);
  });

  test("ICS link/webcal on the venue's own domain and Google Calendar embeds; ticketing and other domains excluded", () => {
    const endpoints = discoverStructuredEndpoints(
      fixture("gcal-embed-page.html"),
      "https://velvetroomlouisville.com/calendar",
    );
    assert.deepEqual(
      endpoints.map((e) => [e.kind, e.url, e.sameSite, e.trustedCalendarHost]),
      [
        ["ical", "https://velvetroomlouisville.com/calendar/velvet-room.ics", true, false],
        ["ical", "https://calendar.google.com/calendar/ical/velvetroomlive%40gmail.com/public/basic.ics", false, true],
      ],
    );
  });

  test("plain page has none", () => {
    assert.deepEqual(
      discoverStructuredEndpoints(fixture("plain-no-structured.html"), "https://cornerpub.com/events"),
      [],
    );
  });

  test("googleCalendarIcsUrl", () => {
    assert.equal(
      googleCalendarIcsUrl(
        "https://calendar.google.com/calendar/embed?src=abc123%40group.calendar.google.com&ctz=America%2FChicago",
      ),
      "https://calendar.google.com/calendar/ical/abc123%40group.calendar.google.com/public/basic.ics",
    );
    const cid = Buffer.from("venue@gmail.com").toString("base64");
    assert.equal(
      googleCalendarIcsUrl(`https://calendar.google.com/calendar/u/0?cid=${cid}`),
      "https://calendar.google.com/calendar/ical/venue%40gmail.com/public/basic.ics",
    );
    assert.equal(googleCalendarIcsUrl("https://calendar.google.com/calendar/embed"), null);
    assert.equal(googleCalendarIcsUrl("https://example.com/embed?src=a@b.com"), null);
  });
});
