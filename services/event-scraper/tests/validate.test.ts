import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, test } from "node:test";
import { blankEvent } from "../src/extract/util.js";
import type { ExtractedEvent, ValidatedEvent } from "../src/types.js";
import { classifyEvent } from "../src/validate/classify.js";
import { parsePriceText } from "../src/validate/price.js";
import { buildQuoteIndex, verifyQuotes } from "../src/validate/quotes.js";
import { type ValidateContext, validateEvent, validateEvents } from "../src/validate/validate.js";

const NOW = new Date("2026-11-02T15:00:00Z"); // Monday Nov 2 2026, 9am in Chicago
const SOURCE = { id: "src-1", venueId: "venue-1", url: "https://example-room.test/shows", timezone: "America/Chicago" };
const CTX: ValidateContext = {
  source: SOURCE,
  venue: { id: "venue-1", name: "The Example Room" },
  timezone: "America/Chicago",
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

function ok(e: ExtractedEvent, ctx: ValidateContext = CTX): ValidatedEvent {
  const outcome = validateEvent(e, ctx);
  if (!outcome.ok) assert.fail(`expected valid, got ${outcome.reasons.join(",")}`);
  return outcome.event;
}

function rejected(e: ExtractedEvent, ctx: ValidateContext = CTX): string[] {
  const outcome = validateEvent(e, ctx);
  if (outcome.ok) assert.fail(`expected rejection, got ${JSON.stringify(outcome.event)}`);
  return outcome.reasons;
}

describe("validateEvent: required fields and dates", () => {
  test("basic event gets local + UTC start in the venue zone", () => {
    const e = ok(ev({}));
    assert.equal(e.startLocal, "2026-11-07T20:00");
    assert.equal(e.startUtc, "2026-11-08T02:00:00.000Z");
    assert.equal(e.datePrecision, "instant");
    assert.equal(e.timezone, "America/Chicago");
    assert.equal(e.category, "music");
    assert.equal(e.identityKey, "venue-1|2026-11-07|20:00|example band");
  });

  test("missing title / start are rejected", () => {
    assert.deepEqual(rejected(ev({ title: "  " })), ["missing_title"]);
    assert.deepEqual(rejected(ev({ title: null })), ["missing_title"]);
    assert.deepEqual(rejected(ev({ start: null })), ["missing_start"]);
    assert.deepEqual(rejected(ev({ start: "sometime soon" })), ["invalid_start"]);
    assert.deepEqual(rejected(ev({ start: "20:00" })), ["start_without_date"]);
  });

  test("date-only events have no UTC instant", () => {
    const e = ok(ev({ start: "2026-11-07" }));
    assert.equal(e.startLocal, "2026-11-07");
    assert.equal(e.startUtc, null);
    assert.equal(e.datePrecision, "date");
  });

  test("past events dropped except within one day; > 13 months out dropped", () => {
    assert.deepEqual(rejected(ev({ start: "2026-10-31T20:00" })), ["past_event"]);
    assert.equal(ok(ev({ start: "2026-11-01T20:00" })).startLocal, "2026-11-01T20:00");
    assert.deepEqual(rejected(ev({ start: "2027-12-03T20:00" })), ["too_far_future"]);
    assert.equal(ok(ev({ start: "2027-12-02T20:00" })).startLocal, "2027-12-02T20:00");
  });

  test("yearless dates get an inferred year", () => {
    const nov = ok(ev({ start: "--11-07T20:00", rawDateText: "Sat Nov 7" }));
    assert.equal(nov.startLocal, "2026-11-07T20:00");
    assert.ok(nov.warnings.includes("year_inferred"));
    const jan = ok(ev({ start: "--01-09T21:00", rawDateText: "Sat, Jan 9" }));
    assert.equal(jan.startLocal, "2027-01-09T21:00");
    assert.equal(jan.startUtc, "2027-01-10T03:00:00.000Z");
  });

  test("a yearless date that only fits a year out needs a matching weekday", () => {
    // "Oct 30" seen on Nov 2 is almost certainly a stale listing.
    assert.deepEqual(rejected(ev({ start: "--10-30T20:00" })), ["year_ambiguous"]);
    // Oct 30 2027 is a Saturday: a printed "Sat" confirms it.
    assert.equal(ok(ev({ start: "--10-30T20:00", rawDateText: "Sat Oct 30" })).startLocal, "2027-10-30T20:00");
  });

  test("startInstant with an offset is converted to the venue's local time", () => {
    const e = ok(ev({ start: null, startInstant: "2026-11-07T21:00:00-05:00" }));
    assert.equal(e.startLocal, "2026-11-07T20:00");
    assert.equal(e.startUtc, "2026-11-08T02:00:00.000Z");
  });

  test("an instant that contradicts the local start defers to the local value", () => {
    // Common CMS bug: local time serialized with +00:00.
    const e = ok(ev({ start: "2026-11-07T20:00", startInstant: "2026-11-07T20:00:00+00:00" }));
    assert.equal(e.startUtc, "2026-11-08T02:00:00.000Z");
    assert.ok(e.warnings.includes("instant_local_mismatch"));
  });

  test("event-level timezone overrides the source zone", () => {
    const e = ok(ev({ start: "2026-11-07T20:00", timezone: "America/Los_Angeles" }));
    assert.equal(e.timezone, "America/Los_Angeles");
    assert.equal(e.startUtc, "2026-11-08T04:00:00.000Z");
    assert.deepEqual(rejected(ev({}), { ...CTX, timezone: "Mars/Olympus" }), ["invalid_timezone"]);
  });

  test("DST: show in the spring-forward gap and an overnight show across fall-back", () => {
    const ctx = { ...CTX, now: new Date("2026-03-01T15:00:00Z"), timezone: "America/New_York" };
    const gap = ok(ev({ start: "2026-03-08T02:30" }), ctx);
    assert.equal(gap.startUtc, "2026-03-08T07:30:00.000Z");
    assert.ok(gap.warnings.includes("start_in_dst_gap"));

    const halloween = { ...CTX, now: new Date("2026-10-25T15:00:00Z"), timezone: "America/New_York" };
    const overnight = ok(ev({ start: "2026-10-31T22:00", end: "03:00" }), halloween);
    assert.equal(overnight.endLocal, "2026-11-01T03:00");
    assert.equal(overnight.startUtc, "2026-11-01T02:00:00.000Z"); // EDT
    assert.equal(overnight.endUtc, "2026-11-01T08:00:00.000Z"); // EST
    assert.ok(overnight.warnings.includes("end_rolled_over"));
  });
});

describe("validateEvent: end, doors, prices, status", () => {
  test("overnight end time rolls to the next day", () => {
    const e = ok(ev({ start: "2026-11-07T22:00", end: "02:00" }));
    assert.equal(e.endLocal, "2026-11-08T02:00");
    assert.equal(e.endUtc, "2026-11-08T08:00:00.000Z");
  });

  test("same-evening end stays on the start date; bogus end is dropped", () => {
    assert.equal(ok(ev({ start: "2026-11-07T20:00", end: "23:00" })).endLocal, "2026-11-07T23:00");
    const bad = ok(ev({ start: "2026-11-07T20:00", end: "2026-11-05T23:00" }));
    assert.equal(bad.endLocal, null);
    assert.ok(bad.warnings.includes("end_before_start"));
  });

  test("doors before show; swapped doors/show are fixed; doors before a past-midnight show", () => {
    assert.equal(ok(ev({ start: "2026-11-07T20:00", doors: "19:00" })).doorsLocal, "2026-11-07T19:00");
    const swapped = ok(ev({ start: "2026-11-07T19:00", doors: "20:00" }));
    assert.equal(swapped.startLocal, "2026-11-07T20:00");
    assert.equal(swapped.doorsLocal, "2026-11-07T19:00");
    assert.ok(swapped.warnings.includes("doors_show_swapped"));
    const lateShow = ok(ev({ start: "2026-11-08T00:30", doors: "23:30" }));
    assert.equal(lateShow.doorsLocal, "2026-11-07T23:30");
  });

  test("price text to integer cents; free and sold out", () => {
    const e = ok(
      ev({ prices: [{ kind: "ticket", minCents: null, maxCents: null, currency: null, text: "$15 adv / $20 dos" }] }),
    );
    assert.deepEqual(
      e.prices.map((p) => [p.kind, p.minCents, p.maxCents, p.currency]),
      [
        ["advance", 1500, 1500, "USD"],
        ["door", 2000, 2000, "USD"],
      ],
    );
    assert.equal(e.isFree, false);
    const free = ok(ev({ title: "Free Show: Local Heroes" }));
    assert.equal(free.isFree, true);
    const soldOut = ok(ev({ title: "SOLD OUT: The Example Band" }));
    assert.equal(soldOut.title, "The Example Band");
    assert.equal(soldOut.status, "sold_out");
    const canceled = ok(ev({ title: "The Example Band (Cancelled)" }));
    assert.equal(canceled.title, "The Example Band");
    assert.equal(canceled.status, "canceled");
    // Status prefixes do not change identity.
    assert.equal(soldOut.identityKey, ok(ev({})).identityKey);
  });

  test("ticketing links are kept as ticketUrl strings only; relative URLs resolved", () => {
    const e = ok(ev({ eventUrl: "https://www.ticketmaster.com/event/123", imageUrl: "/img/band.jpg" }));
    assert.equal(e.eventUrl, null);
    assert.equal(e.ticketUrl, "https://www.ticketmaster.com/event/123");
    assert.equal(e.imageUrl, "https://example-room.test/img/band.jpg");
    assert.equal(ok(ev({ eventUrl: "javascript:void(0)" })).eventUrl, null);
  });

  test("performers deduped, venue name removed, entities decoded", () => {
    const e = ok(ev({ performers: ["Band A", "band a", "The Example Room", "Beyonc&eacute; Tribute"] }));
    assert.deepEqual(e.performers, ["Band A", "Beyoncé Tribute"]);
  });

  test("sourceEventId and event URL identities include the date and start time", () => {
    const a = ok(ev({ sourceEventId: "wp-991" }));
    assert.equal(a.identityKey, "venue-1|2026-11-07|id:wp-991|t:20:00");
    const b = ok(ev({ eventUrl: "/events/example-band?utm_source=x" }));
    assert.equal(b.identityKey, "venue-1|2026-11-07|url:https://example-room.test/events/example-band|t:20:00");
    // The calendar page itself is not an event-specific URL.
    const c = ok(ev({ eventUrl: "https://example-room.test/shows#nov7" }));
    assert.equal(c.identityKey, "venue-1|2026-11-07|20:00|example band");
  });
});

describe("classification", () => {
  test("categories", () => {
    assert.equal(classifyEvent({ title: "The Mountain Goats w/ Lydia Loveless" }).category, "music");
    assert.equal(classifyEvent({ title: "Stand-Up Saturday ft. Jane Doe" }).category, "comedy");
    assert.equal(classifyEvent({ title: "Comedy Open Mic" }).category, "open_mic");
    assert.equal(classifyEvent({ title: "Songwriter Open Mic" }).category, "open_mic");
    assert.equal(classifyEvent({ title: "Little Shop of Horrors: The Musical" }).category, "theater");
    assert.equal(classifyEvent({ title: "Tango Milonga" }).category, "dance");
    assert.equal(classifyEvent({ title: "John Mulaney: From Scratch Tour", hint: "comedy" }).category, "comedy");
    assert.equal(classifyEvent({ title: "Mystery Guest", description: "An evening of improv." }).category, "comedy");
  });

  test("non-events are 'other'", () => {
    for (const title of [
      "Trivia Night",
      "Sunday Brunch",
      "Karaoke Tuesdays",
      "Private Event",
      "CLOSED for Thanksgiving",
      "Monday Night Football Watch Party",
      "Bingo with Betty",
      "Happy Hour",
    ]) {
      assert.equal(classifyEvent({ title }).category, "other", title);
    }
    assert.equal(classifyEvent({ title: "Karaoke Open Mic" }).category, "open_mic");
    assert.equal(classifyEvent({ title: "Jazz Brunch with the Hot Club" }).category, "music");
    assert.equal(classifyEvent({ title: "Something", hint: "other" }).category, "other");
  });

  test("isMusic flags live music inside other categories", () => {
    assert.equal(classifyEvent({ title: "Salsa Night with live band" }).isMusic, true);
    assert.equal(classifyEvent({ title: "Stand-up Showcase" }).isMusic, false);
  });

  test("validation drops 'other'", () => {
    assert.deepEqual(rejected(ev({ title: "Trivia Night" })), ["category_other:non_event:trivia"]);
  });
});

describe("price parsing", () => {
  test("common shapes", () => {
    const range = parsePriceText("$10-$15");
    assert.deepEqual(
      range.prices.map((p) => [p.minCents, p.maxCents]),
      [[1000, 1500]],
    );
    assert.deepEqual(
      parsePriceText("$12.50 advance").prices.map((p) => [p.kind, p.minCents]),
      [["advance", 1250]],
    );
    assert.equal(parsePriceText("Free w/ RSVP").isFree, true);
    assert.equal(parsePriceText("No cover").isFree, true);
    assert.equal(parsePriceText("Free parking, $20 tickets").isFree, false);
    assert.equal(parsePriceText("SOLD OUT").soldOut, true);
    assert.deepEqual(
      parsePriceText("€20").prices.map((p) => p.currency),
      ["EUR"],
    );
    assert.deepEqual(
      parsePriceText("Tickets 25 at the door").prices.map((p) => [p.kind, p.minCents]),
      [["door", 2500]],
    );
    assert.deepEqual(parsePriceText("Show at 8pm 2026").prices, []);
  });
});

describe("evidence quotes", () => {
  const html = readFileSync(new URL("./fixtures/llm/venue-calendar.html", import.meta.url), "utf8");
  const index = buildQuoteIndex(html, "text/html");

  test("whitespace and entity insensitive matching", () => {
    const check = verifyQuotes(
      [
        "The Example Band w/ Openers & Friends",
        "Doors 7:00pm / Show 8:00pm",
        "sat, nov 7 · 10PM - 2am",
        "Free — no cover",
      ],
      index,
    );
    assert.deepEqual(check.missing, []);
    assert.equal(check.verified.length, 4);
  });

  test("hallucinated quotes, script contents and too-short quotes are rejected", () => {
    const check = verifyQuotes(["Taylor Swift Secret Show", "Nov 20", "8p"], index);
    assert.deepEqual(check.missing, ["Taylor Swift Secret Show", "Nov 20"]);
    assert.deepEqual(check.tooShort, ["8p"]);
  });

  test("LLM events need verified evidence; structured extractors do not", () => {
    const ctx = { ...CTX, pageText: html, pageContentType: "text/html" };
    const fake = ev({ extractor: "llm", title: "Taylor Swift Secret Show", evidence: ["Taylor Swift Secret Show"] });
    assert.deepEqual(rejected(fake, ctx), ["evidence_not_found:1"]);
    const partial = ev({ extractor: "llm", evidence: ["Fri, Nov 6", "Headliner: The Example Band at 8"] });
    assert.deepEqual(rejected(partial, ctx), ["evidence_not_found:1"]);
    assert.deepEqual(rejected(ev({ extractor: "llm", evidence: [] }), ctx), ["evidence_missing"]);
    assert.deepEqual(rejected(ev({ extractor: "llm", evidence: ["Fri, Nov 6"] }), CTX), ["evidence_unverifiable"]);
    assert.ok(ok(ev({ extractor: "jsonld", evidence: ["anything"] }), ctx));
  });

  test("validateEvents dedupes identities and shares one quote index", () => {
    const ctx = { ...CTX, pageText: html, pageContentType: "text/html" };
    const result = validateEvents(
      [
        ev({
          extractor: "llm",
          title: "Open Mic Night",
          start: "--11-10T19:00",
          evidence: ["Open Mic Night", "Open Mic Night Tue, Nov 10"],
        }),
        ev({
          extractor: "llm",
          title: "Open Mic Night",
          start: "--11-10T19:00",
          evidence: ["Open Mic Night Tue, Nov 10 · 7pm"],
        }),
        ev({ extractor: "llm", title: "Ghost", start: "--11-12T19:00", evidence: ["Ghost show Nov 12"] }),
      ],
      ctx,
    );
    assert.equal(result.valid.length, 1);
    assert.equal(result.valid[0]?.category, "open_mic");
    assert.equal(result.duplicates, 1);
    assert.equal(result.rejected.length, 1);
  });
});

describe("one event shown in two views", () => {
  test("the copy without a time is dropped when a timed copy exists; a different show that day stays", () => {
    const ctx = {
      source: { id: "s", venueId: "v", url: "https://room.test/shows", timezone: "America/New_York" },
      venue: { id: "v", name: "The Room" },
      timezone: "America/New_York",
      now: new Date("2026-11-02T15:00:00Z"),
    };
    const base = {
      ...blankEvent("jsonld"),
      performers: ["Someone"],
      category: "music" as const,
    };
    const result = validateEvents(
      [
        { ...base, title: "Big Shrimp", start: "2026-11-07" },
        { ...base, title: "Big Shrimp", start: "2026-11-07T21:00" },
        { ...base, title: "Other Band", start: "2026-11-07" },
      ],
      ctx,
    );
    assert.deepEqual(result.valid.map((event) => [event.title, event.startLocal]).sort(), [
      ["Big Shrimp", "2026-11-07T21:00"],
      ["Other Band", "2026-11-07"],
    ]);
    assert.equal(result.duplicates, 1);
  });
});
