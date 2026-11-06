import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { addSource, getCandidate, listCandidates, upsertVenues } from "../src/db.js";
import { seedKnownVenues } from "../src/discovery/seed.js";
import { countDateMentions, looksLikeEventListing } from "../src/llm/text.js";
import { createLlmExtractor } from "../src/runner.js";
import type { ExtractContext, Page, Venue } from "../src/types.js";
import { openTestDb } from "./helpers/db.js";

describe("LLM gate", () => {
  test("counts distinct date mentions in several formats", () => {
    assert.equal(countDateMentions("Nov 5 · November 6th · 7 Nov · 11/08 · 2026-11-09 · Nov 5"), 5);
    assert.equal(countDateMentions("Tacos, burritos and margaritas. Open daily 11-10."), 0);
  });

  test("only calendar-like pages are sent to the LLM", () => {
    const calendar =
      "<ul><li>Sap, Sludge Mother November 3, 2026</li><li>WCW November 4, 2026</li><li>Dogwood Tales November 5, 2026</li></ul>";
    const menu = "<h1>Menu</h1><p>Tacos $3. Happy hour 4-6pm. Private events available, book today.</p>";
    assert.equal(looksLikeEventListing(calendar, "text/html"), true);
    assert.equal(looksLikeEventListing(menu, "text/html"), false);
    let consumed = 0;
    const extractor = createLlmExtractor({ budget: { tryConsume: () => (consumed++, true) } });
    const ctx = { llm: { completeJson: async () => ({ data: { events: [] } }) } } as unknown as ExtractContext;
    const page = (text: string) =>
      ({ url: "https://v.example/", finalUrl: "https://v.example/", contentType: "text/html", text }) as Page;
    assert.equal(extractor.canHandle(page(menu), ctx), false);
    assert.equal(extractor.canHandle(page(calendar), ctx), true);
    assert.equal(consumed, 0, "canHandle never consumes budget");
  });
});

describe("seed-venues", () => {
  const city = {
    name: "Richmond",
    bbox: { south: 37.45, west: -77.6, north: 37.62, east: -77.35 },
    timezone: "America/New_York",
  };
  const venue = (id: string, extra: Partial<Venue>): Venue => ({
    id,
    name: id,
    address: null,
    lat: 37.55,
    lng: -77.45,
    website: `https://${id}.example/`,
    googlePlaceId: null,
    timezone: null,
    syncedAt: 0,
    ...extra,
  });

  test("seeds in-city venues with their own site and no source, once", async () => {
    const db = await openTestDb();
    await upsertVenues(db, [
      venue("camel", {}),
      venue("outside", { lat: 41.88, lng: -87.63 }),
      venue("nosite", { website: null }),
      venue("social", { website: "https://www.instagram.com/somebar/" }),
      venue("hassource", {}),
    ]);
    await addSource(db, {
      venueId: "hassource",
      kind: "html",
      url: "https://hassource.example/events",
      timezone: "America/New_York",
    });
    const first = await seedKnownVenues(db, city, 1_000);
    assert.equal(first.inCity, 4);
    assert.equal(first.seeded, 1);
    assert.deepEqual(first.skipped, { noWebsite: 1, nonOwnSite: 1, hasSource: 1, alreadyCandidate: 0 });
    const [seeded] = await listCandidates(db);
    const stored = await getCandidate(db, seeded.id);
    assert.equal(stored?.status, "resolved");
    assert.equal(stored?.matchedVenueId, "camel");
    assert.equal(stored?.timezone, "America/New_York");
    assert.equal((await seedKnownVenues(db, city, 2_000)).seeded, 0, "re-running does not duplicate");
  });
});

