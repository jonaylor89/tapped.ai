import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, test } from "node:test";
import {
  addSource,
  getCandidate,
  insertCandidate,
  listCandidates,
  listPlaceAliases,
  resolvePlaceId,
  upsertVenues,
} from "../src/db.js";
import { bboxAround, cityGrid, haversineMeters, inBbox } from "../src/discovery/geo.js";
import { compareNames, nameSimilarity, nameTokens } from "../src/discovery/names.js";
import { parsePlace } from "../src/discovery/places.js";
import {
  clusterPlaces,
  establishmentScore,
  ingestPlaces,
  isGeocodeOnly,
  matchIdentity,
  recordProbe,
  resolveCandidate,
  syncVenuePlaceAliases,
} from "../src/discovery/resolve.js";
import type { PlaceResult, Venue } from "../src/types.js";
import { openTestDb } from "./helpers/db.js";

const NOW = Date.UTC(2026, 10, 2, 17);

function placesFixture(name: string): PlaceResult[] {
  const raw = JSON.parse(readFileSync(new URL(`./fixtures/discovery/${name}`, import.meta.url), "utf8")) as {
    places: Parameters<typeof parsePlace>[0][];
  };
  return raw.places.map(parsePlace).filter((p): p is PlaceResult => p !== null);
}

const allPlaces = () => [...placesFixture("places-indy-page1.json"), ...placesFixture("places-indy-page2.json")];
const byId = (places: PlaceResult[], id: string) => places.find((p) => p.placeId === id)!;

function venue(partial: Partial<Venue> & Pick<Venue, "id" | "name">): Venue {
  return {
    address: null,
    lat: null,
    lng: null,
    website: null,
    googlePlaceId: null,
    timezone: "America/Indiana/Indianapolis",
    syncedAt: NOW,
    ...partial,
  };
}

const INDY = { city: "Indianapolis", timezone: "America/Indiana/Indianapolis", now: NOW };

describe("names", () => {
  test("generic venue words and 'the' are ignored, distinctive words kept", () => {
    assert.deepEqual(nameTokens("The Mercury Room"), ["mercury", "room"]);
    assert.deepEqual(nameTokens("Mercury Room Live"), ["mercury", "room"]);
    assert.deepEqual(nameTokens("Hi-Fi Annex"), ["hi", "fi", "annex"]);
    assert.deepEqual(nameTokens("The Bar"), ["bar"]);
    assert.equal(compareNames("The Mercury Room", "Mercury Room Live"), "same");
    assert.equal(compareNames("The Hi-Fi", "HiFi"), "same");
    assert.equal(compareNames("Café Nocturne", "Cafe Nocturne"), "same");
    assert.equal(compareNames("The Hi-Fi", "Hi-Fi Annex"), "similar");
    assert.equal(compareNames("Melody Inn", "The Dome Room"), "different");
  });

  test("city words can be ignored", () => {
    assert.equal(compareNames("Mercury Room Indianapolis", "Mercury Room"), "similar");
    assert.equal(compareNames("Mercury Room Indianapolis", "Mercury Room", ["Indianapolis"]), "same");
    assert.ok(nameSimilarity("Rock & Roll Bar", "Rock and Roll Bar") === 1);
  });
});

describe("geo", () => {
  test("haversine and boxes", () => {
    const d = haversineMeters({ lat: 39.75712, lng: -86.14321 }, { lat: 39.75731, lng: -86.14344 });
    assert.ok(d > 25 && d < 35, `got ${d}`);
    const box = bboxAround({ lat: 39.76, lng: -86.15 }, 1000);
    assert.ok(inBbox({ lat: 39.765, lng: -86.155 }, box));
    assert.ok(!inBbox({ lat: 39.78, lng: -86.15 }, box));
    assert.ok(!inBbox({ lat: null, lng: null }, box));
  });

  test("city grid tiles the box with stable ids and clipped edges", () => {
    const cells = cityGrid(
      {
        name: "Indianapolis",
        timezone: "America/Indiana/Indianapolis",
        bbox: { south: 39.7, west: -86.2, north: 39.8, east: -86.1 },
      },
      5000,
    );
    // 0.1 deg lat ~ 11.1 km -> 3 rows; 0.1 deg lng at 39.75 ~ 8.6 km -> 2 cols.
    assert.equal(cells.length, 6);
    assert.equal(cells[0]!.id, "indianapolis:0:0");
    assert.ok(cells.every((c) => c.bbox.north <= 39.8 + 1e-12 && c.bbox.east <= -86.1 + 1e-12));
    assert.ok(cells.every((c) => c.radiusMeters > 0 && c.radiusMeters < 5000));
    assert.equal(new Set(cells.map((c) => c.id)).size, 6);
  });
});

