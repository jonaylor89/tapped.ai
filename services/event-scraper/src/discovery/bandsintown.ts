/**
 * Optional Bandsintown feed: upcoming events of KNOWN performers -> the venues they play -> candidates.
 * Disabled by default; enabled only when BANDSINTOWN_APP_ID is set AND the feed is switched on explicitly
 * (EVENT_SCRAPER_BANDSINTOWN=1 or `enabled: true`). Rate limited, never the only source of a venue: it only
 * proposes candidates, which still need their own website source proven before promotion. Bandsintown event URLs
 * are recorded as evidence strings and never fetched.
 */
import type { Db } from "../db.js";
import { USER_AGENT } from "../fetch.js";
import type { BandsintownClient, BandsintownEvent, BoundingBox, Clock, FetchLike, Sleep } from "../types.js";
import { realSleep, systemClock } from "../types.js";
import { inBbox } from "./geo.js";
import { type IdentityOptions, type RecordKind, recordProbe } from "./resolve.js";

export const BANDSINTOWN_API = "https://rest.bandsintown.com";

export interface BandsintownHttpClientOptions {
  appId: string;
  fetchImpl?: FetchLike;
  clock?: Clock;
  sleep?: Sleep;
  /** Minimum spacing between requests. Default 3s. */
  minIntervalMs?: number;
  timeoutMs?: number;
  endpoint?: string;
}

interface RawBitEvent {
  id?: string | number;
  datetime?: string;
  url?: string;
  title?: string;
  lineup?: string[];
  venue?: {
    name?: string;
    city?: string;
    region?: string;
    country?: string;
    latitude?: string | number;
    longitude?: string | number;
  };
}

const toNum = (value: unknown): number | null => {
  const n = typeof value === "string" ? Number.parseFloat(value) : typeof value === "number" ? value : Number.NaN;
  return Number.isFinite(n) && n !== 0 ? n : null;
};

/** Normalizes the artist events payload (array) to `BandsintownEvent[]`; anything else yields []. */
export function parseBandsintownEvents(json: unknown): BandsintownEvent[] {
  if (!Array.isArray(json)) return [];
  const out: BandsintownEvent[] = [];
  for (const raw of json as RawBitEvent[]) {
    const name = raw?.venue?.name?.trim();
    if (!raw || raw.id == null || !raw.datetime || !name) continue;
    out.push({
      id: String(raw.id),
      datetime: raw.datetime,
      url: raw.url ?? null,
      title: raw.title ?? null,
      lineup: Array.isArray(raw.lineup) ? raw.lineup.filter((x): x is string => typeof x === "string") : [],
      venue: {
        name,
        city: raw.venue?.city || null,
        region: raw.venue?.region || null,
        country: raw.venue?.country || null,
        lat: toNum(raw.venue?.latitude),
        lng: toNum(raw.venue?.longitude),
      },
    });
  }
  return out;
}

/** Bandsintown's documented artist-name escaping: "/" -> %252F, "?" -> %253F, "*" -> %252A, '"' -> %27C. */
export function encodeArtistName(name: string): string {
  return encodeURIComponent(name.trim())
    .replace(/%2F/gi, "%252F")
    .replace(/%3F/gi, "%253F")
    .replace(/\*/g, "%252A")
    .replace(/%22/gi, "%27C");
}

export class BandsintownHttpClient implements BandsintownClient {
  private nextSlot = 0;
  private readonly fetchImpl: FetchLike;
  private readonly clock: Clock;
  private readonly sleep: Sleep;

  constructor(private readonly options: BandsintownHttpClientOptions) {
    if (!options.appId) throw new Error("Bandsintown app id is required");
    this.fetchImpl = options.fetchImpl ?? ((input, init) => fetch(input, init));
    this.clock = options.clock ?? systemClock;
    this.sleep = options.sleep ?? realSleep;
  }

