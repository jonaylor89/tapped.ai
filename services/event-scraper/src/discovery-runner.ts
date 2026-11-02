/**
 * The slow venue-discovery loop. Each feed unit is a job in the SQLite queue with a dedupe key, re-enqueued after it
 * runs with that feed's refresh interval, so a unit is searched at most once per interval:
 *   discover_cell        one Google Places grid cell   (budget-capped: Places requests per run)
 *   discover_osm         one city bbox on Overpass
 *   discover_listing     one configured non-ticketing city listing page
 *   discover_bandsintown the configured artist list (optional, off by default)
 * After the feeds, candidates are resolved (place-id clustering + aliases) and proved
 * (source finder + normal extraction, >= N valid upcoming events => `promoted` for human review).
 */
import { claimJob, countJobs, type Db, enqueueJob, finishJob, retireJobs } from "./db.js";
import { discoverFromBandsintown } from "./discovery/bandsintown.js";
import { type CityConfig, cityGrid, type GridCell } from "./discovery/geo.js";
import { discoverFromListing, type ListingFeedConfig } from "./discovery/listings.js";
import { discoverOsmArea } from "./discovery/osm.js";
import { CellSearchError, DEFAULT_PLACES_QUERIES, discoverPlacesCell } from "./discovery/places.js";
import { type DiscoveryStepSummary, runCandidatePipeline } from "./discovery/prove.js";
import { type Logger, silentLogger } from "./runner.js";
import type {
  BandsintownClient,
  Clock,
  Extractor,
  HttpClient,
  Job,
  LlmClient,
  OverpassClient,
  PlacesClient,
  Sleep,
} from "./types.js";
import { realSleep, systemClock } from "./types.js";

export const DISCOVERY_JOB_KINDS = {
  places: "discover_cell",
  osm: "discover_osm",
  listing: "discover_listing",
  bandsintown: "discover_bandsintown",
} as const;

const DAY_MS = 24 * 60 * 60 * 1000;

export interface DiscoveryDeps {
  db: Db;
  http: HttpClient;
  places?: PlacesClient | null;
  overpass?: OverpassClient | null;
  bandsintown?: BandsintownClient | null;
  llm?: LlmClient | null;
  /** Fallback extractor used while proving (the LLM extractor when enabled). */
  fallback?: Extractor | null;
  clock?: Clock;
  sleep?: Sleep;
  log?: Logger;
}

export interface DiscoveryOptions {
  cities: CityConfig[];
  listings?: ListingFeedConfig[];
  /** City listing feeds on/off. Default true. When off, queued listing units stay queued but never run. */
  listingsEnabled?: boolean;
  bandsintownArtists?: string[];
  /** Restrict this run to one city (by name, case-insensitive). */
  city?: string | null;
  /** Hard cap on Places requests this run. Default 200. */
  placesBudget?: number;
  placesQueries?: readonly string[];
  /** Pages per query (API max 3). Default 3. */
  placesMaxPages?: number;
  placesPageDelayMs?: number;
  placesRefreshMs?: number;
  osmRefreshMs?: number;
  listingsRefreshMs?: number;
  bandsintownRefreshMs?: number;
  bandsintownMaxArtists?: number;
  /** Retry delay after a feed unit fails. Default 1 day. */
  feedRetryMs?: number;
  minProvenEvents?: number;
  proveLimit?: number;
  /** Skip the resolve/prove step (feeds only). */
  skipProve?: boolean;
}

export interface FeedUnitResult {
  kind: string;
  key: string;
  ok: boolean;
  message?: string;
  summary?: Record<string, unknown>;
}

export interface DiscoveryRunSummary {
  scheduled: number;
  units: FeedUnitResult[];
  placesRequests: number;
  placesBudget: number;
  /** True when the run stopped starting Places cells because the request budget was reached. */
  placesBudgetExhausted: boolean;
  /** Set when Places answered 403/429 and the rest of this run's Places work was skipped. */
  placesHalted: string | null;
  /** Queued units retired because their city / listing is no longer configured. */
  retired: number;
  pipeline: { resolved: number; proved: { promoted: number; noSource: number; other: number } } | null;
  provedDetails: DiscoveryStepSummary["proved"];
}

