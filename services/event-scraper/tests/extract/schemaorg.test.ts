import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { extractJsonLd, jsonLdExtractor, parseJsonLenient } from "../../src/extract/jsonld.js";
import { extractMicrodata, microdataExtractor } from "../../src/extract/microdata.js";
import { byTitle, fixturePage, makeCtx, makePage } from "./helpers.js";

describe("JSON-LD extractor", () => {
  test("Yoast @graph: picks only events, decodes entities, keeps offsets as instants", () => {
    const url = "https://www.redlinetavern.com/shows/";
    const page = fixturePage("jsonld-graph-yoast.html", url);
    const ctx = makeCtx(url);
    assert.equal(jsonLdExtractor.canHandle(page, ctx), true);
    const events = extractJsonLd(page, ctx);
    assert.deepEqual(
      events.map((e) => e.title),
      ["Lucy Dacus & Friends", "Don’t Stop: A Fleetwood Mac Tribute", "Sunday Jazz Brunch"],
    );

    const lucy = byTitle(events, "Lucy Dacus & Friends");
    assert.equal(lucy.extractor, "jsonld");
    assert.equal(lucy.start, "2026-11-07T20:00");
    assert.equal(lucy.startInstant, "2026-11-08T02:00:00.000Z");
    assert.equal(lucy.end, "2026-11-07T23:00");
    assert.equal(lucy.doors, "2026-11-07T19:00");
    assert.equal(lucy.description, "An evening with Lucy Dacus. All ages.\nDoors at 7.");
    assert.equal(lucy.imageUrl, "https://www.redlinetavern.com/wp-content/uploads/2026/09/lucy.jpg");
    assert.equal(lucy.eventUrl, "https://www.redlinetavern.com/event/lucy-dacus-friends/");
    // Ticket links are recorded as strings only.
    assert.equal(lucy.ticketUrl, "https://www.ticketmaster.com/event/05006123ABCD");
    assert.deepEqual(lucy.performers, ["Lucy Dacus", "Jay Som"]);
    assert.deepEqual(lucy.prices, [{ kind: "ticket", minCents: 2500, maxCents: 3000, currency: "USD", text: null }]);
    assert.equal(lucy.isFree, false);
    assert.equal(lucy.status, "scheduled");
    assert.equal(lucy.category, "music");
    assert.equal(lucy.sourceEventId, "https://www.redlinetavern.com/event/lucy-dacus-friends/#event");
    assert.deepEqual(lucy.location, {
      name: "The Redline Tavern",
      address: "1043 Virginia Ave, Milwaukee, WI, 53204, US",
      lat: 43.0167,
      lng: -87.9331,
      url: null,
    });

    const tribute = byTitle(events, "Don’t Stop: A Fleetwood Mac Tribute");
    assert.equal(tribute.status, "canceled");
    assert.equal(tribute.ticketUrl, null, "offer url equal to the event page is not a ticket link");
    assert.deepEqual(
      tribute.prices.map((p) => [p.kind, p.minCents, p.currency]),
      [
        ["advance", 1500, "USD"],
        ["door", 2000, "USD"],
      ],
    );
    assert.equal(tribute.category, "music");

    const brunch = byTitle(events, "Sunday Jazz Brunch");
    assert.equal(brunch.start, "2026-11-15T11:00");
    assert.equal(brunch.startInstant, null, "local time without offset stays local");
    assert.equal(brunch.isFree, true);
    assert.equal(brunch.category, "music");
  });

  test("numeric-offset times keep the wall clock the site wrote; the instant is kept separately", () => {
    const url = "https://www.redlinetavern.com/shows/";
    const events = extractJsonLd(
      fixturePage("jsonld-graph-yoast.html", url),
      makeCtx(url, { timezone: "America/New_York" }),
    );
    const lucy = byTitle(events, "Lucy Dacus & Friends");
    // "20:00-06:00" for a venue configured in New York: the extractor keeps the typed 20:00 and the instant, so
    // validation can see the disagreement (instant_local_mismatch) instead of silently shifting the show to 21:00.
    assert.equal(lucy.start, "2026-11-07T20:00");
    assert.equal(lucy.startInstant, "2026-11-08T02:00:00.000Z");
    assert.equal(byTitle(events, "Sunday Jazz Brunch").start, "2026-11-15T11:00");
  });

  test("ItemList + duplicate blocks + commented, malformed JSON", () => {
    const url = "https://www.cafelumiere.com/calendar";
    const events = extractJsonLd(fixturePage("jsonld-itemlist-messy.html", url), makeCtx(url));
    assert.equal(events.length, 4, events.map((e) => e.title).join(" | "));

    const lfdi = byTitle(events, "Les Filles de Illighadad");
    assert.equal(lfdi.eventUrl, "https://www.cafelumiere.com/events/les-filles-de-illighadad");
    assert.equal(lfdi.start, "2026-11-06T20:30");
    assert.equal(lfdi.doors, "19:30");
    assert.equal(lfdi.status, "sold_out");
    assert.deepEqual(lfdi.prices, [{ kind: "ticket", minCents: 1800, maxCents: 1800, currency: "USD", text: null }]);
    // Filled from the duplicate block.
    assert.equal(lfdi.imageUrl, "https://www.cafelumiere.com/img/lfdi.jpg");
    assert.deepEqual(lfdi.performers, ["Les Filles de Illighadad"]);
    assert.equal(lfdi.location?.address, "2201 N Lincoln Ave, Chicago, IL 60614");

    const standup = byTitle(events, "Tuesday Stand-Up Showcase");
    assert.equal(standup.category, "comedy");
    assert.equal(standup.end, "21:00");
    assert.equal(standup.isFree, true);
    assert.deepEqual(standup.prices, []);

    const market = byTitle(events, "Holiday Market");
    assert.equal(market.start, "2026-12-05");
    assert.equal(market.end, "2026-12-06");

    const openMic = byTitle(events, "Open Mic Night");
    assert.equal(openMic.description, "Sign-up at 6:30.\nBring your own instrument!");
    assert.equal(openMic.status, "rescheduled");
    assert.equal(openMic.startInstant, "2026-11-12T01:00:00.000Z");
    assert.equal(openMic.category, "open_mic");
  });

  test("top-level arrays, Place.event, EventSeries.subEvent, online-only dropped, schema.org URL types", () => {
    const url = "https://northsideplayhouse.org/season/";
    const events = extractJsonLd(fixturePage("jsonld-array-nested.html", url), makeCtx(url));
    assert.deepEqual(events.map((e) => e.title).sort(), [
      "Holiday Choir Concert",
      "Late Night Jazz: The Quartet",
      "Late Night Jazz: Trio Nuevo",
      "Our Town",
      "Winter Dances",
    ]);
    const ourTown = byTitle(events, "Our Town");
    assert.equal(ourTown.category, "theater");
    assert.equal(ourTown.status, "postponed");
    assert.equal(ourTown.prices[0].minCents, 3250);
    const dances = byTitle(events, "Winter Dances");
    assert.equal(dances.category, "dance");
    assert.equal(dances.status, "sold_out");
    const trio = byTitle(events, "Late Night Jazz: Trio Nuevo");
    assert.equal(trio.sourceEventId, "lnj-2026-11-13");
    assert.equal(trio.end, "2026-11-14T01:00", "overnight end keeps its own date");
    const choir = byTitle(events, "Holiday Choir Concert");
    assert.equal(choir.start, "2026-12-12T10:00", "Z instant shown in venue wall-clock");
    assert.equal(choir.category, "music");
    assert.equal(choir.location?.name, "Northside Playhouse Main Stage");
  });

  test("parseJsonLenient repairs common CMS breakage", () => {
    assert.deepEqual(parseJsonLenient('{"a": [1, 2,],}'), { a: [1, 2] });
    assert.deepEqual(parseJsonLenient('<!-- {"a": "line\nbreak"} -->'), { a: "line\nbreak" });
    assert.deepEqual(parseJsonLenient('{"a":1}\n{"b":2}'), [{ a: 1 }, { b: 2 }]);
    assert.deepEqual(parseJsonLenient('//<![CDATA[\n{"a":"it\\\'s"}\n//]]>'), { a: "it's" });
    assert.equal(parseJsonLenient("{ nope"), undefined);
  });

  test("pages without event JSON-LD yield nothing", () => {
    const html =
      '<html><head><script type="application/ld+json">{"@type":"Organization","name":"X"}</script></head></html>';
    const page = makePage(html, "https://x.com/");
    assert.deepEqual(extractJsonLd(page, makeCtx(page.url)), []);
  });
});

