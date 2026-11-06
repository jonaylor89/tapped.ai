/**
 * Venue identity resolution, including the "one venue, many Google place ids" problem.
 *
 * Google often returns several place ids for one real venue: the business (night_club / bar / live_music_venue),
 * the building (premise), the street address and broader areas. Rules implemented here:
 *
 * 1. Pure geocode results (premise, subpremise, street_address, route, locality, neighborhood, postal_code,
 *    political, plus_code, ...) are never identities. Point-like ones (premise/subpremise/street_address) are kept
 *    as aliases of the single establishment cluster they sit on; area-like ones are discarded.
 * 2. Establishments cluster when they are within ~75 m AND their names are the "same" (token-set similarity of
 *    distinctive words). A shared registrable website domain only widens the distance allowance; it never merges
 *    on its own, and two different websites block a merge. Domains are hints, not identities.
 * 3. The canonical place id of a cluster is the most venue-like establishment (live_music_venue / concert_hall /
 *    performing_arts_theater / comedy_club > night_club > bar > restaurant > other).
 * 4. Every member id is written to venue_place_ids, so any of them later resolves to the same venue/candidate.
 * 5. Similar-but-different names nearby ("The Hi-Fi" vs "Hi-Fi Annex"), or one place id claimed by differently
 *    named venues, become `needs_review`. Nothing is ever auto-merged on doubt.
 */
import {
  all,
  type Db,
  getCandidate,
  getVenue,
  insertCandidate,
  listCandidates,
  listPlaceAliases,
  listSources,
  listVenues,
  normalizeName,
  one,
  resolvePlaceId,
  transaction,
  updateCandidate,
  upsertPlaceAlias,
} from "../db.js";
import { isTicketingUrl } from "../denylist.js";
import type { BoundingBox, Candidate, DiscoveryFeed, PlaceResult, Venue } from "../types.js";
import { distanceOrNull, inBbox } from "./geo.js";
import { compareNames, type NameRelation } from "./names.js";
import { identityDomain } from "./website.js";

// ---------------------------------------------------------------------------------------------------------------------
// Place types
// ---------------------------------------------------------------------------------------------------------------------

/** Google types that describe a location, not a business. Never used as a venue identity. */
export const GEOCODE_TYPES: ReadonlySet<string> = new Set([
  "geocode",
  "premise",
  "subpremise",
  "street_address",
  "street_number",
  "route",
  "intersection",
  "locality",
  "sublocality",
  "sublocality_level_1",
  "sublocality_level_2",
  "sublocality_level_3",
  "sublocality_level_4",
  "sublocality_level_5",
  "neighborhood",
  "postal_code",
  "postal_code_prefix",
  "postal_code_suffix",
  "postal_town",
  "political",
  "plus_code",
  "colloquial_area",
  "country",
  "administrative_area_level_1",
  "administrative_area_level_2",
  "administrative_area_level_3",
  "administrative_area_level_4",
  "administrative_area_level_5",
  "administrative_area_level_6",
  "administrative_area_level_7",
  "floor",
  "room",
  "natural_feature",
]);

/** Geocode types that denote a point at the venue (kept as aliases when unambiguous). Areas are discarded. */
export const POINT_GEOCODE_TYPES: ReadonlySet<string> = new Set(["premise", "subpremise", "street_address"]);

/** Types that say nothing about what the business is. */
export const GENERIC_PLACE_TYPES: ReadonlySet<string> = new Set([
  "point_of_interest",
  "establishment",
  "tourist_attraction",
  "food",
  "store",
]);

const TYPE_SCORES: Record<string, number> = {
  live_music_venue: 100,
  concert_hall: 100,
  performing_arts_theater: 95,
  comedy_club: 95,
  amphitheatre: 90,
  opera_house: 90,
  philharmonic_hall: 90,
  auditorium: 85,
  dance_hall: 85,
  event_venue: 80,
  night_club: 80,
  karaoke: 70,
  cultural_center: 65,
  arts_center: 65,
  bar: 60,
  pub: 60,
  wine_bar: 60,
  cocktail_bar: 60,
  brewery: 55,
  brewpub: 55,
  beer_garden: 55,
  bar_and_grill: 55,
  restaurant: 40,
  cafe: 35,
  coffee_shop: 35,
  church: 30,
};

/** True when the place is a location (building, address, area) rather than a business. */
export function isGeocodeOnly(place: Pick<PlaceResult, "types" | "primaryType">): boolean {
  if (place.primaryType && GEOCODE_TYPES.has(place.primaryType)) return true;
  const hasGeocode = place.types.some((type) => GEOCODE_TYPES.has(type));
  const hasSpecific = place.types.some((type) => !GEOCODE_TYPES.has(type) && !GENERIC_PLACE_TYPES.has(type));
  return hasGeocode && !hasSpecific;
}

/** Higher = more venue-like. Used to pick a cluster's canonical id. Geocode-only places score 0. */
export function establishmentScore(place: Pick<PlaceResult, "types" | "primaryType">): number {
  if (isGeocodeOnly(place)) return 0;
  let best = 10;
  for (const type of place.types) {
    if (GEOCODE_TYPES.has(type)) continue;
    const score = TYPE_SCORES[type] ?? (GENERIC_PLACE_TYPES.has(type) ? 10 : 20);
    best = Math.max(best, score);
  }
  if (place.primaryType && TYPE_SCORES[place.primaryType] !== undefined) {
    best = Math.max(best, (TYPE_SCORES[place.primaryType] ?? 0) + 2);
  }
  return best;
}

// ---------------------------------------------------------------------------------------------------------------------
// Clustering
// ---------------------------------------------------------------------------------------------------------------------

export const DEFAULT_CLUSTER_RADIUS_M = 75;
/** Same-name establishments sharing a website domain may sit this many radii apart (big sites, pin drift). */
const SAME_DOMAIN_RADIUS_FACTOR = 3;

