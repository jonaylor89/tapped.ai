import assert from "node:assert/strict";
import { describe, test } from "node:test";
import {
  expandRRule,
  extractIcal,
  icalExtractor,
  parseDuration,
  parseIcs,
  parseRRule,
  unescapeText,
} from "../../src/extract/ical.js";
import { byTitle, fixturePage, makeCtx, makePage } from "./helpers.js";

const VENUE_ICS_URL = "https://www.redlinetavern.com/?post_type=tribe_events&ical=1";
const GCAL_URL = "https://calendar.google.com/calendar/ical/velvetroomlive%40gmail.com/public/basic.ics";

describe("iCal extractor", () => {
  test("venue feed: TZID, folding, escapes, location, prices, categories", () => {
    const page = fixturePage("venue-calendar.ics", VENUE_ICS_URL);
    const ctx = makeCtx(VENUE_ICS_URL);
    assert.equal(icalExtractor.canHandle(page, ctx), true);
    const events = extractIcal(page, ctx);
    assert.equal(events.length, 34, events.map((e) => `${e.title}@${e.start}`).join("\n"));

    const goats = byTitle(events, "The Mountain Goats, with special guest Lydia Loveless");
    assert.equal(goats.extractor, "ical");
    assert.equal(goats.start, "2026-11-07T20:00");
    assert.equal(goats.startInstant, "2026-11-08T02:00:00.000Z");
    assert.equal(goats.end, "2026-11-07T23:00");
    assert.equal(goats.timezone, null);
    assert.equal(
      goats.description,
      "Doors 7pm.\nTickets $25 adv / $30 door.\nAll ages. John Darnielle and company return to the Redline for one night only & it will sell out.",
    );
    assert.deepEqual(goats.location, {
      name: "The Redline Tavern",
      address: "1043 Virginia Ave, Milwaukee, WI 53204",
      lat: 43.0167,
      lng: -87.9331,
      url: null,
    });
    assert.equal(goats.eventUrl, "https://www.redlinetavern.com/event/mountain-goats/");
    assert.deepEqual(
      goats.prices.map((p) => [p.kind, p.minCents, p.currency]),
      [
        ["advance", 2500, "USD"],
        ["door", 3000, "USD"],
      ],
    );
    assert.equal(goats.category, "music");
    assert.equal(goats.sourceEventId, "show-1001@redlinetavern.com");
  });

  test("weekly RRULE: bounded to 180 days, EXDATE removed, RECURRENCE-ID override applied, DST-correct", () => {
    const events = extractIcal(fixturePage("venue-calendar.ics", VENUE_ICS_URL), makeCtx(VENUE_ICS_URL));
    const mics = events.filter((e) => e.sourceEventId?.startsWith("open-mic-weekly@"));
    assert.equal(mics.length, 25);
    assert.equal(mics[0].start, "2026-11-04T19:00");
    assert.equal(mics[0].startInstant, "2026-11-05T01:00:00.000Z");
    assert.equal(mics[0].category, "open_mic");
    assert.ok(!mics.some((e) => e.start?.startsWith("2026-11-25")), "EXDATE skipped");
    const moved = mics.find((e) => e.start?.startsWith("2026-11-11"));
    assert.equal(moved?.title, "Wednesday Open Mic (late start)");
    assert.equal(moved?.start, "2026-11-11T20:00");
    assert.equal(moved?.end, "2026-11-11T23:00");
    assert.equal(moved?.sourceEventId, "open-mic-weekly@redlinetavern.com#20261111T1900");
    const afterDst = mics.find((e) => e.start === "2027-03-17T19:00");
    assert.equal(afterDst?.startInstant, "2027-03-18T00:00:00.000Z", "CDT after the March switch");
    assert.equal(mics[mics.length - 1].start, "2027-04-28T19:00");
    assert.equal(new Set(mics.map((e) => e.sourceEventId)).size, 25, "occurrence ids are unique");
  });

  test("monthly BYDAY=1FR with COUNT, all-day, UTC + DURATION, CANCELLED, Windows TZID, past dropped", () => {
    const events = extractIcal(fixturePage("venue-calendar.ics", VENUE_ICS_URL), makeCtx(VENUE_ICS_URL));
    const funk = events.filter((e) => e.title === "First Friday Funk Night");
    assert.deepEqual(
      funk.map((e) => e.start),
      ["2026-11-06T21:00", "2026-12-04T21:00", "2027-01-01T21:00", "2027-02-05T21:00"],
    );
    assert.equal(funk[0].end, "2026-11-07T01:00");
    assert.equal(funk[0].category, "music");

    const popup = byTitle(events, "Small Business Saturday Vinyl Pop-Up");
    assert.equal(popup.start, "2026-11-28");
    assert.equal(popup.end, null);
    assert.equal(popup.startInstant, null);

    const comedy = byTitle(events, "Comedy Night: Jane Doe");
    assert.equal(comedy.start, "2026-11-20T21:00");
    assert.equal(comedy.end, "2026-11-21T00:00");
    assert.equal(comedy.category, "comedy");

    assert.equal(byTitle(events, "Holiday Bash").status, "canceled");
    const winter = byTitle(events, "Winter Showcase");
    assert.equal(winter.startInstant, "2026-12-13T02:00:00.000Z");
    assert.equal(
      events.find((e) => e.title === "Last Month's Show"),
      undefined,
    );
  });

  test("Google Calendar export: CRLF, X-WR-TIMEZONE floating times, UTC daily COUNT, history dropped, orphan override", () => {
    const page = fixturePage("google-calendar.ics", GCAL_URL, "text/calendar; charset=UTF-8");
    const events = extractIcal(page, makeCtx(GCAL_URL, { timezone: "America/New_York" }));
    assert.equal(events.length, 7, events.map((e) => `${e.title}@${e.start}`).join("\n"));
    assert.equal(
      events.find((e) => e.title === "Old Show From 2019"),
      undefined,
    );

    const residency = events.filter((e) => e.title === "Fall Residency: DJ Kool");
    assert.deepEqual(
      residency.map((e) => e.start),
      ["2026-11-03T22:00", "2026-11-04T22:00", "2026-11-05T22:00", "2026-11-06T22:00", "2026-11-07T22:00"],
    );
    assert.equal(residency[0].startInstant, "2026-11-04T03:00:00.000Z");
    assert.equal(residency[0].end, "2026-11-04T01:00");
    assert.equal(residency[0].description, "Five nights of house & disco.\nNo cover before 11.");
    assert.equal(residency[0].isFree, null, '"No cover before 11" is not a free show');
    assert.equal(residency[0].location?.name, "Velvet Room");
    assert.equal(residency[0].location?.address, "300 W Main St, Louisville, KY 40202, USA");

    const jam = byTitle(events, "Monday Bluegrass Jam");
    assert.equal(jam.start, "2026-11-16T19:00");
    assert.equal(jam.startInstant, "2026-11-17T00:00:00.000Z");

    const moved = byTitle(events, "Saturday Soul Revue (moved)");
    assert.equal(moved.start, "2026-11-21T20:00");
    assert.equal(moved.sourceEventId, "series-orphan@google.com#20261120T2000");
    assert.equal(moved.status, "scheduled");
  });

  test("feed TZID differs from venue zone: instant preserved, local shown in venue time", () => {
    const events = extractIcal(
      fixturePage("venue-calendar.ics", VENUE_ICS_URL),
      makeCtx(VENUE_ICS_URL, { timezone: "America/New_York" }),
    );
    const goats = byTitle(events, "The Mountain Goats, with special guest Lydia Loveless");
    assert.equal(goats.start, "2026-11-07T21:00");
    assert.equal(goats.startInstant, "2026-11-08T02:00:00.000Z");
  });

  test("recognizes ICS by body even with a wrong content type", () => {
    const page = makePage(
      "﻿BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:x\nDTSTART:20261110T010000Z\nSUMMARY:Late Show\nEND:VEVENT\nEND:VCALENDAR\n",
      "https://x.com/feed",
      "text/plain",
    );
    const ctx = makeCtx(page.url);
    assert.equal(icalExtractor.canHandle(page, ctx), true);
    const [ev] = extractIcal(page, ctx);
    assert.equal(ev.title, "Late Show");
    assert.equal(ev.start, "2026-11-09T19:00");
  });
});

