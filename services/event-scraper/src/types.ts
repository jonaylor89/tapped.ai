/**
 * Shared contract for the event scraper. Everything that touches the network is an injectable interface
 * here so the whole pipeline can run offline against fixtures.
 *
 * Date/time conventions used throughout:
 * - "Local" values are venue wall-clock strings WITHOUT an offset, interpreted in an IANA timezone.
 *   Accepted shapes: "YYYY-MM-DD", "YYYY-MM-DDTHH:mm", "YYYY-MM-DDTHH:mm:ss".
 *   Extractors may also emit yearless values ("--MM-DD" or "--MM-DDTHH:mm", ISO 8601 truncated form)
 *   when the page omits the year; validation infers the year.
 *   `end` and `doors` may additionally be time-only ("HH:mm") meaning "same evening as start"
 *   (validation rolls an end that is earlier than the start over to the next day).
 * - Instants (UTC) are ISO 8601 strings with "Z".
 * - Internal bookkeeping timestamps in Postgres are integer epoch milliseconds.
 * - Money is always integer cents.
 */

// ---------------------------------------------------------------------------------------------------------------------
// Core domain
// ---------------------------------------------------------------------------------------------------------------------

/** Categories we keep. "other" is classified and then dropped by validation. */
export type EventCategory = "music" | "comedy" | "open_mic" | "theater" | "dance" | "other";
export type KeptCategory = Exclude<EventCategory, "other">;
export const KEPT_CATEGORIES: readonly KeptCategory[] = ["music", "comedy", "open_mic", "theater", "dance"];

export type EventStatus = "scheduled" | "canceled" | "postponed" | "rescheduled" | "sold_out";

/** How a source is fetched/parsed. The venue always comes from the source row, never from the URL's domain. */
export type SourceKind = "html" | "ical" | "wp_tribe" | "squarespace" | "listing";
export const SOURCE_KINDS: readonly SourceKind[] = ["html", "ical", "wp_tribe", "squarespace", "listing"];

/** Read-only local snapshot of a production venue (pulled from prod, never written back). */
export interface Venue {
  id: string;
  name: string;
  address: string | null;
  lat: number | null;
  lng: number | null;
  website: string | null;
  googlePlaceId: string | null;
  /** IANA timezone, e.g. "America/Chicago". Null if unknown (sources carry their own timezone). */
  timezone: string | null;
  /** Epoch ms when this row was last pulled from production. */
  syncedAt: number;
}

export interface Source {
  id: string;
  /** Null only for kind "listing" (city calendars covering many venues). */
  venueId: string | null;
  kind: SourceKind;
  url: string;
  /** IANA timezone used to interpret local times from this source. */
  timezone: string;
  enabled: boolean;
  label: string | null;
  /** "manual" | "discovery" | "import" — free text provenance of the row. */
  origin: string;
  /** Desired refresh interval. */
  fetchIntervalMs: number;
  createdAt: number;
  updatedAt: number;
}

export interface NewSource {
  id?: string;
  venueId: string | null;
  kind: SourceKind;
  url: string;
  timezone: string;
  enabled?: boolean;
  label?: string | null;
  origin?: string;
  fetchIntervalMs?: number;
}

// ---------------------------------------------------------------------------------------------------------------------
// Fetching
// ---------------------------------------------------------------------------------------------------------------------

export interface FetchRequest {
  url: string;
  /** Conditional GET validators from the previous successful fetch. */
  etag?: string | null;
  lastModified?: string | null;
  /** Optional Accept header override (e.g. "text/calendar" or "application/json"). */
  accept?: string;
}

export interface FetchResult {
  /** URL as requested. */
  url: string;
  /** URL after redirects. */
  finalUrl: string;
  /** Every URL visited, in order, including `url` and `finalUrl`. */
  redirectChain: string[];
  status: number;
  /** True for HTTP 304; `body` is then empty and callers should reuse their previous snapshot. */
  notModified: boolean;
  /** Lower-cased header names. */
  headers: Record<string, string>;
  contentType: string | null;
  etag: string | null;
  lastModified: string | null;
  /** Raw response bytes (kept as evidence). */
  body: Uint8Array;
  /** Body decoded as text (charset from Content-Type, default UTF-8). */
  text: string;
  /** Hex sha256 of `body`. */
  sha256: string;
  /** Epoch ms. */
  fetchedAt: number;
  durationMs: number;
}