export interface ClusterReview {
  reason: "nearby_similar_name" | "same_name_different_website";
  placeId: string;
  displayName: string;
  distanceMeters: number | null;
}

export interface PlaceCluster {
  canonical: PlaceResult;
  /** Establishment members, canonical first. */
  members: PlaceResult[];
  /** Point geocode results (premise / street_address) attached as aliases. */
  geocodeAliases: PlaceResult[];
  /** Nearby places that look related but were not merged; the cluster must go to human review. */
  review: ClusterReview[];
}

export interface ClusterOptions {
  radiusMeters?: number;
  /** Words ignored when comparing names, e.g. the city name. */
  extraStopWords?: Iterable<string>;
}

export interface ClusterResult {
  clusters: PlaceCluster[];
  /** Geocode results that were discarded (areas, or ambiguous points between several venues). */
  discardedGeocode: PlaceResult[];
}

/** Identity-relevant website part; null for ticketing, social and link-in-bio URLs (see website.ts). */
function websiteDomain(url: string | null | undefined): string | null {
  return identityDomain(url);
}

export type PairDecision = "merge" | "review_same_name_different_website" | "review_similar_name" | "none";

/**
 * The one rule deciding whether two establishments are the same venue, shared by in-batch clustering and
 * cross-batch candidate matching so the outcome never depends on arrival order:
 * - "same" names merge within `radius`, or within `radius * SAME_DOMAIN_RADIUS_FACTOR` when both list the same
 *   identifying website; two different identifying websites never merge (review instead, within `radius`)
 * - "similar" names within `radius` go to review
 */
export function decidePair(
  relation: NameRelation,
  distance: number,
  websiteA: string | null | undefined,
  websiteB: string | null | undefined,
  radius: number,
): PairDecision {
  const domainA = websiteDomain(websiteA);
  const domainB = websiteDomain(websiteB);
  const sameDomain = domainA !== null && domainA === domainB;
  const conflict = domainA !== null && domainB !== null && domainA !== domainB;
  if (relation === "same" && !conflict && distance <= (sameDomain ? radius * SAME_DOMAIN_RADIUS_FACTOR : radius))
    return "merge";
  if (distance > radius || relation === "different") return "none";
  return relation === "same" ? "review_same_name_different_website" : "review_similar_name";
}

function compareCanonical(a: PlaceResult, b: PlaceResult): number {
  return (
    establishmentScore(b) - establishmentScore(a) ||
    Number(Boolean(b.websiteUri)) - Number(Boolean(a.websiteUri)) ||
    b.types.length - a.types.length ||
    a.placeId.localeCompare(b.placeId)
  );
}

/** Groups place results that refer to the same real venue. Input order does not matter. */
export function clusterPlaces(places: PlaceResult[], options: ClusterOptions = {}): ClusterResult {
  const radius = options.radiusMeters ?? DEFAULT_CLUSTER_RADIUS_M;
  const stop = options.extraStopWords ? [...options.extraStopWords] : undefined;
  const unique = new Map<string, PlaceResult>();
  for (const place of places) if (!unique.has(place.placeId)) unique.set(place.placeId, place);
  const establishments = [...unique.values()].filter((place) => !isGeocodeOnly(place)).sort(compareCanonical);
  const geocodes = [...unique.values()].filter((place) => isGeocodeOnly(place));

  const parent = establishments.map((_, i) => i);
  const find = (i: number): number => {
    while (parent[i] !== i) {
      parent[i] = parent[parent[i] as number] as number;
      i = parent[i] as number;
    }
    return i;
  };
  const pendingReview: { a: number; b: number; reason: ClusterReview["reason"]; distance: number | null }[] = [];

  for (let i = 0; i < establishments.length; i++) {
    for (let j = i + 1; j < establishments.length; j++) {
      const a = establishments[i] as PlaceResult;
      const b = establishments[j] as PlaceResult;
      const distance = distanceOrNull(a, b);
      if (distance == null) continue;
      if (distance > radius * SAME_DOMAIN_RADIUS_FACTOR) continue;
      const relation: NameRelation = compareNames(a.displayName, b.displayName, stop);
      const decision = decidePair(relation, distance, a.websiteUri, b.websiteUri, radius);
      if (decision === "merge") {
        const ra = find(i);
        const rb = find(j);
        if (ra !== rb) parent[Math.max(ra, rb)] = Math.min(ra, rb);
      } else if (decision !== "none") {
        pendingReview.push({
          a: i,
          b: j,
          reason:
            decision === "review_same_name_different_website" ? "same_name_different_website" : "nearby_similar_name",
          distance,
        });
      }
    }
  }

  const byRoot = new Map<number, PlaceCluster>();
  establishments.forEach((place, i) => {
    const root = find(i);
    const cluster = byRoot.get(root);
    if (cluster) cluster.members.push(place);
    else byRoot.set(root, { canonical: place, members: [place], geocodeAliases: [], review: [] });
  });
  for (const cluster of byRoot.values()) {
    cluster.members.sort(compareCanonical);
    cluster.canonical = cluster.members[0] as PlaceResult;
  }
  for (const pair of pendingReview) {
    const ra = find(pair.a);
    const rb = find(pair.b);
    if (ra === rb) continue;
    const a = establishments[pair.a] as PlaceResult;
    const b = establishments[pair.b] as PlaceResult;
    byRoot.get(ra)?.review.push({
      reason: pair.reason,
      placeId: b.placeId,
      displayName: b.displayName,
      distanceMeters: pair.distance,
    });
    byRoot.get(rb)?.review.push({
      reason: pair.reason,
      placeId: a.placeId,
      displayName: a.displayName,
      distanceMeters: pair.distance,
    });
  }

  const clusters = [...byRoot.values()];
  const discardedGeocode: PlaceResult[] = [];
  for (const geo of geocodes) {
    if (!geo.types.some((type) => POINT_GEOCODE_TYPES.has(type)) || geo.lat == null || geo.lng == null) {
      discardedGeocode.push(geo);
      continue;
    }
    let near = clusters.filter((cluster) =>
      cluster.members.some((member) => {
        const distance = distanceOrNull(member, geo);
        return distance != null && distance <= radius;
      }),
    );
    if (near.length > 1) {
      // Several venues in one building/address: attach only if the geocode result's own name singles one out
      // (a premise named after the venue). Otherwise the building id belongs to nobody.
      near = near.filter((cluster) => compareNames(cluster.canonical.displayName, geo.displayName, stop) === "same");
    }
    const target = near.length === 1 ? near[0] : undefined;
    if (target) target.geocodeAliases.push(geo);
    else discardedGeocode.push(geo);
  }
  return { clusters, discardedGeocode };
}

