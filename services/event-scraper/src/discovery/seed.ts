/**
 * Seeds known Tapped venues (from the local venue snapshot) into the same find-source -> prove pipeline that discovered
 * candidates use. A venue is seeded once, only when it has its own website, sits inside the city's bbox and has no
 * enabled source yet. Seeded candidates start as `resolved` with `matchedVenueId` set, so proving them never creates a
 * new venue; a promoted one is registered with `add-source --candidate ID` after review, like any other candidate.
 */
import { type Db, insertCandidate, listCandidates, listSources, listVenues, updateCandidate } from "../db.js";
import { isTicketingUrl } from "../denylist.js";
import type { Candidate } from "../types.js";
import { type CityConfig, inBbox } from "./geo.js";
import { isNonOwnSite } from "./website.js";

export interface SeedResult {
  city: string;
  inCity: number;
  seeded: number;
  skipped: { noWebsite: number; nonOwnSite: number; hasSource: number; alreadyCandidate: number };
}

export async function seedKnownVenues(db: Db, city: CityConfig, now: number): Promise<SeedResult> {
  const result: SeedResult = {
    city: city.name,
    inCity: 0,
    seeded: 0,
    skipped: { noWebsite: 0, nonOwnSite: 0, hasSource: 0, alreadyCandidate: 0 },
  };
  const withSource = new Set((await listSources(db, { enabled: true })).map((source) => source.venueId));
  const linked = new Set(
    (await listCandidates(db)).map((candidate: Candidate) => candidate.matchedVenueId).filter(Boolean),
  );
  for (const venue of await listVenues(db)) {
    if (!inBbox(venue, city.bbox)) continue;
    result.inCity++;
    if (!venue.website) {
      result.skipped.noWebsite++;
      continue;
    }
    if (isNonOwnSite(venue.website) || isTicketingUrl(venue.website)) {
      result.skipped.nonOwnSite++;
      continue;
    }
    if (withSource.has(venue.id)) {
      result.skipped.hasSource++;
      continue;
    }
    if (linked.has(venue.id)) {
      result.skipped.alreadyCandidate++;
      continue;
    }
    const candidate = await insertCandidate(
      db,
      {
        name: venue.name,
        address: venue.address,
        city: city.name,
        lat: venue.lat,
        lng: venue.lng,
        website: venue.website,
        primaryPlaceId: venue.googlePlaceId,
        discoveredFrom: "manual",
        evidence: { seededFrom: "venue_snapshot", venueId: venue.id },
        status: "resolved",
        timezone: venue.timezone ?? city.timezone,
      },
      now,
    );
    await updateCandidate(db, candidate.id, { matchedVenueId: venue.id, statusReason: "seeded_known_venue" }, now);
    result.seeded++;
  }
  return result;
}