export interface HttpClient {
  /**
   * Polite GET. Throws `FetchBlockedError` (ticketing domain, robots.txt, unsupported scheme, private host)
   * before any request is made, and `FetchError` for network/timeout/size/HTTP-level failures.
   * Non-2xx statuses other than 304 are returned as results (status set), not thrown.
   */
  get(request: FetchRequest): Promise<FetchResult>;
}

/** Signature compatible with the global fetch, injectable for tests. */
export type FetchLike = (input: string | URL, init?: RequestInit) => Promise<Response>;

// ---------------------------------------------------------------------------------------------------------------------
// Extraction
// ---------------------------------------------------------------------------------------------------------------------

export interface ExtractedPrice {
  kind: "ticket" | "advance" | "door" | "other";
  /** Integer cents. */
  minCents: number | null;
  maxCents: number | null;
  /** ISO 4217, null if unstated. */
  currency: string | null;
  /** Original text, e.g. "$15 adv / $20 dos". */
  text: string | null;
}

export interface ExtractedEvent {
  title: string | null;
  /** Local start (see conventions at top). May be yearless. */
  start: string | null;
  /** IANA timezone if the source states one explicitly; validation falls back to the source timezone. */
  timezone: string | null;
  /** Absolute instant if the source provided one with an offset (e.g. JSON-LD "2026-11-07T20:00:00-06:00"). */
  startInstant: string | null;
  /** Local end, full or time-only. */
  end: string | null;
  /** Local door time, full or time-only. */
  doors: string | null;
  description: string | null;
  imageUrl: string | null;
  /** Event page on the venue's own site. */
  eventUrl: string | null;
  /** Ticket link as a string only. Never fetched, even if it is not a ticketing domain. */
  ticketUrl: string | null;
  performers: string[];
  prices: ExtractedPrice[];
  isFree: boolean | null;
  status: EventStatus | null;
  /** Extractor's category hint; validation makes the final call. */
  category: EventCategory | null;
  /** Verbatim quotes from the page supporting the facts (required for the LLM extractor). */
  evidence: string[];
  /** Name of the extractor that produced this event. */
  extractor: string;
  /** The site's own stable event id (e.g. WP post id, iCal UID), if any. */
  sourceEventId: string | null;
  /** Raw date text as seen on the page, for debugging/year inference. */
  rawDateText: string | null;
  /**
   * Where the page says the event happens (structured location). Informational only: the venue of a venue source
   * always comes from the source row. Listing sources use it to turn unknown venues into discovery candidates.
   */
  location?: ExtractedLocation | null;
}

/** Location as stated by the page (schema.org Place, iCal LOCATION, CMS venue object). */
export interface ExtractedLocation {
  name: string | null;
  address: string | null;
  lat: number | null;
  lng: number | null;
  /** Venue website/page URL if the source gives one (never fetched by extractors). */
  url: string | null;
}

/** A fetched page handed to extractors. */
export interface Page {
  url: string;
  finalUrl: string;
  contentType: string | null;
  text: string;
  body: Uint8Array;
  fetchedAt: number;
}

export interface ExtractContext {
  source: Source;
  venue: Venue | null;
  /** IANA timezone to interpret local times (source timezone, else venue timezone). */
  timezone: string;
  /** "Now" for year inference and "upcoming" checks. */
  now: Date;
  /** Present only when the LLM fallback is enabled. */
  llm?: LlmClient;
  /** For extractors that need a related endpoint on the same site (e.g. CMS JSON APIs). Polite + denylisted. */
  http?: HttpClient;
}

export interface Extractor {
  /** Stable name recorded on every event, e.g. "jsonld", "microdata", "ical", "wp_tribe", "squarespace", "llm". */
  readonly name: string;
  canHandle(page: Page, ctx: ExtractContext): boolean;
  extract(page: Page, ctx: ExtractContext): ExtractedEvent[] | Promise<ExtractedEvent[]>;
}

// ---------------------------------------------------------------------------------------------------------------------
// Validation / reconcile
// ---------------------------------------------------------------------------------------------------------------------