// ---------------------------------------------------------------------------------------------------------------------
// Identity matching against local state (production venue snapshot, aliases, candidates)
// ---------------------------------------------------------------------------------------------------------------------

export interface ProbePlace {
  placeId: string;
  types: string[];
  displayName: string | null;
  lat: number | null;
  lng: number | null;
  /** True for the cluster's canonical (establishment) id. */
  canonical: boolean;
}

/** Everything a feed knows about one venue, before it is matched to local state. */
export interface VenueProbe {
  name: string;
  address?: string | null;
  city?: string | null;
  lat?: number | null;
  lng?: number | null;
  website?: string | null;
  timezone?: string | null;
  places?: ProbePlace[];
  discoveredFrom: DiscoveryFeed;
  /** One observation appended to the candidate's evidence log (feed-specific facts). */
  observation?: Record<string, unknown>;
  /** Dedupe key of the observation (e.g. "google:<placeId>", "osm:node/1"), so re-runs do not duplicate it. */
  observationKey?: string;
  /** Area constraint for name-only matching when the probe has no coordinates. */
  area?: BoundingBox | null;
  /** Feed-level reason to route to review (e.g. cluster had a similar-named neighbor). */
  reviewReason?: string | null;
  reviewDetails?: unknown;
}

export interface IdentityOptions {
  /** Proximity for candidate/alias clustering. Default 75 m. */
  radiusMeters?: number;
  /** Proximity for matching production venues (their coordinates are often geocoded addresses). Default 150 m. */
  venueRadiusMeters?: number;
  /** Candidate to ignore (when re-resolving an existing candidate). */
  excludeCandidateId?: number;
  extraStopWords?: Iterable<string>;
  now?: number;
}

export type MatchVia = "place_id" | "geo_name" | "area_name";

export type IdentityMatch =
  | { kind: "venue"; venueId: string; candidateId: number | null; via: MatchVia }
  | { kind: "candidate"; candidateId: number; via: MatchVia }
  | { kind: "conflict"; reason: string; venueIds: string[]; candidateIds: number[]; placeIds: string[] }
  | { kind: "none" };

interface Owner {
  venueId: string | null;
  candidateId: number | null;
  name: string;
}

async function venuesWithPlaceId(db: Db, placeId: string): Promise<Venue[]> {
  const rows = await all(db, "SELECT * FROM venues WHERE google_place_id=? ORDER BY id", placeId);
  const venues: Venue[] = [];
  for (const row of rows) {
    const venue = await getVenue(db, String(row.id));
    if (venue) venues.push(venue);
  }
  return venues;
}

async function candidateForVenue(db: Db, venueId: string, excludeId?: number): Promise<Candidate | null> {
  const row = await one(
    db,
    "SELECT id FROM venue_candidates WHERE matched_venue_id=? AND id<>? ORDER BY id LIMIT 1",
    venueId,
    excludeId ?? -1,
  );
  return row ? await getCandidate(db, Number(row.id)) : null;
}

function isDuplicateTombstone(candidate: Candidate): boolean {
  return candidate.status === "rejected" && (candidate.statusReason ?? "").startsWith("duplicate_of:");
}

async function placeOwners(db: Db, placeId: string, excludeCandidateId: number | undefined): Promise<Owner[]> {
  const owners = new Map<string, Owner>();
  const alias = await resolvePlaceId(db, placeId);
  if (alias) {
    if (alias.venueId != null) {
      const venue = await getVenue(db, alias.venueId);
      const candidateId = alias.candidateId !== excludeCandidateId ? alias.candidateId : null;
      owners.set(`v:${alias.venueId}`, {
        venueId: alias.venueId,
        candidateId,
        name: venue?.name ?? alias.displayName ?? "",
      });
    } else if (alias.candidateId != null && alias.candidateId !== excludeCandidateId) {
      const candidate = await getCandidate(db, alias.candidateId);
      if (candidate && !isDuplicateTombstone(candidate)) {
        owners.set(`c:${candidate.id}`, { venueId: null, candidateId: candidate.id, name: candidate.name });
      }
    }
  }
  for (const venue of await venuesWithPlaceId(db, placeId)) {
    if (!owners.has(`v:${venue.id}`))
      owners.set(`v:${venue.id}`, { venueId: venue.id, candidateId: null, name: venue.name });
  }
  return [...owners.values()];
}

/** True when the stored alias for this id is a geocode result (building / address). */
async function isGeocodeAlias(db: Db, placeId: string): Promise<boolean> {
  const alias = await resolvePlaceId(db, placeId);
  return alias !== null && alias.types.length > 0 && isGeocodeOnly({ types: alias.types, primaryType: null });
}

function websitesConflict(a: string | null | undefined, b: string | null | undefined): boolean {
  const da = websiteDomain(a);
  const dbm = websiteDomain(b);
  return da !== null && dbm !== null && da !== dbm;
}

