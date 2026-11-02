/**
 * OpenStreetMap Overpass feed: venue-like features in a bounding box. Minimal dependencies, no API key.
 * One query per city box is enough (Overpass returns every match); the client is polite (serialized requests,
 * minimum interval, identifiable User-Agent) and injectable for tests.
 */
import type { Db } from "../db.js";
import { USER_AGENT } from "../fetch.js";
import type { BoundingBox, Clock, FetchLike, OverpassClient, OverpassElement, Sleep } from "../types.js";
import { realSleep, systemClock } from "../types.js";
import { parseHttpUrl } from "../url.js";
import { type IdentityOptions, type RecordKind, recordProbe, type VenueProbe } from "./resolve.js";

export const DEFAULT_OVERPASS_URL = "https://overpass-api.de/api/interpreter";

/** amenity values that are venues by definition. */
export const OSM_VENUE_AMENITIES: readonly string[] = [
  "music_venue",
  "nightclub",
  "theatre",
  "arts_centre",
  "events_venue",
  "concert_hall",
  "comedy_club",
];

/** amenity values that count only when tagged live_music=yes. */
export const OSM_LIVE_MUSIC_AMENITIES: readonly string[] = ["bar", "pub", "restaurant", "cafe", "biergarten"];

const fmt = (value: number) => Number(value.toFixed(6)).toString();

/** Builds the Overpass QL query for a bounding box (south, west, north, east). */
export function buildOverpassQuery(box: BoundingBox, timeoutSeconds = 90): string {
  const bbox = `${fmt(box.south)},${fmt(box.west)},${fmt(box.north)},${fmt(box.east)}`;
  const venues = OSM_VENUE_AMENITIES.join("|");
  const live = OSM_LIVE_MUSIC_AMENITIES.join("|");
  return [
    `[out:json][timeout:${timeoutSeconds}];`,
    "(",
    `  nwr["amenity"~"^(${venues})$"]["name"](${bbox});`,
    `  nwr["amenity"~"^(${live})$"]["live_music"="yes"]["name"](${bbox});`,
    `  nwr["leisure"~"^(dance|bandstand)$"]["name"](${bbox});`,
    `  nwr["theatre:type"]["name"](${bbox});`,
    `  nwr["building"="theatre"]["name"](${bbox});`,
    ");",
    "out center tags;",
  ].join("\n");
}

interface RawElement {
  type?: string;
  id?: number;
  lat?: number;
  lon?: number;
  center?: { lat?: number; lon?: number };
  tags?: Record<string, string>;
}

/** Normalizes an Overpass JSON response. Ways/relations use their `center`. */
export function parseOverpassResponse(json: unknown): OverpassElement[] {
  const elements = (json as { elements?: RawElement[] } | null)?.elements;
  if (!Array.isArray(elements)) return [];
  const out: OverpassElement[] = [];
  for (const raw of elements) {
    if (raw.type !== "node" && raw.type !== "way" && raw.type !== "relation") continue;
    if (typeof raw.id !== "number") continue;
    const lat = raw.lat ?? raw.center?.lat ?? null;
    const lng = raw.lon ?? raw.center?.lon ?? null;
    out.push({
      id: `${raw.type}/${raw.id}`,
      type: raw.type,
      lat: typeof lat === "number" ? lat : null,
      lng: typeof lng === "number" ? lng : null,
      tags: raw.tags ?? {},
    });
  }
  return out;
}

/**
 * Overpass reports query timeouts and memory exhaustion with HTTP 200 and a `remark` ("runtime error: Query timed out
 * ..."); the elements are then empty or partial. Returns the remark when the response must count as a failure.
 */
export function overpassRuntimeFailure(json: unknown): string | null {
  const remark = (json as { remark?: unknown } | null)?.remark;
  if (typeof remark !== "string" || !remark.trim()) return null;
  const elements = (json as { elements?: unknown }).elements;
  const empty = !Array.isArray(elements) || elements.length === 0;
  if (/^\s*runtime (error|remark)/i.test(remark) || empty) return remark.trim().slice(0, 300);
  return null;
}

export interface OverpassHttpClientOptions {
  endpoint?: string;
  fetchImpl?: FetchLike;
  clock?: Clock;
  sleep?: Sleep;
  /** Minimum spacing between queries. Default 10s (public instances are shared). */
  minIntervalMs?: number;
  timeoutMs?: number;
  userAgent?: string;
}

