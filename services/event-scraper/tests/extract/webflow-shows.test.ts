import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { extractWebflowShows, webflowShowsExtractor } from "../../src/extract/webflow-shows.js";
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