function addressMentionsCity(address: string | null, city: string | null | undefined): boolean {
  if (!address || !city) return false;
  return normalizeName(address).includes(normalizeName(city));
}

/**
 * Finds what local entity a probe refers to: by any known place id alias first, then by proximity + name, then
 * (no coordinates) by name within the same city/area. Website domains alone never match.
 */
export async function matchIdentity(db: Db, probe: VenueProbe, options: IdentityOptions = {}): Promise<IdentityMatch> {
  const radius = options.radiusMeters ?? DEFAULT_CLUSTER_RADIUS_M;
  const venueRadius = options.venueRadiusMeters ?? 150;
  const stop = [...(options.extraStopWords ?? []), ...(probe.city ? [probe.city] : [])];
  const exclude = options.excludeCandidateId;
  const placeIds = (probe.places ?? []).map((place) => place.placeId);
  // Building / address ids (premise, street_address) are kept as aliases but never decide identity: one building
  // holds several businesses, and the first venue found there must not claim every later one.
  const identityPlaceIds: string[] = [];
  for (const place of probe.places ?? []) {
    if (isGeocodeOnly({ types: place.types, primaryType: null })) continue;
    if (!(await isGeocodeAlias(db, place.placeId))) identityPlaceIds.push(place.placeId);
  }

  // 1. Place-id aliases (establishment ids only).
  const owners = new Map<string, Owner>();
  for (const placeId of identityPlaceIds) {
    for (const owner of await placeOwners(db, placeId, exclude)) {
      owners.set(owner.venueId != null ? `v:${owner.venueId}` : `c:${owner.candidateId}`, owner);
    }
  }
  if (owners.size) {
    const list = [...owners.values()];
    const mismatched = list.filter((owner) => compareNames(owner.name, probe.name, stop) !== "same");
    const venueIds = [...new Set(list.map((owner) => owner.venueId).filter((id): id is string => id != null))];
    const candidateIds = [...new Set(list.map((owner) => owner.candidateId).filter((id): id is number => id != null))];
    if (mismatched.length) {
      return { kind: "conflict", reason: "same_place_id_different_name", venueIds, candidateIds, placeIds };
    }
    if (venueIds.length > 1)
      return { kind: "conflict", reason: "place_ids_span_venues", venueIds, candidateIds, placeIds };
    if (venueIds.length === 1) {
      const venueId = venueIds[0] as string;
      const candidateId =
        list.find((owner) => owner.venueId === venueId && owner.candidateId != null)?.candidateId ??
        (candidateIds.length === 1 ? (candidateIds[0] as number) : null);
      return { kind: "venue", venueId, candidateId, via: "place_id" };
    }
    if (candidateIds.length > 1) {
      return { kind: "conflict", reason: "place_ids_span_candidates", venueIds, candidateIds, placeIds };
    }
    return { kind: "candidate", candidateId: candidateIds[0] as number, via: "place_id" };
  }

  const point = { lat: probe.lat ?? null, lng: probe.lng ?? null };
  const hasPoint = point.lat != null && point.lng != null;
  const venues = await listVenues(db);

  // 2. Proximity + name.
  if (hasPoint) {
    const same: Venue[] = [];
    const similar: Venue[] = [];
    for (const venue of venues) {
      const distance = distanceOrNull(point, venue);
      if (distance == null || distance > venueRadius) continue;
      const relation = compareNames(venue.name, probe.name, stop);
      if (relation === "same") same.push(venue);
      else if (relation === "similar" && distance <= radius) similar.push(venue);
    }
    if (same.length > 1) {
      return {
        kind: "conflict",
        reason: "ambiguous_venue_match",
        venueIds: same.map((v) => v.id),
        candidateIds: [],
        placeIds,
      };
    }
    const venue = same[0];
    if (venue) {
      if (websitesConflict(venue.website, probe.website)) {
        return {
          kind: "conflict",
          reason: "same_name_different_website",
          venueIds: [venue.id],
          candidateIds: [],
          placeIds,
        };
      }
      return {
        kind: "venue",
        venueId: venue.id,
        candidateId: (await candidateForVenue(db, venue.id, exclude))?.id ?? null,
        via: "geo_name",
      };
    }

    // Same rule as in-batch clustering (decidePair): a same-named candidate on the same website may sit up to
    // radius * SAME_DOMAIN_RADIUS_FACTOR away, so the result does not depend on which batch each id arrived in.
    const nearCandidates = (
      await candidatesNearPoint(db, point.lat as number, point.lng as number, radius * SAME_DOMAIN_RADIUS_FACTOR)
    ).filter((candidate) => candidate.id !== exclude && !isDuplicateTombstone(candidate));
    const decided = nearCandidates.map((c) => ({
      c,
      decision: decidePair(
        compareNames(c.name, probe.name, stop),
        distanceOrNull(point, c) ?? Number.POSITIVE_INFINITY,
        c.website,
        probe.website,
        radius,
      ),
    }));
    const sameCandidates = decided
      .filter((d) => d.decision === "merge" || d.decision === "review_same_name_different_website")
      .map((d) => d.c);
    const similarCandidates = decided.filter((d) => d.decision === "review_similar_name").map((d) => d.c);
    if (sameCandidates.length > 1) {
      return {
        kind: "conflict",
        reason: "ambiguous_candidate_match",
        venueIds: [],
        candidateIds: sameCandidates.map((c) => c.id),
        placeIds,
      };
    }
    const candidate = sameCandidates[0];
    if (candidate) {
      if (websitesConflict(candidate.website, probe.website)) {
        return {
          kind: "conflict",
          reason: "same_name_different_website",
          venueIds: [],
          candidateIds: [candidate.id],
          placeIds,
        };
      }
      if (candidate.matchedVenueId) {
        return { kind: "venue", venueId: candidate.matchedVenueId, candidateId: candidate.id, via: "geo_name" };
      }
      return { kind: "candidate", candidateId: candidate.id, via: "geo_name" };
    }
    if (similar.length || similarCandidates.length) {
      return {
        kind: "conflict",
        reason: "nearby_similar_name",
        venueIds: similar.map((v) => v.id),
        candidateIds: similarCandidates.map((c) => c.id),
        placeIds,
      };
    }
    return { kind: "none" };
  }

  // 3. No coordinates (listing / some OSM data): exact-name match restricted to the same city or area.
  const inArea = (entity: { lat: number | null; lng: number | null; address: string | null; city?: string | null }) =>
    (probe.area ? inBbox(entity, probe.area) : false) ||
    addressMentionsCity(entity.address, probe.city) ||
    (probe.city != null && entity.city != null && normalizeName(entity.city) === normalizeName(probe.city));
  if (!probe.area && !probe.city) return { kind: "none" };
  const sameVenues = venues.filter((venue) => inArea(venue) && compareNames(venue.name, probe.name, stop) === "same");
  if (sameVenues.length > 1) {
    return {
      kind: "conflict",
      reason: "ambiguous_venue_match",
      venueIds: sameVenues.map((v) => v.id),
      candidateIds: [],
      placeIds,
    };
  }
  if (sameVenues[0]) {
    const venueId = sameVenues[0].id;
    return {
      kind: "venue",
      venueId,
      candidateId: (await candidateForVenue(db, venueId, exclude))?.id ?? null,
      via: "area_name",
    };
  }
  const sameCandidates = (await listCandidates(db)).filter(
    (candidate) =>
      candidate.id !== exclude &&
      !isDuplicateTombstone(candidate) &&
      inArea(candidate) &&
      compareNames(candidate.name, probe.name, stop) === "same",
  );
  if (sameCandidates.length > 1) {
    return {
      kind: "conflict",
      reason: "ambiguous_candidate_match",
      venueIds: [],
      candidateIds: sameCandidates.map((c) => c.id),
      placeIds,
    };
  }
  const only = sameCandidates[0];
  if (only) {
    if (only.matchedVenueId)
      return { kind: "venue", venueId: only.matchedVenueId, candidateId: only.id, via: "area_name" };
    return { kind: "candidate", candidateId: only.id, via: "area_name" };
  }
  return { kind: "none" };
}