describe("place types", () => {
  test("geocode results are never identities", () => {
    const places = allPlaces();
    assert.ok(isGeocodeOnly(byId(places, "ChIJ_MERCURY_PREMISE")));
    assert.ok(isGeocodeOnly(byId(places, "ChIJ_MERCURY_ADDR")));
    assert.ok(isGeocodeOnly(byId(places, "ChIJ_VIRGINIA_PREMISE")), "premise + generic types is still a premise");
    assert.ok(isGeocodeOnly(byId(places, "ChIJ_FOUNTAIN_SQUARE")));
    assert.ok(isGeocodeOnly(byId(places, "ChIJ_INDIANAPOLIS")));
    assert.ok(!isGeocodeOnly(byId(places, "ChIJ_MERCURY_BIZ")));
    assert.ok(!isGeocodeOnly({ types: ["point_of_interest", "establishment"], primaryType: null }));
  });

  test("venue-typed establishments outrank generic ones", () => {
    const places = allPlaces();
    assert.ok(
      establishmentScore(byId(places, "ChIJ_MERCURY_BIZ")) > establishmentScore(byId(places, "ChIJ_MERCURY_EVENTS")),
    );
    assert.ok(
      establishmentScore({ types: ["bar"], primaryType: "bar" }) >
        establishmentScore({ types: ["restaurant"], primaryType: null }),
    );
    assert.equal(establishmentScore(byId(places, "ChIJ_MERCURY_PREMISE")), 0);
  });
});

describe("clusterPlaces", () => {
  test("business + premise + street_address + second listing collapse into one venue", () => {
    const { clusters, discardedGeocode } = clusterPlaces(allPlaces(), { extraStopWords: ["Indianapolis"] });
    const mercury = clusters.find((c) => c.canonical.placeId === "ChIJ_MERCURY_BIZ")!;
    assert.ok(mercury, "Mercury cluster exists with the live_music_venue business as canonical");
    assert.deepEqual(mercury.members.map((m) => m.placeId).sort(), ["ChIJ_MERCURY_BIZ", "ChIJ_MERCURY_EVENTS"]);
    assert.deepEqual(mercury.geocodeAliases.map((m) => m.placeId).sort(), [
      "ChIJ_MERCURY_ADDR",
      "ChIJ_MERCURY_PREMISE",
    ]);
    assert.equal(mercury.review.length, 0);
    const discarded = discardedGeocode.map((p) => p.placeId).sort();
    assert.ok(discarded.includes("ChIJ_FOUNTAIN_SQUARE"), "areas are discarded");
    assert.ok(discarded.includes("ChIJ_INDIANAPOLIS"));
    assert.ok(discarded.includes("ChIJ_VIRGINIA_PREMISE"), "a building shared by two rooms belongs to neither");
  });

  test("two rooms in one building are never merged and are flagged for review", () => {
    const { clusters } = clusterPlaces(allPlaces());
    const hifi = clusters.find((c) => c.canonical.placeId === "ChIJ_HIFI_BIZ")!;
    const annex = clusters.find((c) => c.canonical.placeId === "ChIJ_HIFI_ANNEX")!;
    assert.equal(hifi.members.length, 1);
    assert.equal(annex.members.length, 1);
    assert.equal(hifi.review[0]?.reason, "nearby_similar_name");
    assert.equal(hifi.review[0]?.placeId, "ChIJ_HIFI_ANNEX");
    assert.equal(annex.review[0]?.placeId, "ChIJ_HIFI_BIZ");
  });

  test("a shared website domain is not an identity", () => {
    const { clusters } = clusterPlaces(allPlaces());
    const melody = clusters.find((c) => c.canonical.placeId === "ChIJ_MELODY_INN")!;
    const dome = clusters.find((c) => c.canonical.placeId === "ChIJ_DOME_ROOM")!;
    assert.notEqual(melody, dome);
    assert.equal(melody.members.length, 1);
    assert.equal(melody.review.length, 0, "different names next door with one domain are simply two venues");
  });

  test("same name but different websites nearby goes to review instead of merging", () => {
    const base = byId(allPlaces(), "ChIJ_MELODY_INN");
    const other: PlaceResult = {
      ...base,
      placeId: "ChIJ_MELODY_2",
      websiteUri: "https://melodyinn-other.com",
      lat: base.lat! + 0.0002,
    };
    const { clusters } = clusterPlaces([base, other]);
    assert.equal(clusters.length, 2);
    assert.equal(clusters[0]!.review[0]?.reason, "same_name_different_website");
  });

  test("same name + same domain may sit further apart (pin drift) and still merge", () => {
    const base = byId(allPlaces(), "ChIJ_MERCURY_BIZ");
    const drift: PlaceResult = {
      ...base,
      placeId: "ChIJ_MERCURY_DRIFT",
      types: ["bar"],
      primaryType: "bar",
      lat: base.lat! + 0.0013,
    };
    assert.equal(clusterPlaces([base, drift]).clusters.length, 1, "~145 m with same domain merges");
    const noSite: PlaceResult = { ...drift, websiteUri: null };
    assert.equal(clusterPlaces([base, noSite]).clusters.length, 2, "~145 m without domain evidence does not");
  });
});