export class OverpassHttpClient implements OverpassClient {
  private nextSlot = 0;
  private readonly fetchImpl: FetchLike;
  private readonly clock: Clock;
  private readonly sleep: Sleep;

  constructor(private readonly options: OverpassHttpClientOptions = {}) {
    this.fetchImpl = options.fetchImpl ?? ((input, init) => fetch(input, init));
    this.clock = options.clock ?? systemClock;
    this.sleep = options.sleep ?? realSleep;
  }

  async query(ql: string): Promise<OverpassElement[]> {
    const now = this.clock.now().getTime();
    const slot = Math.max(now, this.nextSlot);
    this.nextSlot = slot + (this.options.minIntervalMs ?? 10_000);
    if (slot > now) await this.sleep(slot - now);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.options.timeoutMs ?? 120_000);
    try {
      const response = await this.fetchImpl(this.options.endpoint ?? DEFAULT_OVERPASS_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          Accept: "application/json",
          "User-Agent": this.options.userAgent ?? USER_AGENT,
        },
        body: `data=${encodeURIComponent(ql)}`,
        signal: controller.signal,
      });
      const text = await response.text();
      if (!response.ok) throw new Error(`Overpass HTTP ${response.status}`);
      const json = JSON.parse(text) as unknown;
      const failure = overpassRuntimeFailure(json);
      if (failure) throw new Error(`Overpass ${failure}`);
      return parseOverpassResponse(json);
    } finally {
      clearTimeout(timer);
    }
  }
}

function tagWebsite(tags: Record<string, string>): string | null {
  const raw = tags.website ?? tags["contact:website"] ?? tags.url ?? null;
  if (!raw) return null;
  const first = raw.split(";")[0]?.trim() ?? "";
  return parseHttpUrl(first)?.href ?? null;
}

function tagAddress(tags: Record<string, string>): string | null {
  const street = [tags["addr:housenumber"], tags["addr:street"]].filter(Boolean).join(" ");
  const parts = [street, tags["addr:city"], tags["addr:state"], tags["addr:postcode"]].filter(Boolean);
  return parts.length ? parts.join(", ") : null;
}

/** Converts an Overpass element to a probe; null for unnamed or location-less elements. */
export function probeFromOsm(
  element: OverpassElement,
  context: { city?: string | null; timezone?: string | null; area?: BoundingBox | null } = {},
): VenueProbe | null {
  const name = element.tags.name?.trim();
  if (!name || element.lat == null || element.lng == null) return null;
  return {
    name,
    address: tagAddress(element.tags),
    city: element.tags["addr:city"] ?? context.city ?? null,
    lat: element.lat,
    lng: element.lng,
    website: tagWebsite(element.tags),
    timezone: context.timezone ?? null,
    discoveredFrom: "osm",
    observationKey: `osm:${element.id}`,
    observation: {
      osmId: element.id,
      amenity: element.tags.amenity ?? null,
      liveMusic: element.tags.live_music ?? null,
      leisure: element.tags.leisure ?? null,
    },
    area: context.area ?? null,
  };
}

export interface OsmDiscoverOptions extends IdentityOptions {
  city?: string | null;
  timezone?: string | null;
}

export interface OsmDiscoverSummary {
  elements: number;
  skipped: number;
  outcomes: Record<RecordKind, number>;
  candidateIds: number[];
}

/** Queries Overpass for a box and records every named feature as a probe. */
export async function discoverOsmArea(
  db: Db,
  client: OverpassClient,
  box: BoundingBox,
  options: OsmDiscoverOptions = {},
): Promise<OsmDiscoverSummary> {
  const elements = await client.query(buildOverpassQuery(box));
  const summary: OsmDiscoverSummary = {
    elements: elements.length,
    skipped: 0,
    outcomes: { created: 0, merged: 0, matched_venue: 0, needs_review: 0 },
    candidateIds: [],
  };
  for (const element of elements) {
    const probe = probeFromOsm(element, { city: options.city, timezone: options.timezone, area: box });
    if (!probe) {
      summary.skipped++;
      continue;
    }
    const outcome = recordProbe(db, probe, options);
    summary.outcomes[outcome.kind]++;
    summary.candidateIds.push(outcome.candidate.id);
  }
  return summary;
}