async function candidatesNearPoint(db: Db, lat: number, lng: number, meters: number): Promise<Candidate[]> {
  const dLat = meters / 111_320;
  const dLng = meters / (111_320 * Math.max(Math.cos((lat * Math.PI) / 180), 0.01));
  const rows = await all(
    db,
    "SELECT id FROM venue_candidates WHERE lat BETWEEN ? AND ? AND lng BETWEEN ? AND ? ORDER BY id",
    lat - dLat,
    lat + dLat,
    lng - dLng,
    lng + dLng,
  );
  const near: Candidate[] = [];
  for (const row of rows) {
    const candidate = await getCandidate(db, Number(row.id));
    if (!candidate) continue;
    const distance = distanceOrNull({ lat, lng }, candidate);
    if (distance != null && distance <= meters) near.push(candidate);
  }
  return near;
}

// ---------------------------------------------------------------------------------------------------------------------
// Writing probes
// ---------------------------------------------------------------------------------------------------------------------

export type RecordKind = "created" | "merged" | "matched_venue" | "needs_review";

export interface RecordOutcome {
  kind: RecordKind;
  candidate: Candidate;
  match: IdentityMatch;
}

const MAX_OBSERVATIONS = 25;

/** Appends a feed observation to a candidate's evidence log (deduped by key, capped). */
export function appendObservation(
  evidence: Record<string, unknown>,
  feed: DiscoveryFeed,
  key: string | undefined,
  data: Record<string, unknown> | undefined,
  at: number,
): Record<string, unknown> {
  const observations = Array.isArray(evidence.observations)
    ? (evidence.observations as Record<string, unknown>[]).slice()
    : [];
  const entry = { feed, key: key ?? null, at, ...(data ?? {}) };
  const index = key ? observations.findIndex((obs) => obs.key === key) : -1;
  if (index >= 0) observations[index] = entry;
  else observations.push(entry);
  const feeds = new Set<string>(Array.isArray(evidence.feeds) ? (evidence.feeds as string[]) : []);
  feeds.add(feed);
  return { ...evidence, feeds: [...feeds].sort(), observations: observations.slice(-MAX_OBSERVATIONS) };
}

function cleanWebsite(website: string | null | undefined): string | null {
  if (!website) return null;
  return isTicketingUrl(website) ? null : website;
}

async function venueHasEnabledSource(db: Db, venueId: string): Promise<boolean> {
  return (await listSources(db, { venueId })).some((source) => source.enabled);
}

async function writeAliases(
  db: Db,
  places: ProbePlace[] | undefined,
  owner: { venueId: string | null; candidateId: number | null },
  now: number,
): Promise<void> {
  if (!places?.length) return;
  const existing = [
    ...(owner.venueId ? await listPlaceAliases(db, { venueId: owner.venueId }) : []),
    ...(owner.candidateId != null ? await listPlaceAliases(db, { candidateId: owner.candidateId }) : []),
  ];
  const currentCanonical = existing.find((alias) => alias.isCanonical);
  const proposed = places.find((place) => place.canonical);
  const replaceCanonical =
    proposed !== undefined &&
    (!currentCanonical ||
      currentCanonical.placeId === proposed.placeId ||
      establishmentScore({ types: proposed.types, primaryType: null }) >
        establishmentScore({ types: currentCanonical.types, primaryType: null }));
  for (const place of places) {
    const prior = await resolvePlaceId(db, place.placeId);
    // Never steal an id owned by another venue or candidate.
    const otherVenue = prior?.venueId != null && prior.venueId !== owner.venueId;
    const otherCandidate =
      prior?.candidateId != null && owner.candidateId != null && prior.candidateId !== owner.candidateId;
    if (otherVenue || otherCandidate) continue;
    const isCanonical = place.canonical ? replaceCanonical : (prior?.isCanonical ?? false) && !replaceCanonical;
    await upsertPlaceAlias(
      db,
      {
        placeId: place.placeId,
        venueId: owner.venueId ?? prior?.venueId ?? null,
        candidateId: owner.candidateId ?? prior?.candidateId ?? null,
        isCanonical,
        types: place.types,
        displayName: place.displayName,
        lat: place.lat,
        lng: place.lng,
      },
      now,
    );
  }
}