describe("ingestPlaces", () => {
  test("writes one candidate per real venue with every place id as an alias", async () => {
    const db = await openTestDb();
    const summary = await ingestPlaces(db, allPlaces(), INDY);
    assert.equal(summary.closed, 1, "CLOSED_PERMANENTLY is skipped");
    assert.equal(summary.needsReview, 2, "Hi-Fi and Hi-Fi Annex");
    assert.equal(summary.created, 4, "Mercury, Melody Inn, Dome Room, Emerson");
    const mercury = (await listCandidates(db)).find((c) => c.name === "The Mercury Room")!;
    assert.equal(mercury.status, "resolved");
    assert.equal(mercury.primaryPlaceId, "ChIJ_MERCURY_BIZ");
    assert.equal(mercury.timezone, "America/Indiana/Indianapolis");
    assert.equal(mercury.websiteDomain, "mercuryroomindy.com");
    for (const id of ["ChIJ_MERCURY_BIZ", "ChIJ_MERCURY_EVENTS", "ChIJ_MERCURY_PREMISE", "ChIJ_MERCURY_ADDR"]) {
      assert.equal((await resolvePlaceId(db, id))?.candidateId, mercury.id, `${id} resolves to Mercury`);
    }
    const aliases = await listPlaceAliases(db, { candidateId: mercury.id });
    assert.equal(aliases.filter((a) => a.isCanonical).length, 1);
    assert.equal(aliases.find((a) => a.isCanonical)?.placeId, "ChIJ_MERCURY_BIZ");
    assert.equal(await resolvePlaceId(db, "ChIJ_VIRGINIA_PREMISE"), null);
    assert.equal(await resolvePlaceId(db, "ChIJ_INDIANAPOLIS"), null);
    const hifi = (await listCandidates(db)).find((c) => c.name === "The Hi-Fi")!;
    assert.equal(hifi.status, "needs_review");
    assert.equal(hifi.statusReason, "nearby_similar_name");
  });

  test("re-running is idempotent: the same venue resolves through any alias", async () => {
    const db = await openTestDb();
    await ingestPlaces(db, allPlaces(), INDY);
    const before = (await listCandidates(db)).length;
    const second = await ingestPlaces(db, allPlaces(), { ...INDY, now: NOW + 1000 });
    assert.equal((await listCandidates(db)).length, before);
    assert.equal(second.created, 0);
    // A later search that only returns the street address-like listing id still lands on Mercury.
    const eventsOnly = byId(allPlaces(), "ChIJ_MERCURY_EVENTS");
    const third = await ingestPlaces(db, [eventsOnly], { ...INDY, now: NOW + 2000 });
    assert.equal(third.merged, 1);
    assert.equal((await listCandidates(db)).length, before);
  });

  test("matches an existing production venue whose stored id is a premise and adopts the business id", async () => {
    const db = await openTestDb();
    await upsertVenues(db, [
      venue({
        id: "v-mercury",
        name: "Mercury Room",
        lat: 39.7571,
        lng: -86.1432,
        googlePlaceId: "ChIJ_MERCURY_PREMISE",
      }),
    ]);
    assert.deepEqual(await syncVenuePlaceAliases(db, NOW), { assigned: 1, shared: [] });
    await ingestPlaces(db, allPlaces(), INDY);
    const mercury = (await listCandidates(db)).find((c) => c.matchedVenueId === "v-mercury")!;
    assert.equal(mercury.status, "resolved");
    // The premise (building) id never decides identity; the venue still matches by proximity + name.
    assert.equal(mercury.statusReason, "matched_venue:geo_name");
    const aliases = await listPlaceAliases(db, { venueId: "v-mercury" });
    assert.deepEqual(aliases.map((a) => a.placeId).sort(), [
      "ChIJ_MERCURY_ADDR",
      "ChIJ_MERCURY_BIZ",
      "ChIJ_MERCURY_EVENTS",
      "ChIJ_MERCURY_PREMISE",
    ]);
    assert.equal(aliases.find((a) => a.isCanonical)?.placeId, "ChIJ_MERCURY_BIZ", "establishment beats premise");
  });

  test("a venue that already has an enabled source is not re-proposed", async () => {
    const db = await openTestDb();
    await upsertVenues(db, [venue({ id: "v-melody", name: "Melody Inn", lat: 39.8261, lng: -86.1601 })]);
    await addSource(
      db,
      {
        venueId: "v-melody",
        kind: "html",
        url: "https://indyvenuegroup.com/melody-inn/shows",
        timezone: "America/Indiana/Indianapolis",
      },
      NOW,
    );
    await ingestPlaces(db, allPlaces(), INDY);
    const melody = (await listCandidates(db)).find((c) => c.matchedVenueId === "v-melody")!;
    assert.equal(melody.status, "rejected");
    assert.equal(melody.statusReason, "venue_has_source");
  });

  test("two rooms sharing one place id in production => needs_review, nothing merged or stolen", async () => {
    const db = await openTestDb();
    await upsertVenues(db, [
      venue({
        id: "v-emerson",
        name: "The Emerson Theater",
        googlePlaceId: "ChIJ_EMERSON",
        lat: 39.7815,
        lng: -86.0873,
      }),
      venue({ id: "v-side", name: "Emerson Side Room", googlePlaceId: "ChIJ_EMERSON", lat: 39.7815, lng: -86.0873 }),
    ]);
    assert.deepEqual(await syncVenuePlaceAliases(db, NOW), { assigned: 0, shared: ["ChIJ_EMERSON"] });
    await ingestPlaces(db, allPlaces(), INDY);
    const emerson = (await listCandidates(db)).find((c) => c.name === "The Emerson Theater")!;
    assert.equal(emerson.status, "needs_review");
    assert.equal(emerson.statusReason, "same_place_id_different_name");
    assert.equal(emerson.matchedVenueId, null);
    assert.equal(await resolvePlaceId(db, "ChIJ_EMERSON"), null, "alias not assigned to anyone");
    const conflict = emerson.evidence.conflict as { venueIds: string[] };
    assert.deepEqual(conflict.venueIds.sort(), ["v-emerson", "v-side"]);
    // Re-running does not create a second review row.
    await ingestPlaces(db, allPlaces(), { ...INDY, now: NOW + 1 });
    assert.equal((await listCandidates(db)).filter((c) => c.name === "The Emerson Theater").length, 1);
  });

  test("a mis-assigned place id (different name) is routed to review", async () => {
    const db = await openTestDb();
    await upsertVenues(db, [venue({ id: "v-annex", name: "Hi-Fi Annex", googlePlaceId: "ChIJ_HIFI_BIZ" })]);
    const outcome = await recordProbe(
      db,
      {
        name: "The Hi-Fi",
        lat: 39.75405,
        lng: -86.14102,
        discoveredFrom: "google_places",
        places: [
          {
            placeId: "ChIJ_HIFI_BIZ",
            types: ["night_club"],
            displayName: "The Hi-Fi",
            lat: 39.75405,
            lng: -86.14102,
            canonical: true,
          },
        ],
      },
      INDY,
    );
    assert.equal(outcome.kind, "needs_review");
    assert.equal(outcome.match.kind, "conflict");
    assert.equal(await resolvePlaceId(db, "ChIJ_HIFI_BIZ"), null);
  });
});

