/**
 * Runtime configuration: environment variables (validated) plus an optional JSON config file holding the discovery
 * cities, city listing feeds and Bandsintown artists. Nothing here reads secrets beyond checking that a key is set;
 * the network clients read their own keys from the environment when they are built.
 */
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { ticketingMatch } from "./denylist.js";
import type { CityConfig, ListingFeedConfig } from "./discovery/index.js";
import { DEFAULT_PLACES_QUERIES } from "./discovery/places.js";
import type { BoundingBox } from "./types.js";
import { parseHttpUrl } from "./url.js";
import { isValidTimeZone } from "./validate/time.js";

export type PublishMode = "off" | "ndjson" | "postgres";

export interface FeatureFlags {
  /** LLM fallback extractor + LLM help in the source finder. Needs OPENAI_API_KEY. Default off. */
  llm: boolean;
  /** Google Places (New) Text Search grid discovery. Needs GOOGLE_PLACES_API_KEY. Default off (it costs money). */
  places: boolean;
  /** OpenStreetMap Overpass discovery. Default on (no key). */
  osm: boolean;
  /** City listing pages (non-ticketing) from the config file. Default on. */
  listings: boolean;
  /** Bandsintown artist events for known performers. Needs BANDSINTOWN_APP_ID. Default off. */
  bandsintown: boolean;
}

export interface ConfigFile {
  cities: CityConfig[];
  listings: ListingFeedConfig[];
  bandsintownArtists: string[];
  placesQueries: string[] | null;
}

export interface ScraperConfig {
  /** Postgres holding the `scraper` schema; over Tailscale from a laptop. */
  databaseUrl: string;
  dbSchema: string;
  maxDbConnections: number;
  dataDir: string;
  configFile: string | null;
  cities: CityConfig[];
  listings: ListingFeedConfig[];
  bandsintownArtists: string[];
  features: FeatureFlags;
  publish: { mode: PublishMode; dryRunPath: string };
  /** Polite fetching. */
  http: { minHostIntervalMs: number; timeoutMs: number };
  scrape: {
    /** Max fetch_source jobs per run-once / loop tick. */
    maxJobsPerRun: number;
    /** Parallel workers (different hosts proceed in parallel; same host is serialized by the HTTP client). */
    concurrency: number;
    /** Refetch interval for sources whose events changed. Default 24h. */
    productiveIntervalMs: number;
    /** Upper bound of the unchanged-content backoff. Default 7d. */
    maxIntervalMs: number;
    /** Max pages sent to the LLM per UTC day across all runs and processes (cost cap, counted in Postgres). */
    llmMaxPagesPerDay: number;
  };
  discovery: {
    /** Hard cap on Places API requests per discovery run. */
    placesBudgetPerRun: number;
    placesQueries: string[];
    placesMaxPages: number;
    placesRefreshMs: number;
    osmRefreshMs: number;
    listingsRefreshMs: number;
    bandsintownRefreshMs: number;
    bandsintownMaxArtists: number;
    minProvenEvents: number;
    proveLimitPerRun: number;
  };
  loop: { tickMs: number; discoverEveryMs: number; publishEveryMs: number };
}

export class ConfigError extends Error {
  constructor(readonly issues: string[]) {
    super(`Invalid configuration:\n- ${issues.join("\n- ")}`);
    this.name = "ConfigError";
  }
}

type Env = Record<string, string | undefined>;

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

function flag(env: Env, name: string, fallback: boolean, issues: string[]): boolean {
  const raw = env[name]?.trim().toLowerCase();
  if (!raw) return fallback;
  if (["1", "true", "yes", "on"].includes(raw)) return true;
  if (["0", "false", "no", "off"].includes(raw)) return false;
  issues.push(`${name} must be a boolean (1/0, true/false), got "${env[name]}"`);
  return fallback;
}

