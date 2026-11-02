import assert from "node:assert/strict";
import { describe, test } from "node:test";
import {
  instantToLocal,
  localToInstant,
  parseClockOrDate,
  parseDateValue,
  parseHumanDate,
  parseTimeOfDay,
  toIanaTimeZone,
} from "../../src/extract/time.js";
import {
  applyTitleStatus,
  blankEvent,
  categoryHint,
  cleanMultiline,
  cleanText,
  decodeEntities,
  dedupeEvents,
  mapStatus,
  parsePriceText,
  resolveUrl,
} from "../../src/extract/util.js";

const CHI = "America/Chicago";

describe("time helpers", () => {
  test("parseDateValue: local, offset, Z, basic format, fractional seconds", () => {
    assert.deepEqual(parseDateValue("2026-11-07", CHI), { local: "2026-11-07", instant: null, dateOnly: true });
    assert.deepEqual(parseDateValue("2026-11-07 20:00:00", CHI), {
      local: "2026-11-07T20:00",
      instant: null,
      dateOnly: false,
    });
    assert.deepEqual(parseDateValue("2026-11-07T20:00:00-0500", CHI), {
      local: "2026-11-07T19:00",
      instant: "2026-11-08T01:00:00.000Z",
      dateOnly: false,
      wallClock: "2026-11-07T20:00",
      zone: "-0500",
    });
    assert.equal(parseDateValue("2026-11-08T02:00:00.000Z", CHI)?.local, "2026-11-07T20:00");
    assert.equal(parseDateValue("20261108T020000Z", CHI)?.instant, "2026-11-08T02:00:00.000Z");
    assert.equal(parseDateValue("2026-11-07T24:00", CHI)?.local, "2026-11-08T00:00");
    assert.equal(parseDateValue("2026-13-07", CHI), null);
    assert.equal(parseDateValue("", CHI), null);
    assert.equal(parseDateValue("TBA", CHI), null);
  });

  test("parseHumanDate: month names, ordinals, yearless, numeric US dates", () => {
    assert.equal(parseHumanDate("Friday, November 7th, 2026 @ 8:00 PM")?.local, "2026-11-07T20:00");
    assert.equal(parseHumanDate("Sat Nov 14 - 9pm")?.local, "--11-14T21:00");
    assert.equal(parseHumanDate("14 November 2026")?.local, "2026-11-14");
    assert.equal(parseHumanDate("11/21 7:30pm")?.local, "--11-21T19:30");
    assert.equal(parseHumanDate("12/31/26 noon")?.local, "2026-12-31T12:00");
    assert.equal(parseHumanDate("Doors open soon"), null);
  });

  test("parseTimeOfDay / parseClockOrDate", () => {
    assert.equal(parseTimeOfDay("8pm"), "20:00");
    assert.equal(parseTimeOfDay("12:30 a.m."), "00:30");
    assert.equal(parseTimeOfDay("12 PM"), "12:00");
    assert.equal(parseTimeOfDay("19:45"), "19:45");
    assert.equal(parseTimeOfDay("8"), null);
    assert.equal(parseClockOrDate("19:00:00", CHI), "19:00");
    assert.equal(parseClockOrDate("7:30 PM", CHI), "19:30");
    assert.equal(parseClockOrDate("2026-11-07T19:00:00-06:00", CHI), "2026-11-07T19:00");
  });

  test("localToInstant across DST transitions", () => {
    assert.equal(localToInstant("2026-11-07T20:00", CHI)?.toISOString(), "2026-11-08T02:00:00.000Z");
    assert.equal(localToInstant("2026-07-04T20:00", CHI)?.toISOString(), "2026-07-05T01:00:00.000Z");
    // Ambiguous 01:30 on the fall-back night resolves to the first (CDT) occurrence.
    assert.equal(localToInstant("2026-11-01T01:30", CHI)?.toISOString(), "2026-11-01T06:30:00.000Z");
    // Nonexistent 02:30 on spring-forward night still yields a valid instant.
    const gap = localToInstant("2027-03-14T02:30", CHI);
    assert.ok(gap);
    assert.ok(["2027-03-14T08:30:00.000Z", "2027-03-14T07:30:00.000Z"].includes(gap.toISOString()));
    assert.equal(instantToLocal(new Date("2026-11-08T02:00:00Z"), "Europe/London"), "2026-11-08T02:00");
  });

  test("toIanaTimeZone", () => {
    assert.equal(toIanaTimeZone("America/Chicago"), "America/Chicago");
    assert.equal(toIanaTimeZone("/mozilla.org/20050126_1/America/New_York"), "America/New_York");
    assert.equal(toIanaTimeZone('"Pacific Standard Time"'), "America/Los_Angeles");
    assert.equal(toIanaTimeZone("Not/AZone"), null);
    assert.equal(toIanaTimeZone(null), null);
  });
});

