import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { listCandidates, openDb, resolvePlaceId } from "../src/db.js";
import {
  BandsintownHttpClient,
  createBandsintownClientFromEnv,
  discoverFromBandsintown,
  encodeArtistName,
  parseBandsintownEvents,
} from "../src/discovery/bandsintown.js";
import type { GridCell } from "../src/discovery/geo.js";
import { discoverFromListing, extractListingVenueRefs, splitLocationText } from "../src/discovery/listings.js";
import {
  buildOverpassQuery,
  discoverOsmArea,
  OverpassHttpClient,
  parseOverpassResponse,
  probeFromOsm,
} from "../src/discovery/osm.js";
import {
  createPlacesClientFromEnv,
  discoverPlacesCell,
  GooglePlacesClient,
  PLACES_FIELD_MASK,
  PlacesApiError,
  searchCell,
} from "../src/discovery/places.js";
import type { BandsintownClient, OverpassClient, PlacesClient } from "../src/types.js";
import { fakeFetch, fixedClock, fixtureJson, fixtureText, NOW_MS, politeClient } from "./helpers/discovery.js";

const TZ = "America/Indiana/Indianapolis";
const CELL: GridCell = {
  id: "indianapolis:0:0",
  city: "Indianapolis",
  timezone: TZ,
  bbox: { south: 39.74, west: -86.17, north: 39.84, east: -86.08 },
  center: { lat: 39.79, lng: -86.125 },
  radiusMeters: 6000,
};
const FAKE_KEY = "test-key-not-real";

function placesFetch() {
  const pages = [fixtureJson("places-indy-page1.json"), fixtureJson("places-indy-page2.json")];
  return fakeFetch({
    "https://places.googleapis.com/v1/places:searchText": (call) => {
      const body = JSON.parse(call.body ?? "{}") as { pageToken?: string; textQuery: string };
      const page =
        body.pageToken === "PAGE_TWO_TOKEN"
          ? pages[1]
          : body.textQuery === "live music venue"
            ? pages[0]
            : { places: [] };
      return new Response(JSON.stringify(page), { status: 200, headers: { "content-type": "application/json" } });
    },
  });
}

describe("Google Places (New) client", () => {
  test("sends field mask, key header, rectangle restriction and paginates", async () => {
    const { calls, fetchImpl } = placesFetch();
    const client = new GooglePlacesClient({ apiKey: FAKE_KEY, fetchImpl });
    const first = await client.textSearch({ textQuery: "live music venue", center: CELL.center, radiusMeters: 2000 });
    assert.equal(first.places.length, 10);
    assert.equal(first.nextPageToken, "PAGE_TWO_TOKEN");
    const call = calls[0]!;
    assert.equal(call.method, "POST");
    assert.equal(call.headers["x-goog-api-key"], FAKE_KEY);
    assert.equal(call.headers["x-goog-fieldmask"], PLACES_FIELD_MASK);
    for (const field of [
      "id",
      "displayName",
      "types",
      "primaryType",
      "formattedAddress",
      "location",
      "websiteUri",
      "businessStatus",
    ]) {
      assert.ok(PLACES_FIELD_MASK.includes(`places.${field}`), field);
    }
    const body = JSON.parse(call.body!);
    assert.equal(body.pageSize, 20);
    assert.ok(body.locationRestriction.rectangle.low.latitude < CELL.center.lat);
    assert.ok(body.locationRestriction.rectangle.high.longitude > CELL.center.lng);
    const mercury = first.places.find((p) => p.placeId === "ChIJ_MERCURY_BIZ")!;
    assert.equal(mercury.displayName, "The Mercury Room");
    assert.equal(mercury.lat, 39.75712);
    assert.equal(mercury.primaryType, "live_music_venue");
  });

  test("errors never include the API key", async () => {
    const { fetchImpl } = fakeFetch({
      "https://places.googleapis.com/v1/places:searchText": () =>
        new Response(JSON.stringify({ error: { status: "PERMISSION_DENIED", message: `bad key ${FAKE_KEY}` } }), {
          status: 403,
        }),
    });
    const client = new GooglePlacesClient({ apiKey: FAKE_KEY, fetchImpl });
    await assert.rejects(
      client.textSearch({ textQuery: "x", center: CELL.center, radiusMeters: 100 }),
      (error: unknown) => error instanceof PlacesApiError && error.status === 403 && !error.message.includes(FAKE_KEY),
    );
  });

  test("env gating", () => {
    assert.equal(createPlacesClientFromEnv({}), null);
    assert.ok(createPlacesClientFromEnv({ GOOGLE_PLACES_API_KEY: FAKE_KEY }) instanceof GooglePlacesClient);
  });

  test("searchCell runs every query and page, dedupes and drops permanently closed places", async () => {
    const { calls, fetchImpl } = placesFetch();
    const sleeps: number[] = [];
    const client = new GooglePlacesClient({ apiKey: FAKE_KEY, fetchImpl });
    const result = await searchCell(client, CELL, {
      queries: ["live music venue", "comedy club"],
      sleep: async (ms) => {
        sleeps.push(ms);
      },
    });
    assert.equal(calls.length, 3, "2 pages for the first query, 1 for the second");
    assert.deepEqual(sleeps, [1500]);
    assert.equal(result.closed, 1);
    assert.equal(result.places.filter((p) => p.placeId === "ChIJ_MERCURY_BIZ").length, 1);
    assert.ok(!result.places.some((p) => p.placeId === "ChIJ_OLD_VENUE"));
  });

  test("discoverPlacesCell records clustered candidates", async () => {
    const db = openDb(":memory:");
    const { fetchImpl } = placesFetch();
    const client: PlacesClient = new GooglePlacesClient({ apiKey: FAKE_KEY, fetchImpl });
    const summary = await discoverPlacesCell(db, client, CELL, {
      queries: ["live music venue"],
      sleep: async () => {},
      clock: fixedClock,
    });
    assert.equal(summary.requests, 2);
    assert.equal(summary.closed, 1);
    assert.equal(summary.created + summary.needsReview, 6);
    const mercury = listCandidates(db).find((c) => c.name === "The Mercury Room")!;
    assert.equal(mercury.city, "Indianapolis");
    assert.equal(mercury.timezone, TZ);
    assert.equal(mercury.createdAt, NOW_MS);
    const obs = (mercury.evidence.observations as Record<string, unknown>[])[0]!;
    assert.equal(obs.cell, CELL.id);
    assert.equal(obs.feed, "google_places");
  });
});