describe("microdata extractor", () => {
  test("nested Place/Offer/Person items, attribute values, yearless human dates", () => {
    const url = "https://www.bluedoorbar.com/events";
    const page = fixturePage("microdata-calendar.html", url);
    const ctx = makeCtx(url);
    assert.equal(microdataExtractor.canHandle(page, ctx), true);
    const events = extractMicrodata(page, ctx);
    assert.equal(events.length, 3);

    const ktt = byTitle(events, "Kiss the Tiger w/ Bad Bad Hats");
    assert.equal(ktt.extractor, "microdata");
    assert.equal(ktt.start, "2026-11-06T21:00");
    assert.equal(ktt.doors, "20:00");
    assert.equal(ktt.eventUrl, "https://www.bluedoorbar.com/event/kiss-the-tiger");
    assert.equal(ktt.imageUrl, "https://cdn.bluedoorbar.com/img/ktt.jpg");
    assert.deepEqual(ktt.performers, ["Kiss the Tiger", "Bad Bad Hats"]);
    assert.equal(ktt.location?.name, "The Blue Door");
    assert.equal(ktt.location?.address, "1811 Selby Ave, St. Paul, MN");
    assert.deepEqual(ktt.prices, [{ kind: "ticket", minCents: 1200, maxCents: 1200, currency: "USD", text: null }]);
    assert.equal(ktt.ticketUrl, "https://www.etix.com/ticket/p/12345678/kiss-the-tiger");
    assert.equal(ktt.category, "music");

    const swing = byTitle(events, "Swing Dance Social");
    assert.equal(swing.start, "--11-14T19:30", "year left for validation to infer");
    assert.equal(swing.rawDateText, "Saturday, November 14 at 7:30 PM");
    assert.equal(swing.description, "Free lesson at 7:30, & live band at 8:30.");

    const salsa = byTitle(events, "Salsa Night");
    assert.equal(salsa.status, "canceled");
    assert.equal(salsa.category, "dance");
    assert.equal(salsa.start, "2026-11-21T20:00");
  });
});
