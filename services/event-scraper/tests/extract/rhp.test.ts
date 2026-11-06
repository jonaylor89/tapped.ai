import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { extractRhp } from "../../src/extract/rhp.js";
import { parseRoutes, routeEvents } from "../../src/extract/routes.js";
import { fixturePage, makeCtx } from "./helpers.js";

const URL = "https://venue-group.test/events/";

describe("multi-venue calendar", () => {
  const events = extractRhp(fixturePage("rhp-events.html", URL), makeCtx(URL));

  test("each card keeps its own venue, a yearless date and doors time", () => {
    assert.deepEqual([...new Set(events.map((e) => e.venueKey))].sort(), [
      "richmond-music-hall",
      "the-broadberry-2",
      "the-camel",
      "vclub",
    ]);
    for (const event of events) {
      assert.match(event.start ?? "", /^--\d{2}-\d{2}/);
      assert.match(event.doors ?? "", /^\d{2}:\d{2}$/);
      assert.ok(event.title);
      assert.ok(event.sourceEventId?.startsWith("rhp:/event/"));
    }
  });

  test("routes events to venues, drops ignored keys, holds back unknown ones", () => {
    const routes = parseRoutes(["the-broadberry-2=v-broadberry", "richmond-music-hall=v-rmh", "the-camel=ignore"]);
    const routed = routeEvents({ venueRoutes: routes }, events);
    assert.equal(routed.byVenue.get("v-broadberry")?.length, 1);
    assert.equal(routed.byVenue.get("v-rmh")?.length, 1);
    assert.equal(routed.ignored, 1);
    assert.deepEqual([...routed.unknown], [["vclub", 1]]);
  });

  test("an event with no venue is never assigned", () => {
    const routed = routeEvents({ venueRoutes: { a: "v" } }, [{ ...events[0], venueKey: null } as (typeof events)[0]]);
    assert.equal(routed.byVenue.size, 0);
    assert.deepEqual([...routed.unknown], [["", 1]]);
  });

  test("bad route specs are refused", () => {
    assert.throws(() => parseRoutes(["nope"]));
    assert.throws(() => parseRoutes(["=v"]));
    assert.deepEqual(parseRoutes(["A=ignore"]), { a: null });
  });
});