function canonicalPlaceId(probe: VenueProbe): string | null {
  return probe.places?.find((place) => place.canonical)?.placeId ?? null;
}

async function mergeInto(
  db: Db,
  candidate: Candidate,
  probe: VenueProbe,
  now: number,
  extra: Partial<Candidate> = {},
): Promise<Candidate> {
  const website = cleanWebsite(probe.website);
  const evidence = appendObservation(
    candidate.evidence,
    probe.discoveredFrom,
    probe.observationKey,
    probe.observation,
    now,
  );
  const canonical = canonicalPlaceId(probe);
  const needsReview = probe.reviewReason && (candidate.status === "new" || candidate.status === "resolved");
  return updateCandidate(
    db,
    candidate.id,
    {
      address: candidate.address ?? probe.address ?? null,
      city: candidate.city ?? probe.city ?? null,
      lat: candidate.lat ?? probe.lat ?? null,
      lng: candidate.lng ?? probe.lng ?? null,
      website: candidate.website ?? website,
      timezone: candidate.timezone ?? probe.timezone ?? null,
      primaryPlaceId: candidate.primaryPlaceId ?? canonical,
      evidence: needsReview ? { ...evidence, review: probe.reviewDetails ?? null } : evidence,
      ...(needsReview ? { status: "needs_review" as const, statusReason: probe.reviewReason ?? null } : {}),
      ...extra,
    },
    now,
  );
}

async function findOpenReview(db: Db, probe: VenueProbe): Promise<Candidate | null> {
  const canonical = canonicalPlaceId(probe);
  const rows = await all(
    db,
    `SELECT id FROM venue_candidates WHERE status='needs_review'
       AND (normalized_name=? OR (primary_place_id IS NOT NULL AND primary_place_id=?)) ORDER BY id`,
    normalizeName(probe.name),
    canonical ?? "",
  );
  for (const row of rows) {
    const candidate = await getCandidate(db, Number(row.id));
    if (!candidate) continue;
    if (canonical && candidate.primaryPlaceId === canonical) return candidate;
    const distance = distanceOrNull(candidate, { lat: probe.lat ?? null, lng: probe.lng ?? null });
    if (distance != null ? distance <= 150 : candidate.city === (probe.city ?? null)) return candidate;
  }
  return null;
}

/**
 * Matches a probe and writes the outcome: merges into an existing candidate, links to an existing production venue
 * (still a candidate, so its own-site source can be found; rejected when the venue already has a source), creates a
 * new candidate, or parks it as `needs_review`. Place-id aliases are written for every non-conflicting outcome.
 */
export async function recordProbe(db: Db, probe: VenueProbe, options: IdentityOptions = {}): Promise<RecordOutcome> {
  const now = options.now ?? Date.now();
  return transaction(db, async () => {
    const match = await matchIdentity(db, probe, options);
    switch (match.kind) {
      case "venue": {
        const existing = match.candidateId != null ? await getCandidate(db, match.candidateId) : null;
        let candidate: Candidate;
        if (existing) {
          candidate = await mergeInto(db, existing, probe, now, { matchedVenueId: match.venueId });
        } else {
          const hasSource = await venueHasEnabledSource(db, match.venueId);
          candidate = await insertCandidate(
            db,
            {
              name: probe.name,
              address: probe.address ?? null,
              city: probe.city ?? null,
              lat: probe.lat ?? null,
              lng: probe.lng ?? null,
              website: cleanWebsite(probe.website) ?? (await getVenue(db, match.venueId))?.website ?? null,
              primaryPlaceId: canonicalPlaceId(probe),
              discoveredFrom: probe.discoveredFrom,
              evidence: appendObservation({}, probe.discoveredFrom, probe.observationKey, probe.observation, now),
              status: hasSource ? "rejected" : "resolved",
              timezone: probe.timezone ?? (await getVenue(db, match.venueId))?.timezone ?? null,
            },
            now,
          );
          candidate = await updateCandidate(
            db,
            candidate.id,
            {
              matchedVenueId: match.venueId,
              statusReason: hasSource ? "venue_has_source" : `matched_venue:${match.via}`,
            },
            now,
          );
        }
        await writeAliases(db, probe.places, { venueId: match.venueId, candidateId: candidate.id }, now);
        return { kind: "matched_venue", candidate, match };
      }
      case "candidate": {
        const existing = (await getCandidate(db, match.candidateId)) as Candidate;
        const candidate = await mergeInto(db, existing, probe, now);
        await writeAliases(db, probe.places, { venueId: candidate.matchedVenueId, candidateId: candidate.id }, now);
        return { kind: "merged", candidate, match };
      }
      case "conflict": {
        const conflict = {
          reason: match.reason,
          venueIds: match.venueIds,
          candidateIds: match.candidateIds,
          placeIds: match.placeIds,
          probeName: probe.name,
        };
        const open = await findOpenReview(db, probe);
        if (open) {
          const candidate = await mergeInto(db, open, probe, now);
          return {
            kind: "needs_review",
            candidate: await updateCandidate(db, candidate.id, { evidence: { ...candidate.evidence, conflict } }, now),
            match,
          };
        }
        const candidate = await insertCandidate(
          db,
          {
            name: probe.name,
            address: probe.address ?? null,
            city: probe.city ?? null,
            lat: probe.lat ?? null,
            lng: probe.lng ?? null,
            website: cleanWebsite(probe.website),
            primaryPlaceId: canonicalPlaceId(probe),
            discoveredFrom: probe.discoveredFrom,
            evidence: {
              ...appendObservation({}, probe.discoveredFrom, probe.observationKey, probe.observation, now),
              conflict,
            },
            status: "needs_review",
            timezone: probe.timezone ?? null,
          },
          now,
        );
        // Aliases are deliberately not written: the conflicting ids stay with their current owners.
        return {
          kind: "needs_review",
          candidate: await updateCandidate(db, candidate.id, { statusReason: match.reason }, now),
          match,
        };
      }
      case "none": {
        let candidate = await insertCandidate(
          db,
          {
            name: probe.name,
            address: probe.address ?? null,
            city: probe.city ?? null,
            lat: probe.lat ?? null,
            lng: probe.lng ?? null,
            website: cleanWebsite(probe.website),
            primaryPlaceId: canonicalPlaceId(probe),
            discoveredFrom: probe.discoveredFrom,
            evidence: {
              ...appendObservation({}, probe.discoveredFrom, probe.observationKey, probe.observation, now),
              ...(probe.reviewReason ? { review: probe.reviewDetails ?? null } : {}),
            },
            status: probe.reviewReason ? "needs_review" : "resolved",
            timezone: probe.timezone ?? null,
          },
          now,
        );
        candidate = await updateCandidate(db, candidate.id, { statusReason: probe.reviewReason ?? "new_venue" }, now);
        await writeAliases(db, probe.places, { venueId: null, candidateId: candidate.id }, now);
        return { kind: probe.reviewReason ? "needs_review" : "created", candidate, match };
      }
    }
  });
}