describe("OpenStreetMap Overpass", () => {
  test("query covers venue amenities, live_music bars and the bbox", () => {
    const ql = buildOverpassQuery({ south: 39.7, west: -86.2, north: 39.8, east: -86.1 });
    assert.match(ql, /^\[out:json\]\[timeout:90\];/);
    assert.match(ql, /"amenity"~"\^\(music_venue\|nightclub\|theatre\|arts_centre/);
    assert.match(ql, /\["live_music"="yes"\]/);
    assert.match(ql, /\(39\.7,-86\.2,39\.8,-86\.1\)/);
    assert.match(ql, /out center tags;$/);
  });

  test("parses nodes and way centers; skips unnamed / location-less elements", () => {
    const elements = parseOverpassResponse(fixtureJson("overpass-indy.json"));
    assert.equal(elements.length, 5);
    assert.deepEqual(elements[1], {
      id: "way/2002",
      type: "way",
      lat: 39.76841,
      lng: -86.15532,
      tags: { amenity: "theatre", name: "Murat Theatre", "theatre:type": "concert_hall" },
    });
    assert.equal(probeFromOsm(elements[3]!), null, "unnamed");
    assert.equal(probeFromOsm(elements[4]!), null, "no coordinates");
    const radio = probeFromOsm(elements[2]!)!;
    assert.equal(radio.website, "https://radioradioindy.com/");
    assert.equal(probeFromOsm(elements[0]!)!.address, "412 Shelby Street, Indianapolis");
  });

  test("the HTTP client posts form-encoded QL with our User-Agent and spaces requests", async () => {
    const { calls, fetchImpl } = fakeFetch({
      "https://overpass-api.de/api/interpreter": () => new Response(fixtureText("overpass-indy.json"), { status: 200 }),
    });
    const sleeps: number[] = [];
    const client = new OverpassHttpClient({
      fetchImpl,
      clock: fixedClock,
      sleep: async (ms) => {
        sleeps.push(ms);
      },
      minIntervalMs: 10_000,
    });
    await client.query("[out:json];node(1);out;");
    await client.query("[out:json];node(2);out;");
    assert.equal(calls[0]!.method, "POST");
    assert.equal(calls[0]!.body, `data=${encodeURIComponent("[out:json];node(1);out;")}`);
    assert.match(calls[0]!.headers["user-agent"]!, /^TappedEventScraper\//);
    assert.deepEqual(sleeps, [10_000]);
  });

  test("OSM features merge into existing Places candidates and add new ones", async () => {
    const db = openDb(":memory:");
    const { fetchImpl } = placesFetch();
    await discoverPlacesCell(db, new GooglePlacesClient({ apiKey: FAKE_KEY, fetchImpl }), CELL, {
      queries: ["live music venue"],
      sleep: async () => {},
      clock: fixedClock,
    });
    const before = listCandidates(db).length;
    const overpass: OverpassClient = { query: async () => parseOverpassResponse(fixtureJson("overpass-indy.json")) };
    const summary = await discoverOsmArea(db, overpass, CELL.bbox, { city: "Indianapolis", timezone: TZ, now: NOW_MS });
    assert.deepEqual(summary.outcomes, { created: 2, merged: 1, matched_venue: 0, needs_review: 0 });
    assert.equal(summary.skipped, 2);
    assert.equal(listCandidates(db).length, before + 2);
    const mercury = listCandidates(db).find((c) => c.name === "The Mercury Room")!;
    assert.deepEqual(mercury.evidence.feeds, ["google_places", "osm"]);
  });
});

describe("city listing feed", () => {
  test("venue references come from JSON-LD locations and microdata; ticketing and virtual places are dropped", () => {
    const refs = extractListingVenueRefs({
      text: fixtureText("listing-indy.html"),
      contentType: "text/html",
      finalUrl: "https://www.indyweekly.example/music/this-week",
    });
    const byName = new Map(refs.map((r) => [r.name, r]));
    assert.deepEqual([...byName.keys()].sort(), ["Gainbridge Fieldhouse", "Healer", "Melody Inn", "Square Cat Vinyl"]);
    assert.equal(byName.get("Healer")!.eventCount, 2);
    assert.equal(byName.get("Healer")!.website, "https://healerindy.com/");
    assert.equal(byName.get("Healer")!.lat, 39.7741);
    assert.equal(byName.get("Melody Inn")!.website, null, "the listing's own venue page is not the venue website");
    assert.equal(byName.get("Melody Inn")!.listingVenueUrl, "https://www.indyweekly.example/venues/melody-inn");
    assert.equal(byName.get("Melody Inn")!.address, "3826 N Illinois St, Indianapolis, IN");
    assert.equal(byName.get("Gainbridge Fieldhouse")!.website, null, "ticketing URLs are never a venue website");
    assert.equal(byName.get("Square Cat Vinyl")!.website, "https://squarecatvinyl.com/");
  });

  test("iCal LOCATION lines and free-text locations", () => {
    const ics = [
      "BEGIN:VCALENDAR",
      "BEGIN:VEVENT",
      "SUMMARY:Open Mic",
      "LOCATION:Healer\\, 1101 E 16th St\\, Indianapolis",
      "GEO:39.7741;-86.1338",
      "END:VEVENT",
      "BEGIN:VEVENT",
      "SUMMARY:Online thing",
      "LOCATION:Online",
      "END:VEVENT",
      "END:VCALENDAR",
    ].join("\r\n");
    const refs = extractListingVenueRefs({
      text: ics,
      contentType: "text/calendar",
      finalUrl: "https://city.example/cal.ics",
    });
    assert.equal(refs.length, 1);
    assert.equal(refs[0]!.name, "Healer");
    assert.equal(refs[0]!.address, "1101 E 16th St, Indianapolis");
    assert.equal(refs[0]!.lng, -86.1338);
    assert.equal(splitLocationText("123 Main St"), null);
  });

  test("discoverFromListing fetches politely and records candidates (name-only venues matched by city)", async () => {
    const db = openDb(":memory:");
    const { fetchImpl } = placesFetch();
    await discoverPlacesCell(db, new GooglePlacesClient({ apiKey: FAKE_KEY, fetchImpl }), CELL, {
      queries: ["live music venue"],
      sleep: async () => {},
      clock: fixedClock,
    });
    const net = fakeFetch({ "https://www.indyweekly.example/music/this-week": fixtureText("listing-indy.html") });
    const summary = await discoverFromListing(
      db,
      politeClient(net.fetchImpl),
      { url: "https://www.indyweekly.example/music/this-week", city: "Indianapolis", timezone: TZ },
      { now: NOW_MS },
    );
    assert.equal(summary.status, "ok");
    assert.equal(summary.venues, 4);
    assert.equal(summary.outcomes.merged, 1, "Melody Inn (from Places) matched by name within the city");
    assert.equal(summary.outcomes.created, 3);
    assert.ok(
      net.calls.some((c) => c.url.endsWith("/robots.txt")),
      "robots.txt consulted",
    );
    assert.ok(!net.calls.some((c) => c.url.includes("ticketmaster")), "never fetches ticketing");
    const healer = listCandidates(db).find((c) => c.name === "Healer")!;
    assert.equal(healer.discoveredFrom, "listing");
    assert.equal(healer.website, "https://healerindy.com/");
    assert.equal(healer.timezone, TZ);
  });

  test("ticketing listing URLs are refused without any request", async () => {
    const db = openDb(":memory:");
    const net = fakeFetch({});
    const summary = await discoverFromListing(db, politeClient(net.fetchImpl), {
      url: "https://www.eventbrite.com/d/in--indianapolis/music--events/",
      city: "Indianapolis",
      timezone: TZ,
    });
    assert.equal(summary.status, "rejected_ticketing");
    assert.equal(net.calls.length, 0);
    assert.equal(listCandidates(db).length, 0);
  });

  test("a listing that redirects to a ticketing platform is blocked", async () => {
    const db = openDb(":memory:");
    const net = fakeFetch({
      "https://city.example/events": () =>
        new Response(null, { status: 302, headers: { location: "https://www.dice.fm/browse/indianapolis" } }),
    });
    const summary = await discoverFromListing(db, politeClient(net.fetchImpl), {
      url: "https://city.example/events",
      city: "Indianapolis",
      timezone: TZ,
    });
    assert.equal(summary.status, "rejected_ticketing");
    assert.ok(!net.calls.some((c) => c.url.includes("dice.fm")));
  });
});

describe("Bandsintown (optional)", () => {
  test("disabled unless app id AND explicit enable", () => {
    assert.equal(createBandsintownClientFromEnv({}), null);
    assert.equal(createBandsintownClientFromEnv({ BANDSINTOWN_APP_ID: "x" }), null);
    assert.equal(createBandsintownClientFromEnv({ EVENT_SCRAPER_BANDSINTOWN: "1" }), null);
    assert.ok(createBandsintownClientFromEnv({ BANDSINTOWN_APP_ID: "x", EVENT_SCRAPER_BANDSINTOWN: "1" }));
    assert.ok(createBandsintownClientFromEnv({ BANDSINTOWN_APP_ID: "x" }, { enabled: true }));
  });

  test("parses events and escapes artist names per the API rules", () => {
    const events = parseBandsintownEvents(fixtureJson("bandsintown-artist.json"));
    assert.equal(events.length, 2);
    assert.equal(events[0]!.venue.lat, 39.7741);
    assert.equal(encodeArtistName("AC/DC"), "AC%252FDC");
    assert.equal(encodeArtistName("Why?"), "Why%253F");
    assert.deepEqual(parseBandsintownEvents({ errorMessage: "[NotFound] The artist was not found" }), []);
  });

  test("client is rate limited and treats 404 as no events", async () => {
    const { calls, fetchImpl } = fakeFetch({
      "https://rest.bandsintown.com/artists/The%20Example%20Band/events": () =>
        new Response(fixtureText("bandsintown-artist.json"), { status: 200 }),
    });
    const sleeps: number[] = [];
    const client = new BandsintownHttpClient({
      appId: "app",
      fetchImpl,
      clock: fixedClock,
      sleep: async (ms) => {
        sleeps.push(ms);
      },
    });
    assert.equal((await client.artistEvents("The Example Band")).length, 2);
    assert.deepEqual(await client.artistEvents("Unknown Artist"), []);
    assert.deepEqual(sleeps, [3000]);
    assert.match(calls[0]!.url, /app_id=app/);
    assert.match(calls[0]!.url, /date=upcoming/);
  });

  test("only venues inside configured areas become candidates; event URLs are evidence only", async () => {
    const db = openDb(":memory:");
    const client: BandsintownClient = {
      artistEvents: async () => parseBandsintownEvents(fixtureJson("bandsintown-artist.json")),
    };
    const summary = await discoverFromBandsintown(db, client, ["The Example Band", "the example band ", ""], {
      areas: [{ city: "Indianapolis", timezone: TZ, bbox: CELL.bbox }],
      now: NOW_MS,
    });
    assert.equal(summary.artists, 2, "names are trimmed and deduped exactly");
    assert.equal(summary.outsideAreas, 2);
    const healer = listCandidates(db).find((c) => c.name === "Healer")!;
    assert.equal(healer.discoveredFrom, "bandsintown");
    assert.equal(healer.website, null);
    assert.equal(healer.timezone, TZ);
    assert.equal(resolvePlaceId(db, "anything"), null);
  });
});
