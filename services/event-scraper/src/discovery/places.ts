/**
 * Google Places API (New) Text Search feed. Map search per city grid cell is the primary discovery feed.
 *
 * - POST https://places.googleapis.com/v1/places:searchText with an explicit X-Goog-FieldMask (billing tier is
 *   driven by the mask; we ask only for identity fields).
 * - `locationRestriction.rectangle` (the API only supports rectangles for restriction) derived from the cell.
 * - Pagination through `nextPageToken` (max 3 pages / 60 results per query).
 * - Key from GOOGLE_PLACES_API_KEY; it is sent as a header only and never logged or included in errors.
 */
import type { Db } from "../db.js";
import type {
  BoundingBox,
  Clock,
  FetchLike,
  LatLng,
  PlaceResult,
  PlacesClient,
  PlacesTextSearchRequest,
  PlacesTextSearchResponse,
  Sleep,
} from "../types.js";
import { realSleep, systemClock } from "../types.js";
import { bboxAround, type GridCell } from "./geo.js";
import { type IngestSummary, ingestPlaces } from "./resolve.js";

export const PLACES_SEARCH_TEXT_URL = "https://places.googleapis.com/v1/places:searchText";

/** Field mask covering exactly `PlaceResult` (+ pagination). */
export const PLACES_FIELD_MASK = [
  "places.id",
  "places.displayName",
  "places.types",
  "places.primaryType",
  "places.formattedAddress",
  "places.location",
  "places.websiteUri",
  "places.businessStatus",
  "nextPageToken",
].join(",");

/** Default text queries per cell. */
export const DEFAULT_PLACES_QUERIES: readonly string[] = [
  "live music venue",
  "jazz club",
  "concert hall",
  "comedy club",
  "theater",
  "music bar",
  "open mic",
];

export class PlacesApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "PlacesApiError";
  }
}

export interface GooglePlacesClientOptions {
  apiKey: string;
  fetchImpl?: FetchLike;
  endpoint?: string;
  /** Request timeout. Default 15s. */
  timeoutMs?: number;
  languageCode?: string;
  regionCode?: string;
}

interface RawPlace {
  id?: string;
  displayName?: { text?: string };
  types?: string[];
  primaryType?: string;
  formattedAddress?: string;
  location?: { latitude?: number; longitude?: number };
  websiteUri?: string;
  businessStatus?: string;
}

/** Normalizes one raw Places (New) object; returns null when it has no id or name. */
export function parsePlace(raw: RawPlace): PlaceResult | null {
  const placeId = typeof raw.id === "string" ? raw.id : null;
  const displayName = raw.displayName?.text?.trim();
  if (!placeId || !displayName) return null;
  return {
    placeId,
    displayName,
    types: Array.isArray(raw.types) ? raw.types.filter((type): type is string => typeof type === "string") : [],
    primaryType: typeof raw.primaryType === "string" ? raw.primaryType : null,
    formattedAddress: typeof raw.formattedAddress === "string" ? raw.formattedAddress : null,
    lat: typeof raw.location?.latitude === "number" ? raw.location.latitude : null,
    lng: typeof raw.location?.longitude === "number" ? raw.location.longitude : null,
    websiteUri: typeof raw.websiteUri === "string" ? raw.websiteUri : null,
    businessStatus: typeof raw.businessStatus === "string" ? raw.businessStatus : null,
  };
}

/**
 * Rectangle used for `locationRestriction`: the cell's own box when given. The box around the cell's circumscribing
 * circle is ~2x the cell's area, so neighbouring cells would share each query's 60-result cap.
 */
export function restrictionRectangle(center: LatLng, radiusMeters: number, cellBox?: BoundingBox | null) {
  const box = cellBox ?? bboxAround(center, radiusMeters);
  return {
    rectangle: {
      low: { latitude: box.south, longitude: box.west },
      high: { latitude: box.north, longitude: box.east },
    },
  };
}

export class GooglePlacesClient implements PlacesClient {
  private readonly fetchImpl: FetchLike;
  private readonly endpoint: string;

  constructor(private readonly options: GooglePlacesClientOptions) {
    if (!options.apiKey) throw new Error("Google Places API key is required");
    this.fetchImpl = options.fetchImpl ?? ((input, init) => fetch(input, init));
    this.endpoint = options.endpoint ?? PLACES_SEARCH_TEXT_URL;
  }

  async textSearch(request: PlacesTextSearchRequest): Promise<PlacesTextSearchResponse> {
    const body: Record<string, unknown> = {
      textQuery: request.textQuery,
      pageSize: Math.min(Math.max(request.pageSize ?? 20, 1), 20),
      locationRestriction: restrictionRectangle(request.center, request.radiusMeters, request.bbox),
    };
    if (request.pageToken) body.pageToken = request.pageToken;
    if (this.options.languageCode) body.languageCode = this.options.languageCode;
    if (this.options.regionCode) body.regionCode = this.options.regionCode;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.options.timeoutMs ?? 15_000);
    let response: Response;
    try {
      response = await this.fetchImpl(this.endpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": this.options.apiKey,
          "X-Goog-FieldMask": PLACES_FIELD_MASK,
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
    } catch (error) {
      throw new PlacesApiError(0, `Places request failed: ${(error as Error).name}`);
    } finally {
      clearTimeout(timer);
    }
    const text = await response.text();
    if (!response.ok) {
      let detail = "";
      try {
        const parsed = JSON.parse(text) as { error?: { status?: string } };
        detail = parsed.error?.status ? ` ${parsed.error.status}` : "";
      } catch {
        // ignore non-JSON error bodies
      }
      throw new PlacesApiError(response.status, `Places Text Search HTTP ${response.status}${detail}`);
    }
    const data = (text ? JSON.parse(text) : {}) as { places?: RawPlace[]; nextPageToken?: string };
    return {
      places: (data.places ?? []).map(parsePlace).filter((place): place is PlaceResult => place !== null),
      nextPageToken: data.nextPageToken || null,
    };
  }
}