// ---------------------------------------------------------------------------------------------------------------------
// Places ingestion
// ---------------------------------------------------------------------------------------------------------------------

export interface PlacesIngestContext extends IdentityOptions {
  city?: string | null;
  timezone?: string | null;
  area?: BoundingBox | null;
  /** Free-text provenance stored on each observation (e.g. the text query and cell id). */
  provenance?: Record<string, unknown>;
}

export interface IngestSummary {
  places: number;
  closed: number;
  clusters: number;
  discardedGeocode: number;
  created: number;
  merged: number;
  matchedVenue: number;
  needsReview: number;
  candidateIds: number[];
}

function toProbePlace(place: PlaceResult, canonical: boolean): ProbePlace {
  return {
    placeId: place.placeId,
    types: place.types,
    displayName: place.displayName,
    lat: place.lat,
    lng: place.lng,
    canonical,
  };
}

/** Builds the probe for one place cluster. */
export function probeFromCluster(cluster: PlaceCluster, context: PlacesIngestContext = {}): VenueProbe {
  const { canonical } = cluster;
  const website =
    cleanWebsite(canonical.websiteUri) ??
    cluster.members.map((member) => cleanWebsite(member.websiteUri)).find((uri) => uri != null) ??
    null;
  const places = [
    ...cluster.members.map((member) => toProbePlace(member, member.placeId === canonical.placeId)),
    ...cluster.geocodeAliases.map((geo) => toProbePlace(geo, false)),
  ];
  return {
    name: canonical.displayName,
    address: canonical.formattedAddress,
    city: context.city ?? null,
    lat: canonical.lat,
    lng: canonical.lng,
    website,
    timezone: context.timezone ?? null,
    places,
    discoveredFrom: "google_places",
    observationKey: `google:${canonical.placeId}`,
    observation: {
      placeId: canonical.placeId,
      primaryType: canonical.primaryType,
      types: canonical.types,
      memberPlaceIds: places.map((place) => place.placeId),
      businessStatus: canonical.businessStatus,
      ...(context.provenance ?? {}),
    },
    area: context.area ?? null,
    reviewReason: cluster.review.length ? (cluster.review[0]?.reason ?? null) : null,
    reviewDetails: cluster.review.length ? cluster.review : undefined,
  };
}

/** Clusters a batch of Places results and records each cluster. Permanently closed places are skipped. */
export async function ingestPlaces(
  db: Db,
  places: PlaceResult[],
  context: PlacesIngestContext = {},
): Promise<IngestSummary> {
  const open = places.filter((place) => place.businessStatus !== "CLOSED_PERMANENTLY");
  const stop = [...(context.extraStopWords ?? []), ...(context.city ? [context.city] : [])];
  const { clusters, discardedGeocode } = clusterPlaces(open, {
    radiusMeters: context.radiusMeters,
    extraStopWords: stop,
  });
  const summary: IngestSummary = {
    places: places.length,
    closed: places.length - open.length,
    clusters: clusters.length,
    discardedGeocode: discardedGeocode.length,
    created: 0,
    merged: 0,
    matchedVenue: 0,
    needsReview: 0,
    candidateIds: [],
  };
  for (const cluster of clusters) {
    const outcome = await recordProbe(db, probeFromCluster(cluster, context), context);
    summary.candidateIds.push(outcome.candidate.id);
    if (outcome.kind === "created") summary.created++;
    else if (outcome.kind === "merged") summary.merged++;
    else if (outcome.kind === "matched_venue") summary.matchedVenue++;
    else summary.needsReview++;
  }
  return summary;
}

// ---------------------------------------------------------------------------------------------------------------------
// Venue alias seeding and candidate re-resolution
// ---------------------------------------------------------------------------------------------------------------------

/**
 * Seeds venue_place_ids from the production snapshot's google_place_id column. An id claimed by several venues
 * (rooms in one building sharing the building's id) is NOT assigned to any of them and is reported instead.
 */