describe("matchIdentity without place ids", () => {
  test("geo + name matches production venues; similar names nearby are ambiguous", async () => {
    const db = await openTestDb();
    await upsertVenues(db, [
      venue({ id: "v-hifi", name: "The Hi-Fi", lat: 39.75405, lng: -86.14102, website: "https://thehifi.com" }),
    ]);
    assert.deepEqual(await matchIdentity(db, { name: "Hi-Fi", lat: 39.7541, lng: -86.141, discoveredFrom: "osm" }), {
      kind: "venue",
      venueId: "v-hifi",
      candidateId: null,
      via: "geo_name",
    });
    const annex = await matchIdentity(db, {
      name: "Hi-Fi Annex",
      lat: 39.75397,
      lng: -86.14085,
      discoveredFrom: "osm",
    });
    assert.equal(annex.kind, "conflict");
    assert.equal(annex.kind === "conflict" && annex.reason, "nearby_similar_name");
    assert.deepEqual(await matchIdentity(db, { name: "The Hi-Fi", lat: 39.8, lng: -86.2, discoveredFrom: "osm" }), {
      kind: "none",
    });
  });

  test("a matching website domain alone never matches", async () => {
    const db = await openTestDb();
    await upsertVenues(db, [
      venue({ id: "v-hifi", name: "The Hi-Fi", lat: 39.75405, lng: -86.14102, website: "https://thehifi.com" }),
    ]);
    const result = await matchIdentity(db, {
      name: "Square Cat Vinyl",
      website: "https://thehifi.com/square-cat",
      lat: 39.7541,
      lng: -86.141,
      discoveredFrom: "listing",
    });
    assert.deepEqual(result, { kind: "none" });
  });

  test("name-only probes match within the same city only", async () => {
    const db = await openTestDb();
    await upsertVenues(db, [
      venue({ id: "v-melody", name: "Melody Inn", address: "3826 N Illinois St, Indianapolis, IN" }),
    ]);
    assert.equal(
      (await matchIdentity(db, { name: "The Melody Inn", city: "Indianapolis", discoveredFrom: "listing" })).kind,
      "venue",
    );
    assert.equal(
      (await matchIdentity(db, { name: "Melody Inn", city: "Louisville", discoveredFrom: "listing" })).kind,
      "none",
    );
    assert.equal((await matchIdentity(db, { name: "Melody Inn", discoveredFrom: "listing" })).kind, "none");
  });
});