function int(env: Env, name: string, fallback: number, issues: string[], min = 0, max = Number.MAX_SAFE_INTEGER) {
  const raw = env[name]?.trim();
  if (!raw) return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < min || value > max) {
    issues.push(`${name} must be an integer between ${min} and ${max}, got "${raw}"`);
    return fallback;
  }
  return value;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseBbox(value: unknown, where: string, issues: string[]): BoundingBox | null {
  if (!isObject(value)) {
    issues.push(`${where}: bbox must be an object {south, west, north, east}`);
    return null;
  }
  const box = { south: value.south, west: value.west, north: value.north, east: value.east };
  for (const [key, v] of Object.entries(box)) {
    if (typeof v !== "number" || !Number.isFinite(v)) {
      issues.push(`${where}: bbox.${key} must be a number`);
      return null;
    }
  }
  const b = box as BoundingBox;
  if (b.south < -90 || b.north > 90 || b.west < -180 || b.east > 180 || !(b.north > b.south) || !(b.east > b.west)) {
    issues.push(`${where}: bbox must satisfy -90<=south<north<=90 and -180<=west<east<=180`);
    return null;
  }
  return b;
}

function parseTimezone(value: unknown, where: string, issues: string[]): string | null {
  if (typeof value !== "string" || !isValidTimeZone(value)) {
    issues.push(`${where}: timezone must be a valid IANA zone (e.g. "America/Chicago")`);
    return null;
  }
  return value;
}

/** Validates the JSON config file contents. Throws ConfigError listing every problem. */
export function parseConfigFile(raw: unknown): ConfigFile {
  const issues: string[] = [];
  if (!isObject(raw)) throw new ConfigError(["config file must be a JSON object"]);
  const cities: CityConfig[] = [];
  const names = new Set<string>();
  for (const [i, item] of (Array.isArray(raw.cities) ? raw.cities : []).entries()) {
    const where = `cities[${i}]`;
    if (!isObject(item) || typeof item.name !== "string" || !item.name.trim()) {
      issues.push(`${where}: name is required`);
      continue;
    }
    const bbox = parseBbox(item.bbox, where, issues);
    const timezone = parseTimezone(item.timezone, where, issues);
    let cellMeters: number | undefined;
    if (item.cellMeters !== undefined) {
      if (typeof item.cellMeters !== "number" || !(item.cellMeters >= 250 && item.cellMeters <= 50_000)) {
        issues.push(`${where}: cellMeters must be a number between 250 and 50000`);
      } else cellMeters = item.cellMeters;
    }
    const key = item.name.trim().toLowerCase();
    if (names.has(key)) issues.push(`${where}: duplicate city name "${item.name}"`);
    names.add(key);
    if (bbox && timezone)
      cities.push({ name: item.name.trim(), bbox, timezone, ...(cellMeters ? { cellMeters } : {}) });
  }
  if (raw.cities !== undefined && !Array.isArray(raw.cities)) issues.push("cities must be an array");

  const listings: ListingFeedConfig[] = [];
  for (const [i, item] of (Array.isArray(raw.listings) ? raw.listings : []).entries()) {
    const where = `listings[${i}]`;
    if (!isObject(item)) {
      issues.push(`${where}: must be an object`);
      continue;
    }
    const url = typeof item.url === "string" ? parseHttpUrl(item.url) : null;
    if (!url) {
      issues.push(`${where}: url must be an http(s) URL`);
      continue;
    }
    const ticketing = ticketingMatch(url);
    if (ticketing) {
      issues.push(`${where}: ${url.hostname} is a ticketing platform (${ticketing}); ticketing sites are never used`);
      continue;
    }
    if (typeof item.city !== "string" || !item.city.trim()) {
      issues.push(`${where}: city is required`);
      continue;
    }
    const timezone = parseTimezone(item.timezone, where, issues);
    const area = item.area === undefined || item.area === null ? null : parseBbox(item.area, where, issues);
    if (!timezone) continue;
    listings.push({
      url: url.href,
      city: item.city.trim(),
      timezone,
      area,
      label: typeof item.label === "string" ? item.label : null,
    });
  }
  if (raw.listings !== undefined && !Array.isArray(raw.listings)) issues.push("listings must be an array");

  const artists = raw.bandsintownArtists;
  if (artists !== undefined && (!Array.isArray(artists) || artists.some((a) => typeof a !== "string"))) {
    issues.push("bandsintownArtists must be an array of strings");
  }
  const queries = raw.placesQueries;
  if (queries !== undefined && (!Array.isArray(queries) || queries.some((q) => typeof q !== "string" || !q.trim()))) {
    issues.push("placesQueries must be an array of non-empty strings");
  }
  if (issues.length) throw new ConfigError(issues);
  return {
    cities,
    listings,
    bandsintownArtists: Array.isArray(artists) ? (artists as string[]).map((a) => a.trim()).filter(Boolean) : [],
    placesQueries: Array.isArray(queries) ? (queries as string[]).map((q) => q.trim()) : null,
  };
}

