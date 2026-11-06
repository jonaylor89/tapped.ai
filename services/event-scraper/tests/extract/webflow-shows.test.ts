import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { extractWebflowShows, setTimes, webflowShowsExtractor } from "../../src/extract/webflow-shows.js";
import { fixturePage, makeCtx } from "./helpers.js";

const URL = "https://room.test/shows";
const page = fixturePage("webflow-shows.html", URL);

describe("webflow show list", () => {
  const events = extractWebflowShows(page, makeCtx(URL));

  test("recognizes the page", () => {
    assert.ok(webflowShowsExtractor.canHandle(page, makeCtx(URL)));
  });

  test("reads every card with its show time, doors, link and image", () => {
    assert.equal(events.length, 3);
    const box = events.find((event) => event.title?.startsWith("Box Factory"));
    assert.equal(box?.start, "--11-06T21:30");
    assert.equal(box?.doors, "21:00");
    assert.equal(
      box?.eventUrl,
      "https://room.test/shows/box-factory-s-first-friday-with-mad-abbey-marshall-family-values-06-nov",
    );
    assert.match(box?.imageUrl ?? "", /^https:\/\/cdn\.prod\.website-files\.com\//);
    assert.ok(box?.sourceEventId?.startsWith("webflow:/shows/"));
  });

  test("a sold-out tag counts only when it is visible", () => {
    assert.equal(events.filter((event) => event.status === "sold_out").length, 1);
    assert.notEqual(events.find((event) => event.title?.startsWith("Box Factory"))?.status, "sold_out");
  });
});

describe("webflow listed show cards", () => {
  const listed = "https://listed.test/calendar";
  const listedPage = fixturePage("webflow-listed-shows.html", listed);
  const events = extractWebflowShows(listedPage, makeCtx(listed));

  test("reads full dates, times and links", () => {
    assert.ok(webflowShowsExtractor.canHandle(listedPage, makeCtx(listed)));
    assert.equal(events.length, 3);
    const justin = events.find((event) => event.title === "JUSTIN TRAWICK AND THE COMMON GOOD");
    assert.equal(justin?.start, "2026-11-08T16:00");
    assert.equal(justin?.eventUrl, "https://listed.test/event/justin-trawick-and-the-common-good-112026");
  });

  test("each set of a two-set night is its own show; a closed card is not a show", () => {
    assert.deepEqual(setTimes("6 + 8:30PM"), ["18:00", "20:30"]);
    assert.deepEqual(setTimes("7:30 + 9:30PM"), ["19:30", "21:30"]);
    assert.deepEqual(setTimes("6PM + 8PM"), ["18:00", "20:00"]);
    assert.deepEqual(setTimes("4PM"), ["16:00"]);
    assert.deepEqual(setTimes("TBA"), []);
    const sets = events.filter((event) => event.title === "THE SKY CHIEFS");
    assert.equal(sets.length, 2);
    assert.notEqual(sets[0]?.start, sets[1]?.start);
    assert.notEqual(sets[0]?.sourceEventId, sets[1]?.sourceEventId);
    assert.equal(
      events.find((event) => event.title === "THANKSGIVING"),
      undefined,
    );
  });
});