describe("text and price helpers", () => {
  test("entities, double-encoding, tags, invisible whitespace", () => {
    assert.equal(decodeEntities("Rock &amp;amp; Roll"), "Rock & Roll");
    assert.equal(cleanText("Don&#8217;t&nbsp;Stop <em>Live</em>​"), "Don’t Stop Live");
    assert.equal(cleanText("AT&T Presents"), "AT&T Presents");
    assert.equal(cleanText("   "), null);
    assert.equal(cleanMultiline("<p>One</p><p>Two<br>Three</p><script>x()</script>"), "One\nTwo\nThree");
  });

  test("resolveUrl", () => {
    assert.equal(resolveUrl("/e/1?a=1&amp;b=2", "https://v.com/x/"), "https://v.com/e/1?a=1&b=2");
    assert.equal(resolveUrl("//cdn.v.com/i.jpg", "https://v.com/"), "https://cdn.v.com/i.jpg");
    assert.equal(resolveUrl("mailto:a@b.com", "https://v.com/"), null);
    assert.equal(resolveUrl("javascript:void(0)", "https://v.com/"), null);
    assert.equal(resolveUrl("#top", "https://v.com/"), null);
  });

  test("parsePriceText", () => {
    assert.deepEqual(parsePriceText("$15 adv / $20 dos"), {
      prices: [
        { kind: "advance", minCents: 1500, maxCents: 1500, currency: "USD", text: "$15 adv / $20 dos" },
        { kind: "door", minCents: 2000, maxCents: 2000, currency: "USD", text: "$15 adv / $20 dos" },
      ],
      isFree: false,
    });
    assert.deepEqual(
      parsePriceText("$10-$25").prices.map((p) => [p.minCents, p.maxCents]),
      [[1000, 2500]],
    );
    assert.equal(parsePriceText("$12.50").prices[0].minCents, 1250);
    assert.equal(parsePriceText("15").prices[0].minCents, 1500);
    assert.deepEqual(parsePriceText("FREE w/ RSVP"), { prices: [], isFree: true });
    assert.deepEqual(parsePriceText("No cover"), { prices: [], isFree: true });
    assert.deepEqual(parsePriceText("No cover before 10"), { prices: [], isFree: null });
    assert.deepEqual(parsePriceText("21+ show, doors at 8"), { prices: [], isFree: null });
    assert.deepEqual(parsePriceText(null), { prices: [], isFree: null });
  });

  test("mapStatus and applyTitleStatus", () => {
    assert.equal(mapStatus("https://schema.org/EventCancelled"), "canceled");
    assert.equal(mapStatus("CANCELLED"), "canceled");
    assert.equal(mapStatus("EventMovedOnline"), "scheduled");
    assert.equal(mapStatus("http://schema.org/EventPostponed"), "postponed");
    assert.equal(mapStatus("whatever"), null);
    const ev = { ...blankEvent("x"), title: "[SOLD OUT] The Band" };
    applyTitleStatus(ev);
    assert.deepEqual([ev.title, ev.status], ["The Band", "sold_out"]);
    const ev2 = { ...blankEvent("x"), title: "Postponed - Jazz Night", status: "canceled" as const };
    applyTitleStatus(ev2);
    assert.deepEqual([ev2.title, ev2.status], ["Jazz Night", "canceled"], "structured status wins");
    const ev3 = { ...blankEvent("x"), title: "Sold Out" };
    applyTitleStatus(ev3);
    assert.equal(ev3.title, "Sold Out", "never empties a title");
  });

  test("categoryHint uses explicit types and labels only", () => {
    assert.equal(categoryHint(["ComedyEvent"], ["music"], "x"), "comedy");
    assert.equal(categoryHint(["event"], ["Concerts"], "x"), "music");
    assert.equal(categoryHint(["event"], [], "Tuesday Open-Mic"), "open_mic");
    assert.equal(categoryHint(["event"], ["Stand-Up"], null), "comedy");
    assert.equal(categoryHint(["event"], ["Trivia"], "Trivia Night"), null);
  });

  test("dedupeEvents merges by source id, url+time or title+time", () => {
    const a = { ...blankEvent("jsonld"), title: "The Band", start: "2026-11-07T20:00", eventUrl: "https://v.com/e/1/" };
    const b = {
      ...blankEvent("microdata"),
      title: "THE BAND!",
      start: "2026-11-07T20:00",
      imageUrl: "https://v.com/i.jpg",
    };
    const c = { ...blankEvent("jsonld"), title: "The Band", start: "2026-11-08T20:00" };
    const out = dedupeEvents([a, b, c], true);
    assert.equal(out.length, 2);
    assert.equal(out[0].imageUrl, "https://v.com/i.jpg");
    assert.equal(out[0].extractor, "jsonld");
  });
});