describe("non-music calendars", async () => {
  const { classifyEvent } = await import("../src/validate/classify.js");
  const { hasPerformanceSignal } = await import("../src/discovery/prove.js");

  test("park/museum programming is dropped, music with the same words is kept", () => {
    for (const title of [
      "Food Trucks Mon, Nov 2",
      "Toddler Time",
      "Trail Trek: Virginia Wildlife Trail Guided Tour",
      "Animal Encounters",
      "Adult Night Hike",
      "Wreath Workshop",
      "Holiday Photo Sessions at Maymont Mansion",
      "“In Our Nature” Film Screening",
    ]) {
      assert.equal(classifyEvent({ title }).category, "other", title);
    }
    assert.equal(classifyEvent({ title: "Jazz Trio Workshop & Jam" }).category, "music");
    assert.equal(classifyEvent({ title: "Sap, Sludge Mother, easterlin" }).category, "music");
  });

  test("defaulted events prove a source only with performers or a doors time", () => {
    const base = { warnings: ["category_default"], performers: [], doorsLocal: null } as never;
    assert.equal(hasPerformanceSignal(base), false);
    assert.equal(hasPerformanceSignal({ ...(base as object), performers: ["Havok"] } as never), true);
    assert.equal(hasPerformanceSignal({ ...(base as object), doorsLocal: "2026-11-05T19:00" } as never), true);
    assert.equal(hasPerformanceSignal({ ...(base as object), warnings: [] } as never), true);
  });
});

describe("LLM auth failures", async () => {
  const { LlmError } = await import("../src/llm/openai.js");
  test("a 401 stops the LLM fallback instead of burning the daily budget", async () => {
    let calls = 0;
    const extractor = createLlmExtractor({ budget: { tryConsume: () => true } });
    const llm = {
      completeJson: async () => {
        calls++;
        throw new LlmError("LLM HTTP 401", "http", 401);
      },
    };
    const text = "<p>Nov 3 Sap</p><p>Nov 4 WCW</p><p>Nov 5 Dogwood Tales</p>";
    const page = { url: "https://v.example/", finalUrl: "https://v.example/", contentType: "text/html", text } as Page;
    const ctx = {
      llm,
      venue: { name: "V", timezone: "America/New_York" },
      timezone: "America/New_York",
      now: new Date("2026-11-01T12:00:00Z"),
      source: { url: page.url },
    } as unknown as ExtractContext;
    assert.equal(extractor.canHandle(page, ctx), true);
    await assert.rejects(async () => Promise.resolve(await extractor.extract(page, ctx)));
    assert.equal(extractor.canHandle(page, ctx), false);
    assert.ok(calls >= 1);
  });
});

describe("separate name and date quotes", async () => {
  const { buildQuoteIndex, quotesNear } = await import("../src/validate/quotes.js");
  const page = `<div class="show"><h3>Sap, Sludge Mother, easterlin</h3><span>November 3, 2026</span></div>
    ${"<p>This is some text inside of a div block.</p>".repeat(2)}
    <div class="show"><h3>Woman Crush Wednesday</h3><span>November 4, 2026</span></div>
    ${"<p>Lorem ipsum filler paragraph that separates far away content from the rest.</p>".repeat(12)}
    <div class="show"><h3>Far Away Band</h3></div>`;
  const index = buildQuoteIndex(page, "text/html");

  test("a nearby date supports a separately quoted title", () => {
    assert.equal(quotesNear(index, "Sap, Sludge Mother, easterlin", "November 3, 2026"), true);
  });

  test("a date far from the title does not", () => {
    assert.equal(quotesNear(index, "Far Away Band", "November 3, 2026"), false);
  });
});