export interface ValidatedEvent {
  /** Stable identity within the source; see reconcile rules. */
  identityKey: string;
  sourceId: string;
  venueId: string | null;
  title: string;
  /** Fully-qualified local start "YYYY-MM-DDTHH:mm" or "YYYY-MM-DD" when no time is known. */
  startLocal: string;
  /** UTC instant of start; null when only a date is known. */
  startUtc: string | null;
  datePrecision: "instant" | "date";
  endLocal: string | null;
  endUtc: string | null;
  doorsLocal: string | null;
  timezone: string;
  description: string | null;
  imageUrl: string | null;
  eventUrl: string | null;
  ticketUrl: string | null;
  performers: string[];
  prices: ExtractedPrice[];
  isFree: boolean | null;
  status: EventStatus;
  category: KeptCategory;
  isMusic: boolean;
  evidence: string[];
  extractor: string;
  sourceEventId: string | null;
  /** Non-fatal issues (e.g. "year_inferred", "end_rolled_over"). */
  warnings: string[];
}

export type ValidationOutcome =
  | { ok: true; event: ValidatedEvent }
  | { ok: false; reasons: string[]; extracted: ExtractedEvent };

export type ChangeKind = "new" | "updated" | "unchanged" | "canceled" | "reappeared";

export type StoredEventStatus = "active" | "canceled" | "past";

export interface StoredEvent {
  id: number;
  sourceId: string;
  venueId: string | null;
  identityKey: string;
  status: StoredEventStatus;
  /** Consecutive successful fetches that did not contain this event. */
  missCount: number;
  contentHash: string;
  startLocal: string;
  startUtc: string | null;
  title: string;
  data: ValidatedEvent;
  firstSeenAt: number;
  lastSeenAt: number;
  lastChangedAt: number;
}

// ---------------------------------------------------------------------------------------------------------------------
// Venue discovery
// ---------------------------------------------------------------------------------------------------------------------

export type CandidateStatus = "new" | "resolved" | "needs_review" | "no_source" | "proving" | "promoted" | "rejected";
export const CANDIDATE_STATUSES: readonly CandidateStatus[] = [
  "new",
  "resolved",
  "needs_review",
  "no_source",
  "proving",
  "promoted",
  "rejected",
];

export type DiscoveryFeed = "google_places" | "osm" | "listing" | "bandsintown" | "manual";

export interface Candidate {
  id: number;
  name: string;
  normalizedName: string;
  address: string | null;
  city: string | null;
  lat: number | null;
  lng: number | null;
  website: string | null;
  /** Registrable domain of `website` (e.g. "thehifi.com"). A hint, never an identity. */
  websiteDomain: string | null;
  /** Canonical Google place id for this candidate, if any (all aliases live in venue_place_ids). */
  primaryPlaceId: string | null;
  discoveredFrom: DiscoveryFeed;
  /** Feed-specific raw facts (Places payloads, OSM tags, listing event refs...). */
  evidence: Record<string, unknown>;
  status: CandidateStatus;
  statusReason: string | null;
  /** Existing production venue this candidate matched, if any. */
  matchedVenueId: string | null;
  /** Event source found on the candidate's own website. */
  sourceUrl: string | null;
  sourceKind: SourceKind | null;
  timezone: string | null;
  provenEventCount: number;
  attempts: number;
  nextAttemptAt: number | null;
  createdAt: number;
  updatedAt: number;
}

export interface NewCandidate {
  name: string;
  address?: string | null;
  city?: string | null;
  lat?: number | null;
  lng?: number | null;
  website?: string | null;
  primaryPlaceId?: string | null;
  discoveredFrom: DiscoveryFeed;
  evidence?: Record<string, unknown>;
  status?: CandidateStatus;
  timezone?: string | null;
  nextAttemptAt?: number | null;
}

/** Normalized Google Places (New) result. */
export interface PlaceResult {
  placeId: string;
  displayName: string;
  /** All Google types, e.g. ["night_club","bar","point_of_interest","establishment"]. */
  types: string[];
  primaryType: string | null;
  formattedAddress: string | null;
  lat: number | null;
  lng: number | null;
  websiteUri: string | null;
  businessStatus: string | null;
}

export interface LatLng {
  lat: number;
  lng: number;
}

export interface PlacesTextSearchRequest {
  textQuery: string;
  center: LatLng;
  radiusMeters: number;
  /** The grid cell's own box; used as the `locationRestriction` rectangle when given (else center/radius). */
  bbox?: BoundingBox;
  pageToken?: string;
  /** Default 20 (API max per page). */
  pageSize?: number;
}

export interface PlacesTextSearchResponse {
  places: PlaceResult[];
  nextPageToken: string | null;
}