interface PlacesPayload {
  cell: GridCell;
}
interface OsmPayload {
  city: string;
  timezone: string;
  bbox: CityConfig["bbox"];
}
interface ListingPayload {
  feed: ListingFeedConfig;
}
interface BandsintownPayload {
  artists: string[];
}

function errorText(error: unknown): string {
  return (error instanceof Error ? error.message : String(error)).slice(0, 300);
}

/** Every feed unit the current configuration wants, by kind and dedupe key (with its current payload). */
export interface FeedUnits {
  osm: Map<string, OsmPayload>;
  places: Map<string, PlacesPayload>;
  listing: Map<string, ListingPayload>;
  bandsintown: Map<string, BandsintownPayload>;
}

function unitKey(kind: string, key: string): string {
  return `${kind}:${key}`;
}

function sameCity(a: string, b: string | null | undefined): boolean {
  return b != null && a.toLowerCase() === b.toLowerCase();
}

/**
 * Feed units from the configuration. `city` narrows to one city (and that city's listings); features without a
 * client (or listings turned off) contribute nothing.
 */
export function configuredUnits(
  deps: Pick<DiscoveryDeps, "places" | "overpass" | "bandsintown">,
  options: DiscoveryOptions,
  city: string | null = options.city ?? null,
): FeedUnits {
  const units: FeedUnits = { osm: new Map(), places: new Map(), listing: new Map(), bandsintown: new Map() };
  const cities = city ? options.cities.filter((c) => sameCity(c.name, city)) : options.cities;
  for (const c of cities) {
    if (deps.overpass)
      units.osm.set(unitKey(DISCOVERY_JOB_KINDS.osm, c.name.toLowerCase()), {
        city: c.name,
        timezone: c.timezone,
        bbox: c.bbox,
      });
    if (deps.places)
      for (const cell of cityGrid(c)) units.places.set(unitKey(DISCOVERY_JOB_KINDS.places, cell.id), { cell });
  }
  if (options.listingsEnabled ?? true) {
    for (const feed of options.listings ?? []) {
      if (city && !sameCity(feed.city, city)) continue;
      units.listing.set(unitKey(DISCOVERY_JOB_KINDS.listing, feed.url), { feed });
    }
  }
  if (deps.bandsintown && options.bandsintownArtists?.length) {
    units.bandsintown.set(unitKey(DISCOVERY_JOB_KINDS.bandsintown, "artists"), {
      artists: options.bandsintownArtists,
    });
  }
  return units;
}

/**
 * Enqueues every feed unit that has no pending job yet (existing future jobs keep their refresh time), and retires
 * queued units whose city / listing URL / artist list is no longer configured, so removed feeds stop for good.
 * Kinds whose feature is off (no client, listings disabled) are left alone: they simply never run.
 */
export function scheduleDiscovery(
  db: Db,
  deps: Pick<DiscoveryDeps, "places" | "overpass" | "bandsintown">,
  options: DiscoveryOptions,
  now: number,
): { scheduled: number; retired: number } {
  const kinds = Object.values(DISCOVERY_JOB_KINDS);
  const all = configuredUnits(deps, options, null);
  let retired = 0;
  if (deps.overpass) retired += retireJobs(db, DISCOVERY_JOB_KINDS.osm, all.osm.keys(), now);
  if (deps.places) retired += retireJobs(db, DISCOVERY_JOB_KINDS.places, all.places.keys(), now);
  if (options.listingsEnabled ?? true) retired += retireJobs(db, DISCOVERY_JOB_KINDS.listing, all.listing.keys(), now);
  if (deps.bandsintown) retired += retireJobs(db, DISCOVERY_JOB_KINDS.bandsintown, all.bandsintown.keys(), now);

  const before = kinds.reduce((sum, kind) => sum + countJobs(db, { kind }), 0);
  const wanted = configuredUnits(deps, options);
  const enqueue = (kind: string, units: Map<string, object>) => {
    for (const [dedupeKey, payload] of units)
      enqueueJob(db, kind, payload, { dedupeKey, runAfter: now, now, maxAttempts: 1_000_000 });
  };
  enqueue(DISCOVERY_JOB_KINDS.osm, wanted.osm);
  enqueue(DISCOVERY_JOB_KINDS.places, wanted.places);
  enqueue(DISCOVERY_JOB_KINDS.listing, wanted.listing);
  enqueue(DISCOVERY_JOB_KINDS.bandsintown, wanted.bandsintown);
  return { scheduled: kinds.reduce((sum, kind) => sum + countJobs(db, { kind }), 0) - before, retired };
}