describe("Richmond regressions", async () => {
  const { classifyEvent } = await import("../src/validate/classify.js");
  const { validateEvents } = await import("../src/validate/validate.js");

  test("museum tours and talks are not music", () => {
    for (const title of [
      "Poe and Cats Guided Focus Tour",
      "Tell-Tale Talks Featuring: Diana Peterfreund",
      "Short Story Club",
    ])
      assert.equal(classifyEvent({ title, performers: ["Someone"] }).category, "other", title);
    assert.equal(classifyEvent({ title: "Mama's Broke: Reunion Album Release Tour" }).category, "music");
  });

  test("a midnight UTC start that is an evening show in venue time keeps the instant", () => {
    const source = { id: "s", venueId: "v", kind: "html", url: "https://canal.example/", timezone: "America/New_York" };
    const out = validateEvents(
      [
        {
          title: "Devil Master",
          start: "2026-11-04T00:00",
          startInstant: "2026-11-04T00:00:00+00:00",
          end: "2026-11-04T04:00",
          timezone: null,
          doors: null,
          performers: ["Devil Master"],
          prices: [],
          evidence: [],
          extractor: "jsonld",
          category: null,
        } as never,
      ],
      { source, venue: null, timezone: "America/New_York", now: new Date("2026-11-01T12:00:00Z") } as never,
    );
    const event = out.valid[0];
    assert.ok(event, JSON.stringify(out.rejected));
    assert.equal(event.startLocal, "2026-11-03T19:00");
    assert.equal(event.endLocal, "2026-11-03T23:00");
    assert.ok(event.warnings.includes("instant_trusted"));
  });
});

describe("title paired with the neighbouring item's date", async () => {
  const { buildQuoteIndex, nearestDateIs } = await import("../src/validate/quotes.js");
  const { cleanPageText } = await import("../src/llm/text.js");
  const item = (title: string, weekday: string, date: string, time: string, genre: string) =>
    `<div role="listitem"><a href="/event/x"><h1>${title}</h1><div><div>${weekday}</div><div>${date}</div><div>${time}</div></div><div>${genre}</div></a></div>`;
  const page = `<div role="list">${[
    item("B.A.D. THURSDAY POWERHOUSE OPEN MIC", "THU", "NOVEMBER 5, 2026", "8PM", "R&B + POP"),
    item("REX RICHARDSON QUARTET + MARSHALL GILKES", "FRI", "NOVEMBER 6, 2026", "8PM", "JAZZ"),
    item("ELIZABETH WISE", "SAT", "NOVEMBER 7, 2026", "3PM", "BLUES"),
  ].join("")}</div>`;
  const index = buildQuoteIndex(page, "text/html");

  test("the nearest date wins (Révéler layout: title, then date)", () => {
    assert.equal(nearestDateIs(index, "REX RICHARDSON QUARTET + MARSHALL GILKES", [[11, 6]]), true);
    assert.equal(nearestDateIs(index, "REX RICHARDSON QUARTET + MARSHALL GILKES", [[11, 5]]), false);
  });

  test("the LLM text separates listing items", () => {
    const text = cleanPageText(page, "text/html");
    assert.match(text, /R&B \+ POP\n---\nREX RICHARDSON/);
    assert.ok(!text.startsWith("---"));
  });
});

describe("LLM events need the page's nearest date, not a quoted one", async () => {
  const { validateEvents } = await import("../src/validate/validate.js");
  const html = `<ul>
    <li><span>Nov 03</span><h3>The Garcia Project</h3><p>Door: 7 pm</p></li>
    <li><span>Nov 05</span><h3>Sadurn w/ Kitchen</h3><p>Door: 7 pm</p></li>
  </ul>`;
  const source = { id: "s", venueId: "v", url: "https://b.example/", timezone: "America/New_York" };
  const ctx = {
    source,
    timezone: "America/New_York",
    now: new Date("2026-11-01T12:00:00Z"),
    pageText: html,
    pageContentType: "text/html",
  };
  const llmEvent = (title: string, start: string) =>
    ({ title, start, evidence: [title, "Door: 7 pm"], extractor: "llm", performers: [], prices: [] }) as never;

  test("title-only quotes pass when the nearest printed date matches", () => {
    const out = validateEvents([llmEvent("The Garcia Project", "2026-11-03")], ctx as never);
    assert.equal(out.valid.length, 1, JSON.stringify(out.rejected));
  });

  test("a neighbouring listing's date is rejected", () => {
    const out = validateEvents([llmEvent("The Garcia Project", "2026-11-05")], ctx as never);
    assert.deepEqual(out.rejected[0]?.reasons, ["evidence_date_unsupported"]);
  });
});
