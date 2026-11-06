import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { extractSeasonDates, parseRun } from "../../src/extract/season-dates.js";
import { fixturePage, makeCtx } from "./helpers.js";

const URL = "https://theater.test/";

describe("theater season list", () => {
  test("reads every date format the page prints", () => {
    assert.deepEqual(parseRun("September 16th – October 10th, 2026"), { start: "2026-09-16", end: "2026-10-10" });
    assert.deepEqual(parseRun("July 7th – 31st, 2027"), { start: "2027-07-07", end: "2027-07-31" });
    assert.deepEqual(parseRun("October 15th – 17th. 2026"), { start: "2026-10-15", end: "2026-10-17" });
    assert.deepEqual(parseRun("January 8th & 9th, 2027"), { start: "2027-01-08", end: "2027-01-09" });
    assert.deepEqual(parseRun("December 31st, 2026"), { start: "2026-12-31", end: null });
    assert.deepEqual(parseRun("December 28th – January 3rd, 2027"), { start: "2026-12-28", end: "2027-01-03" });
    assert.equal(parseRun("Coming soon"), null);
  });

  const events = extractSeasonDates(fixturePage("season-dates.html", URL), makeCtx(URL));

  test("pairs each date with its show; main stage is theater", () => {
    assert.equal(events.length, 10);
    const play = events.find((event) => event.title === "Avenue Q");
    assert.equal(play?.start, "2027-07-07");
    assert.equal(play?.end, "2027-07-31");
    assert.equal(play?.category, "theater");
    assert.match(play?.description ?? "", /^by Robert Lopez/);
    assert.ok(events.find((event) => event.title?.startsWith("Julie Fulcher Davis")));
  });
});