  async artistEvents(artistName: string): Promise<BandsintownEvent[]> {
    const now = this.clock.now().getTime();
    const slot = Math.max(now, this.nextSlot);
    this.nextSlot = slot + (this.options.minIntervalMs ?? 3000);
    if (slot > now) await this.sleep(slot - now);
    const url = new URL(`/artists/${encodeArtistName(artistName)}/events`, this.options.endpoint ?? BANDSINTOWN_API);
    url.searchParams.set("app_id", this.options.appId);
    url.searchParams.set("date", "upcoming");
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.options.timeoutMs ?? 15_000);
    try {
      const response = await this.fetchImpl(url, {
        headers: { Accept: "application/json", "User-Agent": USER_AGENT },
        signal: controller.signal,
      });
      // Unknown artists come back as 404 or as an {errorMessage} object; neither is an error for discovery.
      if (response.status === 404) return [];
      if (!response.ok) throw new Error(`Bandsintown HTTP ${response.status}`);
      const text = await response.text();
      return parseBandsintownEvents(text ? JSON.parse(text) : []);
    } finally {
      clearTimeout(timer);
    }
  }
}

/**
 * Returns a client only when BANDSINTOWN_APP_ID is set and the feed is explicitly enabled
 * (`options.enabled` or EVENT_SCRAPER_BANDSINTOWN=1/true).
 */
export function createBandsintownClientFromEnv(
  env: Record<string, string | undefined> = process.env,
  options: Omit<BandsintownHttpClientOptions, "appId"> & { enabled?: boolean } = {},
): BandsintownHttpClient | null {
  const appId = env.BANDSINTOWN_APP_ID?.trim();
  const flag = (env.EVENT_SCRAPER_BANDSINTOWN ?? "").trim().toLowerCase();
  const enabled = options.enabled ?? (flag === "1" || flag === "true" || flag === "yes");
  if (!appId || !enabled) return null;
  const { enabled: _ignored, ...rest } = options;
  return new BandsintownHttpClient({ ...rest, appId });
}

export interface BandsintownDiscoverOptions extends IdentityOptions {
  /** Only venues inside one of these boxes become candidates (avoid discovering the whole world). */
  areas?: { city: string; timezone: string; bbox: BoundingBox }[];
  /** Max artists per run. Default 50. */
  maxArtists?: number;
  clock?: Clock;
}

export interface BandsintownDiscoverSummary {
  artists: number;
  events: number;
  outsideAreas: number;
  outcomes: Record<RecordKind, number>;
  candidateIds: number[];
}

/** Looks up known performers' upcoming events and records their venues (inside configured areas) as candidates. */
export async function discoverFromBandsintown(
  db: Db,
  client: BandsintownClient,
  artistNames: string[],
  options: BandsintownDiscoverOptions = {},
): Promise<BandsintownDiscoverSummary> {
  const summary: BandsintownDiscoverSummary = {
    artists: 0,
    events: 0,
    outsideAreas: 0,
    outcomes: { created: 0, merged: 0, matched_venue: 0, needs_review: 0 },
    candidateIds: [],
  };
  const unique = [...new Set(artistNames.map((name) => name.trim()).filter(Boolean))].slice(
    0,
    options.maxArtists ?? 50,
  );
  for (const artist of unique) {
    summary.artists++;
    const events = await client.artistEvents(artist);
    for (const event of events) {
      summary.events++;
      const area = options.areas?.find((candidate) => inBbox(event.venue, candidate.bbox));
      if (options.areas && !area) {
        summary.outsideAreas++;
        continue;
      }
      const outcome = recordProbe(
        db,
        {
          name: event.venue.name,
          city: area?.city ?? event.venue.city,
          lat: event.venue.lat,
          lng: event.venue.lng,
          timezone: area?.timezone ?? null,
          discoveredFrom: "bandsintown",
          observationKey: `bandsintown:${event.id}`,
          observation: { artist, eventId: event.id, datetime: event.datetime, eventUrl: event.url },
          area: area?.bbox ?? null,
        },
        { ...options, now: options.now ?? (options.clock ?? systemClock).now().getTime() },
      );
      summary.outcomes[outcome.kind]++;
      summary.candidateIds.push(outcome.candidate.id);
    }
  }
  return summary;
}