describe("resolveCandidate", () => {
  test("folds a manually added duplicate into the existing candidate", async () => {
    const db = await openTestDb();
    await ingestPlaces(db, allPlaces(), INDY);
    const mercury = (await listCandidates(db)).find((c) => c.name === "The Mercury Room")!;
    const manual = await insertCandidate(
      db,
      { name: "Mercury Room", lat: 39.7571, lng: -86.1432, discoveredFrom: "manual", status: "new" },
      NOW,
    );
    const outcome = await resolveCandidate(db, manual.id, { now: NOW });
    assert.equal(outcome.kind, "merged");
    assert.equal(outcome.candidate.id, mercury.id);
    assert.equal((await getCandidate(db, manual.id))?.status, "rejected");
    assert.equal((await getCandidate(db, manual.id))?.statusReason, `duplicate_of:${mercury.id}`);
    assert.ok(((await getCandidate(db, mercury.id))?.evidence.feeds as string[]).includes("manual"));
  });

  test("a new unknown candidate becomes resolved", async () => {
    const db = await openTestDb();
    const manual = await insertCandidate(
      db,
      { name: "Brand New Room", lat: 39.7, lng: -86.1, discoveredFrom: "manual", status: "new" },
      NOW,
    );
    assert.equal((await resolveCandidate(db, manual.id, { now: NOW })).candidate.status, "resolved");
  });
});