export async function syncVenuePlaceAliases(
  db: Db,
  now: number = Date.now(),
): Promise<{ assigned: number; shared: string[] }> {
  const byPlace = new Map<string, Venue[]>();
  for (const venue of await listVenues(db)) {
    if (!venue.googlePlaceId) continue;
    byPlace.set(venue.googlePlaceId, [...(byPlace.get(venue.googlePlaceId) ?? []), venue]);
  }
  let assigned = 0;
  const shared: string[] = [];
  await transaction(db, async () => {
    for (const [placeId, venues] of byPlace) {
      if (venues.length > 1) {
        shared.push(placeId);
        continue;
      }
      const venue = venues[0] as Venue;
      const prior = await resolvePlaceId(db, placeId);
      if (prior?.venueId === venue.id) continue;
      if (prior?.venueId != null) continue;
      if (prior?.candidateId != null) {
        const candidate = await getCandidate(db, prior.candidateId);
        if (!candidate || compareNames(candidate.name, venue.name) !== "same") continue;
      }
      const hasCanonical = (await listPlaceAliases(db, { venueId: venue.id })).some((alias) => alias.isCanonical);
      await upsertPlaceAlias(
        db,
        {
          placeId,
          venueId: venue.id,
          candidateId: prior?.candidateId ?? null,
          isCanonical: !hasCanonical,
          types: prior?.types ?? [],
          displayName: prior?.displayName ?? venue.name,
          lat: prior?.lat ?? venue.lat,
          lng: prior?.lng ?? venue.lng,
        },
        now,
      );
      assigned++;
    }
  });
  return { assigned, shared: shared.sort() };
}

/**
 * Resolves a candidate in status "new" (e.g. added manually) against venues, aliases and other candidates.
 * Duplicates are folded into the existing candidate and this one becomes a `duplicate_of:<id>` tombstone.
 */
export async function resolveCandidate(
  db: Db,
  candidateId: number,
  options: IdentityOptions = {},
): Promise<RecordOutcome> {
  const now = options.now ?? Date.now();
  return transaction(db, async () => {
    const candidate = await getCandidate(db, candidateId);
    if (!candidate) throw new Error(`Unknown candidate ${candidateId}`);
    const aliases = await listPlaceAliases(db, { candidateId });
    const probe: VenueProbe = {
      name: candidate.name,
      address: candidate.address,
      city: candidate.city,
      lat: candidate.lat,
      lng: candidate.lng,
      website: candidate.website,
      timezone: candidate.timezone,
      places: aliases.map((alias) => ({
        placeId: alias.placeId,
        types: alias.types,
        displayName: alias.displayName,
        lat: alias.lat,
        lng: alias.lng,
        canonical: alias.isCanonical,
      })),
      discoveredFrom: candidate.discoveredFrom,
    };
    const match = await matchIdentity(db, probe, { ...options, excludeCandidateId: candidateId });
    switch (match.kind) {
      case "venue": {
        if (match.candidateId != null && match.candidateId !== candidateId) {
          return foldDuplicate(db, candidate, match.candidateId, probe, match, now);
        }
        const hasSource = await venueHasEnabledSource(db, match.venueId);
        const updated = await updateCandidate(
          db,
          candidateId,
          {
            matchedVenueId: match.venueId,
            status: hasSource ? "rejected" : "resolved",
            statusReason: hasSource ? "venue_has_source" : `matched_venue:${match.via}`,
          },
          now,
        );
        await writeAliases(db, probe.places, { venueId: match.venueId, candidateId }, now);
        return { kind: "matched_venue", candidate: updated, match };
      }
      case "candidate":
        return foldDuplicate(db, candidate, match.candidateId, probe, match, now);
      case "conflict": {
        const updated = await updateCandidate(
          db,
          candidateId,
          {
            status: "needs_review",
            statusReason: match.reason,
            evidence: {
              ...candidate.evidence,
              conflict: { reason: match.reason, venueIds: match.venueIds, candidateIds: match.candidateIds },
            },
          },
          now,
        );
        return { kind: "needs_review", candidate: updated, match };
      }
      case "none": {
        const updated = await updateCandidate(db, candidateId, { status: "resolved", statusReason: "new_venue" }, now);
        return { kind: "created", candidate: updated, match };
      }
    }
  });
}

async function foldDuplicate(
  db: Db,
  duplicate: Candidate,
  targetId: number,
  probe: VenueProbe,
  match: IdentityMatch,
  now: number,
): Promise<RecordOutcome> {
  const target = (await getCandidate(db, targetId)) as Candidate;
  const observations = Array.isArray(duplicate.evidence.observations)
    ? (duplicate.evidence.observations as Record<string, unknown>[])
    : [];
  let merged = await mergeInto(
    db,
    target,
    { ...probe, observation: undefined, observationKey: `candidate:${duplicate.id}` },
    now,
  );
  let evidence = merged.evidence;
  for (const obs of observations) {
    evidence = appendObservation(
      evidence,
      (obs.feed as DiscoveryFeed) ?? duplicate.discoveredFrom,
      obs.key as string | undefined,
      obs,
      now,
    );
  }
  merged = await updateCandidate(db, target.id, { evidence }, now);
  for (const alias of await listPlaceAliases(db, { candidateId: duplicate.id })) {
    await upsertPlaceAlias(
      db,
      {
        placeId: alias.placeId,
        venueId: alias.venueId ?? merged.matchedVenueId,
        candidateId: target.id,
        isCanonical:
          alias.isCanonical && !(await listPlaceAliases(db, { candidateId: target.id })).some((a) => a.isCanonical),
        types: alias.types,
        displayName: alias.displayName,
        lat: alias.lat,
        lng: alias.lng,
      },
      now,
    );
  }
  await updateCandidate(db, duplicate.id, { status: "rejected", statusReason: `duplicate_of:${target.id}` }, now);
  return { kind: "merged", candidate: merged, match };
}