/** One discovery pass: feeds (cheapest and owner-preferred first), then resolve + prove. */
export async function runDiscovery(deps: DiscoveryDeps, options: DiscoveryOptions): Promise<DiscoveryRunSummary> {
  const { db } = deps;
  const clock = deps.clock ?? systemClock;
  const log = deps.log ?? silentLogger;
  const queries = options.placesQueries ?? DEFAULT_PLACES_QUERIES;
  const maxPages = Math.min(3, Math.max(1, options.placesMaxPages ?? 3));
  const budget = options.placesBudget ?? 200;
  const retryMs = options.feedRetryMs ?? DAY_MS;
  const scheduled = scheduleDiscovery(db, deps, options, clock.now().getTime());
  const summary: DiscoveryRunSummary = {
    scheduled: scheduled.scheduled,
    units: [],
    placesRequests: 0,
    placesBudget: budget,
    placesBudgetExhausted: false,
    placesHalted: null,
    retired: scheduled.retired,
    pipeline: null,
    provedDetails: [],
  };
  const areas = options.cities.map((c) => ({ city: c.name, timezone: c.timezone, bbox: c.bbox }));
  const wanted = configuredUnits(deps, options);

  /**
   * Runs every due job of one kind that the current configuration (and --city filter) still wants. The handler gets
   * the unit's CURRENT payload, not the one stored when it was queued. The unit is re-enqueued after `refreshMs`
   * (or `retryMs` on failure). `canStart` is checked before each unit.
   */
  const drain = async <P extends object>(
    kind: string,
    units: Map<string, P>,
    refreshMs: number,
    handler: (payload: P, job: Job<P>) => Promise<Record<string, unknown>>,
    canStart: () => boolean = () => true,
  ) => {
    if (!units.size) return;
    const keys = [...units.keys()];
    while (canStart()) {
      const job = claimJob<P>(db, {
        kinds: [kind],
        dedupeKeys: keys,
        leaseMs: 60 * 60 * 1000,
        now: clock.now().getTime(),
      });
      if (!job) return;
      const token = job.leaseToken as string;
      const key = job.dedupeKey ?? `${kind}:${job.id}`;
      const payload = units.get(key) ?? job.payload;
      let ok = true;
      let unit: FeedUnitResult;
      try {
        unit = { kind, key, ok, summary: await handler(payload, job) };
      } catch (error) {
        ok = false;
        unit = { kind, key, ok, message: errorText(error) };
        log("discovery_unit_failed", { kind, key, error: unit.message });
      }
      const at = clock.now().getTime();
      if (!finishJob(db, job.id, token, at)) {
        // Lease lost (another process reclaimed it): that process reschedules the unit.
        summary.units.push(unit);
        continue;
      }
      enqueueJob(db, kind, payload, {
        dedupeKey: job.dedupeKey,
        runAfter: at + (ok ? refreshMs : retryMs),
        now: at,
        maxAttempts: 1_000_000,
      });
      summary.units.push(unit);
    }
  };

  // (1) Map search: OpenStreetMap first (free, owner's favorite), then Google Places within the request budget.
  const overpass = deps.overpass;
  if (overpass) {
    await drain<OsmPayload>(DISCOVERY_JOB_KINDS.osm, wanted.osm, options.osmRefreshMs ?? 30 * DAY_MS, async (area) => {
      const r = await discoverOsmArea(db, overpass, area.bbox, {
        city: area.city,
        timezone: area.timezone,
        now: clock.now().getTime(),
      });
      return { elements: r.elements, skipped: r.skipped, ...r.outcomes };
    });
  }
  const places = deps.places;
  if (places) {
    const worstCase = queries.length * maxPages;
    await drain<PlacesPayload>(
      DISCOVERY_JOB_KINDS.places,
      wanted.places,
      options.placesRefreshMs ?? 30 * DAY_MS,
      async ({ cell }) => {
        try {
          const r = await discoverPlacesCell(db, places, cell, {
            queries,
            maxPages,
            pageDelayMs: options.placesPageDelayMs,
            sleep: deps.sleep ?? realSleep,
            clock,
            // Every request is counted when it is made (failed ones too) and checked against the hard cap.
            beforeRequest: () => {
              if (summary.placesRequests >= budget) {
                summary.placesBudgetExhausted = true;
                return false;
              }
              summary.placesRequests++;
              return true;
            },
          });
          // A cell cut short by the budget is incomplete: retry it soon instead of after the refresh interval.
          if (r.truncated) throw new Error("places_budget_exhausted_mid_cell");
          const { candidateIds: _ids, ...rest } = r;
          return rest;
        } catch (error) {
          if (error instanceof CellSearchError && (error.status === 403 || error.status === 429)) {
            // Quota exhausted or key restricted: every further cell would fail the same way.
            summary.placesHalted = `http_${error.status}`;
          }
          throw error;
        }
      },
      () => {
        if (summary.placesHalted) return false;
        // Only start a cell when its worst-case request count still fits: the budget is a hard cap.
        const ok = summary.placesRequests + worstCase <= budget;
        if (!ok) summary.placesBudgetExhausted = true;
        return ok;
      },
    );
  }

  // (2) City listing pages (never ticketing platforms; discoverFromListing refuses them before any request).
  // Only listing URLs still in the configuration run (none when listings are disabled).
  await drain<ListingPayload>(
    DISCOVERY_JOB_KINDS.listing,
    wanted.listing,
    options.listingsRefreshMs ?? 7 * DAY_MS,
    async ({ feed }) => {
      const r = await discoverFromListing(db, deps.http, feed, { clock });
      if (r.status !== "ok" && r.status !== "not_modified")
        throw new Error(`${r.status}${r.message ? `: ${r.message}` : ""}`);
      return { status: r.status, venues: r.venues, ...r.outcomes };
    },
  );

  // (3) Bandsintown: optional, disabled by default, never the only source.
  const bandsintown = deps.bandsintown;
  if (bandsintown) {
    await drain<BandsintownPayload>(
      DISCOVERY_JOB_KINDS.bandsintown,
      wanted.bandsintown,
      options.bandsintownRefreshMs ?? 7 * DAY_MS,
      async ({ artists }) => {
        const r = await discoverFromBandsintown(db, bandsintown, artists, {
          areas,
          maxArtists: options.bandsintownMaxArtists,
          clock,
        });
        return { artists: r.artists, events: r.events, outsideAreas: r.outsideAreas, ...r.outcomes };
      },
    );
  }

  if (!options.skipProve) {
    const step = await runCandidatePipeline(db, {
      http: deps.http,
      llm: deps.llm ?? null,
      fallback: deps.fallback ?? null,
      minEvents: options.minProvenEvents,
      limit: options.proveLimit,
      clock,
    });
    const promoted = step.proved.filter((p) => p.status === "promoted").length;
    const noSource = step.proved.filter((p) => p.status === "no_source").length;
    summary.pipeline = {
      resolved: step.resolved,
      proved: { promoted, noSource, other: step.proved.length - promoted - noSource },
    };
    summary.provedDetails = step.proved;
  }
  log("discovery_done", { units: summary.units.length, placesRequests: summary.placesRequests });
  return summary;
}