describe("iCal primitives", () => {
  test("parseIcs handles quoted params with colons and unfolding", () => {
    const [cal] = parseIcs(
      'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDESCRIPTION;ALTREP="http://x.com/a:b":Hello\r\n  world\r\nEND:VEVENT\r\nEND:VCALENDAR',
    );
    const desc = cal.children[0].props[0];
    assert.equal(desc.name, "DESCRIPTION");
    assert.equal(desc.params.ALTREP, "http://x.com/a:b");
    assert.equal(desc.value, "Hello world");
  });

  test("unescapeText and parseDuration", () => {
    assert.equal(unescapeText("a\\, b\\; c\\nd\\\\e"), "a, b; c\nd\\e");
    assert.equal(parseDuration("PT2H30M"), 9_000_000);
    assert.equal(parseDuration("P1D"), 86_400_000);
    assert.equal(parseDuration("-PT15M"), -900_000);
    assert.equal(parseDuration("bogus"), null);
  });

  test("RRULE: last Saturday monthly, BYSETPOS, UNTIL, INTERVAL", () => {
    const always = () => true;
    const lastSat = parseRRule("FREQ=MONTHLY;BYDAY=-1SA");
    assert.ok(lastSat);
    assert.deepEqual(expandRRule(lastSat, "2026-11-28", "2027-02-28", always), [
      "2026-11-28",
      "2026-12-26",
      "2027-01-30",
      "2027-02-27",
    ]);
    const lastWeekday = parseRRule("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1");
    assert.ok(lastWeekday);
    assert.deepEqual(expandRRule(lastWeekday, "2026-11-30", "2027-01-31", always), [
      "2026-11-30",
      "2026-12-31",
      "2027-01-29",
    ]);
    const biweekly = parseRRule("FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH;UNTIL=20261201T000000Z");
    assert.ok(biweekly);
    assert.deepEqual(biweekly.until?.instant?.toISOString(), "2026-12-01T00:00:00.000Z");
    assert.deepEqual(
      expandRRule(biweekly, "2026-11-03", "2027-12-31", (d) => d <= "2026-11-30"),
      ["2026-11-03", "2026-11-05", "2026-11-17", "2026-11-19"],
    );
    const yearly = parseRRule("FREQ=YEARLY;COUNT=3");
    assert.ok(yearly);
    assert.deepEqual(expandRRule(yearly, "2026-12-31", "2030-01-01", always), [
      "2026-12-31",
      "2027-12-31",
      "2028-12-31",
    ]);
    assert.equal(parseRRule("FREQ=HOURLY"), null);
  });
});