export interface PlacesClient {
  /** Google Places API (New) Text Search with a field mask covering PlaceResult. */
  textSearch(request: PlacesTextSearchRequest): Promise<PlacesTextSearchResponse>;
}

export interface BoundingBox {
  south: number;
  west: number;
  north: number;
  east: number;
}

export interface OverpassElement {
  /** e.g. "node/123", "way/456". */
  id: string;
  type: "node" | "way" | "relation";
  lat: number | null;
  lng: number | null;
  tags: Record<string, string>;
}

export interface OverpassClient {
  /** Runs an Overpass QL query (must request `out center tags;`-style output) and returns elements. */
  query(ql: string): Promise<OverpassElement[]>;
}

export interface BandsintownEvent {
  id: string;
  /** Local datetime as reported, e.g. "2026-11-07T20:00:00". */
  datetime: string;
  url: string | null;
  title: string | null;
  lineup: string[];
  venue: {
    name: string;
    city: string | null;
    region: string | null;
    country: string | null;
    lat: number | null;
    lng: number | null;
  };
}

export interface BandsintownClient {
  artistEvents(artistName: string): Promise<BandsintownEvent[]>;
}

// ---------------------------------------------------------------------------------------------------------------------
// LLM
// ---------------------------------------------------------------------------------------------------------------------

/** Minimal JSON Schema object (strict structured-output subset). */
export type JsonSchema = Record<string, unknown>;

export interface LlmJsonRequest {
  system: string;
  user: string;
  /** Name for the structured output schema (OpenAI `json_schema.name`). */
  schemaName: string;
  schema: JsonSchema;
  maxOutputTokens?: number;
  temperature?: number;
}

export interface LlmJsonResponse {
  /** Parsed JSON matching `schema` (callers must still validate). */
  data: unknown;
  model: string;
  inputTokens: number | null;
  outputTokens: number | null;
}

export interface LlmClient {
  completeJson(request: LlmJsonRequest): Promise<LlmJsonResponse>;
}

// ---------------------------------------------------------------------------------------------------------------------
// Publishing (the only coupling to production)
// ---------------------------------------------------------------------------------------------------------------------

export interface OutboxItem {
  id: number;
  eventId: number;
  sourceId: string;
  venueId: string | null;
  identityKey: string;
  change: ChangeKind;
  event: ValidatedEvent;
  /** Epoch ms the observation was captured (fetch time). */
  observedAt: number;
  /** sha256 of the raw page in raw_pages used as evidence. */
  evidenceSha256: string | null;
  attempts: number;
  createdAt: number;
}

export interface PublishOutcome {
  outboxId: number;
  ok: boolean;
  /** Short, secret-free message. */
  message?: string;
}

export interface Publisher {
  readonly name: string;
  /** Publishes a batch; `evidence` resolves raw page bytes by sha256 from the page store. */
  publish(
    items: OutboxItem[],
    evidence: (sha256: string) => Promise<{ bytes: Uint8Array; contentType: string | null } | null>,
  ): Promise<PublishOutcome[]>;
}

/** Read-only pull of production venues into the local snapshot. */
export interface VenueSnapshotSource {
  listVenues(): Promise<Venue[]>;
}

// ---------------------------------------------------------------------------------------------------------------------
// Runtime
// ---------------------------------------------------------------------------------------------------------------------

export interface Clock {
  now(): Date;
}

export const systemClock: Clock = { now: () => new Date() };

export type Sleep = (ms: number) => Promise<void>;
export const realSleep: Sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export type JobKind = "fetch_source" | "discover_cell" | "resolve_candidate" | "prove_candidate" | "publish";

export type JobStatus = "queued" | "leased" | "done" | "dead";

export interface Job<P = Record<string, unknown>> {
  id: number;
  kind: string;
  payload: P;
  dedupeKey: string | null;
  status: JobStatus;
  runAfter: number;
  leaseToken: string | null;
  leaseExpiresAt: number | null;
  attempts: number;
  maxAttempts: number;
  lastError: string | null;
  createdAt: number;
  updatedAt: number;
}

export type AlertKind =
  | "zero_results"
  | "fetch_failed"
  | "robots_blocked"
  | "ticketing_blocked"
  | "extract_failed"
  | "publish_failed"
  | "other";

export interface Alert {
  id: number;
  kind: AlertKind;
  sourceId: string | null;
  candidateId: number | null;
  message: string;
  details: Record<string, unknown>;
  createdAt: number;
  resolvedAt: number | null;
}
