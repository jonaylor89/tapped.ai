import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { extractAeg, looksLikeAegEvents } from "../../src/extract/aeg.js";
import { parseJsonPage } from "../../src/extract/util.js";
import { fixturePage, makeCtx } from "./helpers.js";

const URL = "https://example-content.test/json/events/51/events.json";

describe("AEG venue schedule feed", () => {
  const page = fixturePage("aeg-events.json", URL);
  const events = extractAeg(page, makeCtx(URL));

  test("is recognized only by its own shape", () => {
    assert.ok(looksLikeAegEvents(parseJsonPage(page)));
    assert.ok(!looksLikeAegEvents({ meta: {}, events: [{ title: "No date" }] }));
    assert.ok(!looksLikeAegEvents({ events: [] }));
  });

  test("reads title, local and absolute time, doors, performers and the site's id", () => {
    const first = events[0];
    assert.ok(first);
    assert.equal(first.title, "The Sword");
    assert.equal(first.start, "2026-11-07T20:00");
    assert.equal(first.startInstant, "2026-11-07T20:00:00-05:00");
    assert.equal(first.timezone, "America/New_York");
    assert.equal(first.doors, "2026-11-07T19:00");
    assert.deepEqual(first.performers, ["The Sword", "Hippie Death Cult"]);
    assert.equal(first.sourceEventId, "aeg:1611230");
    assert.equal(first.imageUrl, null);
  });

  test("skips private events and carries a canceled status", () => {
    assert.ok(!events.some((event) => event.sourceEventId === "aeg:3"));
    assert.equal(events.find((event) => event.sourceEventId === "aeg:4")?.status, "canceled");
  });
});