export function readConfigFile(path: string): ConfigFile {
  let text: string;
  try {
    text = readFileSync(path, "utf8");
  } catch (error) {
    throw new ConfigError([`cannot read config file ${path}: ${(error as NodeJS.ErrnoException).code ?? "error"}`]);
  }
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    throw new ConfigError([`config file ${path} is not valid JSON`]);
  }
  return parseConfigFile(json);
}

/**
 * Builds the configuration from environment variables (see README for the full list) and the optional config file
 * named by EVENT_SCRAPER_CONFIG. Throws ConfigError listing every invalid value.
 */
export function loadConfig(env: Env = process.env, overrides: { configFile?: string | null } = {}): ScraperConfig {
  const issues: string[] = [];
  const dataDir = resolve(env.EVENT_SCRAPER_DATA_DIR?.trim() || "./data");
  const databaseUrl = env.EVENT_SCRAPER_DATABASE_URL?.trim() ?? "";
  if (!databaseUrl) issues.push("EVENT_SCRAPER_DATABASE_URL is required");
  const configPath =
    overrides.configFile !== undefined ? overrides.configFile : env.EVENT_SCRAPER_CONFIG?.trim() || null;

  let file: ConfigFile = { cities: [], listings: [], bandsintownArtists: [], placesQueries: null };
  if (configPath) {
    try {
      file = readConfigFile(configPath);
    } catch (error) {
      if (error instanceof ConfigError) issues.push(...error.issues);
      else throw error;
    }
  }

  const features: FeatureFlags = {
    llm: flag(env, "EVENT_SCRAPER_LLM", false, issues),
    places: flag(env, "EVENT_SCRAPER_PLACES", false, issues),
    osm: flag(env, "EVENT_SCRAPER_OSM", true, issues),
    listings: flag(env, "EVENT_SCRAPER_LISTINGS", true, issues),
    bandsintown: flag(env, "EVENT_SCRAPER_BANDSINTOWN", false, issues),
  };
  if (features.llm && !env.OPENAI_API_KEY?.trim()) issues.push("EVENT_SCRAPER_LLM is on but OPENAI_API_KEY is not set");
  if (features.places && !env.GOOGLE_PLACES_API_KEY?.trim()) {
    issues.push("EVENT_SCRAPER_PLACES is on but GOOGLE_PLACES_API_KEY is not set");
  }
  if (features.bandsintown && !env.BANDSINTOWN_APP_ID?.trim()) {
    issues.push("EVENT_SCRAPER_BANDSINTOWN is on but BANDSINTOWN_APP_ID is not set");
  }

  const rawMode = (env.EVENT_SCRAPER_PUBLISH?.trim().toLowerCase() || "ndjson") as PublishMode;
  let mode: PublishMode = "ndjson";
  if (rawMode === "off" || rawMode === "ndjson" || rawMode === "postgres") mode = rawMode;
  else issues.push(`EVENT_SCRAPER_PUBLISH must be one of off, ndjson, postgres; got "${env.EVENT_SCRAPER_PUBLISH}"`);
  if (mode === "postgres" && !env.INGESTION_DATABASE_URL?.trim()) {
    issues.push("EVENT_SCRAPER_PUBLISH=postgres requires INGESTION_DATABASE_URL");
  }
  const day = new Date().toISOString().slice(0, 10);
  const dryRunPath =
    env.EVENT_SCRAPER_DRY_RUN_PATH?.trim() || resolve(dataDir, "publish", `observations-${day}.ndjson`);

  const config: ScraperConfig = {
    databaseUrl,
    dbSchema: env.EVENT_SCRAPER_DB_SCHEMA?.trim() || "scraper",
    maxDbConnections: int(env, "EVENT_SCRAPER_DB_CONNECTIONS", 4, issues, 1, 8),
    dataDir,
    configFile: configPath,
    cities: file.cities,
    listings: file.listings,
    bandsintownArtists: file.bandsintownArtists,
    features,
    publish: { mode, dryRunPath },
    http: {
      minHostIntervalMs: int(env, "EVENT_SCRAPER_MIN_HOST_INTERVAL_MS", 5_000, issues, 1_000, 600_000),
      timeoutMs: int(env, "EVENT_SCRAPER_FETCH_TIMEOUT_MS", 20_000, issues, 1_000, 120_000),
    },
    scrape: {
      maxJobsPerRun: int(env, "EVENT_SCRAPER_MAX_JOBS", 200, issues, 1, 100_000),
      concurrency: int(env, "EVENT_SCRAPER_CONCURRENCY", 4, issues, 1, 32),
      productiveIntervalMs: int(env, "EVENT_SCRAPER_PRODUCTIVE_INTERVAL_HOURS", 24, issues, 1, 24 * 7) * HOUR,
      maxIntervalMs: int(env, "EVENT_SCRAPER_MAX_INTERVAL_DAYS", 7, issues, 1, 60) * DAY,
      llmMaxPagesPerDay: int(env, "EVENT_SCRAPER_LLM_MAX_PAGES", 300, issues, 0, 10_000),
    },
    discovery: {
      placesBudgetPerRun: int(env, "EVENT_SCRAPER_PLACES_BUDGET", 200, issues, 0, 100_000),
      placesQueries: file.placesQueries ?? [...DEFAULT_PLACES_QUERIES],
      placesMaxPages: int(env, "EVENT_SCRAPER_PLACES_MAX_PAGES", 3, issues, 1, 3),
      placesRefreshMs: int(env, "EVENT_SCRAPER_PLACES_REFRESH_DAYS", 30, issues, 1, 365) * DAY,
      osmRefreshMs: int(env, "EVENT_SCRAPER_OSM_REFRESH_DAYS", 30, issues, 1, 365) * DAY,
      listingsRefreshMs: int(env, "EVENT_SCRAPER_LISTINGS_REFRESH_DAYS", 7, issues, 1, 365) * DAY,
      bandsintownRefreshMs: int(env, "EVENT_SCRAPER_BANDSINTOWN_REFRESH_DAYS", 7, issues, 1, 365) * DAY,
      bandsintownMaxArtists: int(env, "EVENT_SCRAPER_BANDSINTOWN_MAX_ARTISTS", 50, issues, 1, 10_000),
      minProvenEvents: int(env, "EVENT_SCRAPER_MIN_PROVEN_EVENTS", 3, issues, 1, 100),
      proveLimitPerRun: int(env, "EVENT_SCRAPER_PROVE_LIMIT", 20, issues, 1, 10_000),
    },
    loop: {
      tickMs: int(env, "EVENT_SCRAPER_LOOP_TICK_SECONDS", 60, issues, 1, 86_400) * 1000,
      discoverEveryMs: int(env, "EVENT_SCRAPER_DISCOVER_EVERY_HOURS", 24, issues, 1, 24 * 30) * HOUR,
      publishEveryMs: int(env, "EVENT_SCRAPER_PUBLISH_EVERY_MINUTES", 15, issues, 1, 24 * 60) * 60_000,
    },
  };
  if (issues.length) throw new ConfigError(issues);
  return config;
}