/** Builds a client from the environment, or null when GOOGLE_PLACES_API_KEY is not set. */
export function createPlacesClientFromEnv(
  env: Record<string, string | undefined> = process.env,
  options: Omit<GooglePlacesClientOptions, "apiKey"> = {},
): GooglePlacesClient | null {
  const apiKey = env.GOOGLE_PLACES_API_KEY?.trim();
  return apiKey ? new GooglePlacesClient({ ...options, apiKey }) : null;
}

export interface CellSearchOptions {
  /**
   * Called before every request; return false to stop (the shared per-run request budget). Requests are counted as
   * they are made, including ones that fail.
   */
  beforeRequest?: () => boolean;
  queries?: readonly string[];
  /** Max pages per query. Default 3 (the API's own cap). */
  maxPages?: number;
  /** Delay between page requests. Default 1500 ms. */
  pageDelayMs?: number;
  sleep?: Sleep;
}

export interface CellSearchResult {
  places: PlaceResult[];
  requests: number;
  /** Count of permanently closed places dropped. */
  closed: number;
  /** True when `beforeRequest` stopped the search before every query/page ran. */
  truncated?: boolean;
}

/** A cell search that failed part way. Carries what the paid requests before the failure returned. */
export class CellSearchError extends Error {
  constructor(
    readonly original: unknown,
    readonly partial: CellSearchResult,
  ) {
    super(original instanceof Error ? original.message : String(original));
    this.name = "CellSearchError";
  }

  /** HTTP status of the underlying Places error (0 for network errors), or null. */
  get status(): number | null {
    return this.original instanceof PlacesApiError ? this.original.status : null;
  }
}

/** Runs every query (all pages) for one grid cell and returns unique, not-permanently-closed places. */
export async function searchCell(
  client: PlacesClient,
  cell: Pick<GridCell, "center" | "radiusMeters"> & { bbox?: BoundingBox },
  options: CellSearchOptions = {},
): Promise<CellSearchResult> {
  const queries = options.queries ?? DEFAULT_PLACES_QUERIES;
  const maxPages = options.maxPages ?? 3;
  const sleep = options.sleep ?? realSleep;
  const byId = new Map<string, PlaceResult>();
  let requests = 0;
  let closed = 0;
  const snapshot = (truncated: boolean): CellSearchResult => ({
    places: [...byId.values()],
    requests,
    closed,
    truncated,
  });
  try {
    for (const textQuery of queries) {
      let pageToken: string | undefined;
      for (let page = 0; page < maxPages; page++) {
        if (options.beforeRequest && !options.beforeRequest()) return snapshot(true);
        if (page > 0) await sleep(options.pageDelayMs ?? 1500);
        requests++;
        const response = await client.textSearch({
          textQuery,
          center: cell.center,
          radiusMeters: cell.radiusMeters,
          bbox: cell.bbox,
          pageToken,
        });
        for (const place of response.places) {
          if (place.businessStatus === "CLOSED_PERMANENTLY") {
            closed++;
            continue;
          }
          if (!byId.has(place.placeId)) byId.set(place.placeId, place);
        }
        if (!response.nextPageToken) break;
        pageToken = response.nextPageToken;
      }
    }
  } catch (error) {
    throw new CellSearchError(error, snapshot(true));
  }
  return snapshot(false);
}

export interface DiscoverPlacesCellOptions extends CellSearchOptions {
  clock?: Clock;
  radiusMeters?: number;
}

/** Searches one cell and records the clustered results as candidates (aliases included). */
export async function discoverPlacesCell(
  db: Db,
  client: PlacesClient,
  cell: GridCell,
  options: DiscoverPlacesCellOptions = {},
): Promise<IngestSummary & { requests: number; truncated: boolean }> {
  const ingest = (search: CellSearchResult) => {
    const summary = ingestPlaces(db, search.places, {
      city: cell.city,
      timezone: cell.timezone,
      area: cell.bbox,
      radiusMeters: options.radiusMeters,
      now: (options.clock ?? systemClock).now().getTime(),
      provenance: { cell: cell.id },
    });
    return {
      ...summary,
      closed: summary.closed + search.closed,
      places: summary.places + search.closed,
      requests: search.requests,
      truncated: search.truncated ?? false,
    };
  };
  let search: CellSearchResult;
  try {
    search = await searchCell(client, cell, options);
  } catch (error) {
    // Keep what the paid requests before the failure returned; the cell is retried later.
    if (error instanceof CellSearchError && error.partial.places.length) ingest(error.partial);
    throw error;
  }
  return ingest(search);
}
