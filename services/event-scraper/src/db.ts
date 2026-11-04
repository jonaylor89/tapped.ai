/**
 * The scraper's own working state, in one local SQLite file (node:sqlite, no native deps).
 * Production Postgres is never used as the queue; only the explicit publish step talks to production.
 *
 * All bookkeeping timestamps are integer epoch milliseconds.
 */
import { createHash, randomUUID } from "node:crypto";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { DatabaseSync, type SQLInputValue, type SQLOutputValue } from "node:sqlite";
import type {
  Alert,
  AlertKind,
  Candidate,
  CandidateStatus,
  ChangeKind,
  DiscoveryFeed,
  Job,
  JobStatus,
  NewCandidate,
  NewSource,
  OutboxItem,
  Source,
  SourceKind,
  StoredEvent,
  StoredEventStatus,
  ValidatedEvent,
  Venue,
} from "./types.js";
import { canonicalUrl, registrableDomain } from "./url.js";

export type Db = DatabaseSync;
type Row = Record<string, SQLOutputValue>;

// ---------------------------------------------------------------------------------------------------------------------
// Migrations
// ---------------------------------------------------------------------------------------------------------------------

export interface Migration {
  version: number;
  name: string;
  sql: string;
}

export const MIGRATIONS: readonly Migration[] = [
  {
    version: 1,
    name: "initial",
    sql: `
CREATE TABLE venues (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  address TEXT,
  lat REAL,
  lng REAL,
  website TEXT,
  google_place_id TEXT,
  timezone TEXT,
  synced_at INTEGER NOT NULL
);
CREATE INDEX venues_google_place_id ON venues(google_place_id);

CREATE TABLE sources (
  id TEXT PRIMARY KEY,
  venue_id TEXT,
  kind TEXT NOT NULL CHECK (kind IN ('html','ical','wp_tribe','squarespace','listing')),
  url TEXT NOT NULL UNIQUE,
  timezone TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  label TEXT,
  origin TEXT NOT NULL DEFAULT 'manual',
  fetch_interval_ms INTEGER NOT NULL DEFAULT 21600000,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  CHECK (venue_id IS NOT NULL OR kind = 'listing')
);
CREATE INDEX sources_venue ON sources(venue_id);

CREATE TABLE fetch_state (
  source_id TEXT PRIMARY KEY REFERENCES sources(id) ON DELETE CASCADE,
  etag TEXT,
  last_modified TEXT,
  content_hash TEXT,
  last_status INTEGER,
  last_fetch_at INTEGER,
  last_success_at INTEGER,
  last_error TEXT,
  consecutive_failures INTEGER NOT NULL DEFAULT 0,
  consecutive_zero_results INTEGER NOT NULL DEFAULT 0,
  successful_fetches INTEGER NOT NULL DEFAULT 0,
  last_event_count INTEGER,
  max_event_count INTEGER NOT NULL DEFAULT 0,
  last_extractor TEXT
);

CREATE TABLE raw_pages (
  sha256 TEXT PRIMARY KEY,
  url TEXT NOT NULL,
  content_type TEXT,
  size INTEGER NOT NULL,
  bytes BLOB NOT NULL,
  first_seen_at INTEGER NOT NULL
);

CREATE TABLE jobs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  payload TEXT NOT NULL DEFAULT '{}',
  dedupe_key TEXT,
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','leased','done','dead')),
  run_after INTEGER NOT NULL,
  lease_token TEXT,
  lease_expires_at INTEGER,
  attempts INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 5,
  last_error TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  finished_at INTEGER
);
CREATE INDEX jobs_claim ON jobs(status, run_after);
CREATE UNIQUE INDEX jobs_open_dedupe ON jobs(dedupe_key) WHERE dedupe_key IS NOT NULL AND status IN ('queued','leased');

CREATE TABLE events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
  venue_id TEXT,
  identity_key TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','canceled','past')),
  miss_count INTEGER NOT NULL DEFAULT 0,
  content_hash TEXT NOT NULL,
  start_local TEXT NOT NULL,
  start_utc TEXT,
  title TEXT NOT NULL,
  data TEXT NOT NULL,
  first_seen_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  last_changed_at INTEGER NOT NULL,
  UNIQUE (source_id, identity_key)
);
CREATE INDEX events_venue_start ON events(venue_id, start_local);

CREATE TABLE event_changes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_id INTEGER NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  source_id TEXT NOT NULL,
  identity_key TEXT NOT NULL,
  change TEXT NOT NULL,
  before TEXT,
  after TEXT,
  at INTEGER NOT NULL
);
CREATE INDEX event_changes_event ON event_changes(event_id);

CREATE TABLE alerts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  source_id TEXT,
  candidate_id INTEGER,
  message TEXT NOT NULL,
  details TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  resolved_at INTEGER
);
CREATE INDEX alerts_open ON alerts(resolved_at, kind);

CREATE TABLE venue_candidates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  normalized_name TEXT NOT NULL,
  address TEXT,
  city TEXT,
  lat REAL,
  lng REAL,
  website TEXT,
  website_domain TEXT,
  primary_place_id TEXT,
  discovered_from TEXT NOT NULL,
  evidence TEXT NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'new'
    CHECK (status IN ('new','resolved','needs_review','no_source','proving','promoted','rejected')),
  status_reason TEXT,
  matched_venue_id TEXT,
  source_url TEXT,
  source_kind TEXT,
  timezone TEXT,
  proven_event_count INTEGER NOT NULL DEFAULT 0,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX venue_candidates_status ON venue_candidates(status, next_attempt_at);
CREATE INDEX venue_candidates_domain ON venue_candidates(website_domain);
CREATE INDEX venue_candidates_name ON venue_candidates(normalized_name);

CREATE TABLE venue_place_ids (
  place_id TEXT PRIMARY KEY,
  provider TEXT NOT NULL DEFAULT 'google',
  venue_id TEXT,
  candidate_id INTEGER REFERENCES venue_candidates(id) ON DELETE CASCADE,
  is_canonical INTEGER NOT NULL DEFAULT 0,
  types TEXT NOT NULL DEFAULT '[]',
  display_name TEXT,
  lat REAL,
  lng REAL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  CHECK (venue_id IS NOT NULL OR candidate_id IS NOT NULL)
);
CREATE INDEX venue_place_ids_venue ON venue_place_ids(venue_id);
CREATE INDEX venue_place_ids_candidate ON venue_place_ids(candidate_id);

CREATE TABLE publish_outbox (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_id INTEGER NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  source_id TEXT NOT NULL,
  venue_id TEXT,
  identity_key TEXT NOT NULL,
  change TEXT NOT NULL,
  payload TEXT NOT NULL,
  payload_hash TEXT NOT NULL,
  observed_at INTEGER NOT NULL,
  evidence_sha256 TEXT,
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at INTEGER NOT NULL,
  published_at INTEGER,
  UNIQUE (event_id, payload_hash)
);
CREATE INDEX publish_outbox_pending ON publish_outbox(published_at, id);
`,
  },
  {
    version: 2,
    name: "kv_and_host_slots",
    sql: `
CREATE TABLE kv (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE host_slots (
  host TEXT PRIMARY KEY,
  next_slot_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
`,
  },
  {
    version: 3,
    name: "known_events",
    sql: `
-- Events production Postgres already has (any crawler). Replaced wholesale by every sync; an incoming event matching
-- one of these is never stored, reconciled or published.
CREATE TABLE known_events (
  origin TEXT NOT NULL,
  origin_key TEXT NOT NULL,
  venue_id TEXT,
  start_utc TEXT NOT NULL,
  norm_title TEXT NOT NULL,
  url_key TEXT,
  PRIMARY KEY (origin, origin_key)
);
CREATE INDEX known_events_venue_start ON known_events(venue_id, start_utc);
CREATE INDEX known_events_url ON known_events(url_key) WHERE url_key IS NOT NULL;
`,
  },
];

export const SCHEMA_VERSION = MIGRATIONS[MIGRATIONS.length - 1]?.version ?? 0;

export function schemaVersion(db: Db): number {
  const row = db.prepare("PRAGMA user_version").get() as Row | undefined;
  return Number(row?.user_version ?? 0);
}

/** Applies pending migrations in order, each in its own transaction. Idempotent. */
export function migrate(db: Db, migrations: readonly Migration[] = MIGRATIONS): number {
  let current = schemaVersion(db);
  for (const migration of [...migrations].sort((a, b) => a.version - b.version)) {
    if (migration.version <= current) continue;
    transaction(db, () => {
      db.exec(migration.sql);
      db.exec(`PRAGMA user_version = ${Math.trunc(migration.version)}`);
    });
    current = migration.version;
  }
  return current;
}

/** Opens (creating if needed) the scraper database and migrates it. Use ":memory:" for tests. */
export function openDb(path: string): Db {
  if (path !== ":memory:") mkdirSync(dirname(path), { recursive: true });
  const db = new DatabaseSync(path);
  db.exec("PRAGMA foreign_keys = ON");
  db.exec("PRAGMA busy_timeout = 5000");
  if (path !== ":memory:") {
    db.exec("PRAGMA journal_mode = WAL");
    db.exec("PRAGMA synchronous = NORMAL");
  }
  migrate(db);
  return db;
}

/** Runs `fn` inside BEGIN IMMEDIATE/COMMIT; rolls back on throw. Nested calls join the outer transaction. */
export function transaction<T>(db: Db, fn: () => T): T {
  if (db.isTransaction) return fn();
  db.exec("BEGIN IMMEDIATE");
  try {
    const result = fn();
    db.exec("COMMIT");
    return result;
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Row helpers
// ---------------------------------------------------------------------------------------------------------------------

function str(value: SQLOutputValue | undefined): string {
  return value == null ? "" : String(value);
}
function strOrNull(value: SQLOutputValue | undefined): string | null {
  return value == null ? null : String(value);
}
function num(value: SQLOutputValue | undefined): number {
  return value == null ? 0 : Number(value);
}
function numOrNull(value: SQLOutputValue | undefined): number | null {
  return value == null ? null : Number(value);
}
function json<T>(value: SQLOutputValue | undefined, fallback: T): T {
  if (value == null) return fallback;
  try {
    return JSON.parse(String(value)) as T;
  } catch {
    return fallback;
  }
}
function all(db: Db, sql: string, ...params: SQLInputValue[]): Row[] {
  return db.prepare(sql).all(...params) as Row[];
}
function one(db: Db, sql: string, ...params: SQLInputValue[]): Row | undefined {
  return db.prepare(sql).get(...params) as Row | undefined;
}
function run(db: Db, sql: string, ...params: SQLInputValue[]) {
  return db.prepare(sql).run(...params);
}
const bool = (value: boolean): number => (value ? 1 : 0);

export function sha256Hex(value: string | Uint8Array): string {
  return createHash("sha256").update(value).digest("hex");
}

/** Lower-case, strip accents/punctuation, collapse whitespace and a leading "the". */
export function normalizeName(name: string): string {
  return name
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/^the\s+/, "")
    .replace(/\s+/g, " ");
}

// ---------------------------------------------------------------------------------------------------------------------
// Venues (local read-only snapshot of production)
// ---------------------------------------------------------------------------------------------------------------------

function toVenue(row: Row): Venue {
  return {
    id: str(row.id),
    name: str(row.name),
    address: strOrNull(row.address),
    lat: numOrNull(row.lat),
    lng: numOrNull(row.lng),
    website: strOrNull(row.website),
    googlePlaceId: strOrNull(row.google_place_id),
    timezone: strOrNull(row.timezone),
    syncedAt: num(row.synced_at),
  };
}

export function upsertVenues(db: Db, venues: Venue[]): number {
  const statement = db.prepare(
    `INSERT INTO venues (id,name,address,lat,lng,website,google_place_id,timezone,synced_at)
     VALUES (?,?,?,?,?,?,?,?,?)
     ON CONFLICT(id) DO UPDATE SET name=excluded.name, address=excluded.address, lat=excluded.lat, lng=excluded.lng,
       website=excluded.website, google_place_id=excluded.google_place_id,
       timezone=COALESCE(excluded.timezone, venues.timezone), synced_at=excluded.synced_at`,
  );
  return transaction(db, () => {
    for (const venue of venues) {
      statement.run(
        venue.id,
        venue.name,
        venue.address,
        venue.lat,
        venue.lng,
        venue.website,
        venue.googlePlaceId,
        venue.timezone,
        venue.syncedAt,
      );
    }
    return venues.length;
  });
}

export function getVenue(db: Db, id: string): Venue | null {
  const row = one(db, "SELECT * FROM venues WHERE id=?", id);
  return row ? toVenue(row) : null;
}

export function listVenues(db: Db): Venue[] {
  return all(db, "SELECT * FROM venues ORDER BY name").map(toVenue);
}

// ---------------------------------------------------------------------------------------------------------------------
// Sources
// ---------------------------------------------------------------------------------------------------------------------

export const DEFAULT_FETCH_INTERVAL_MS = 6 * 60 * 60 * 1000;

function toSource(row: Row): Source {
  return {
    id: str(row.id),
    venueId: strOrNull(row.venue_id),
    kind: str(row.kind) as SourceKind,
    url: str(row.url),
    timezone: str(row.timezone),
    enabled: num(row.enabled) === 1,
    label: strOrNull(row.label),
    origin: str(row.origin),
    fetchIntervalMs: num(row.fetch_interval_ms),
    createdAt: num(row.created_at),
    updatedAt: num(row.updated_at),
  };
}

/** Inserts a source (URL canonicalized). Returns the existing row unchanged if the URL is already registered. */
export function addSource(db: Db, input: NewSource, now: number = Date.now()): Source {
  const url = canonicalUrl(input.url);
  if (!url) throw new Error(`Invalid source URL: ${input.url}`);
  if (input.venueId == null && input.kind !== "listing") throw new Error("Only listing sources may omit venueId");
  const existing = getSourceByUrl(db, url);
  if (existing) return existing;
  const id = input.id ?? randomUUID();
  run(
    db,
    `INSERT INTO sources (id,venue_id,kind,url,timezone,enabled,label,origin,fetch_interval_ms,created_at,updated_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
    id,
    input.venueId,
    input.kind,
    url,
    input.timezone,
    bool(input.enabled ?? true),
    input.label ?? null,
    input.origin ?? "manual",
    input.fetchIntervalMs ?? DEFAULT_FETCH_INTERVAL_MS,
    now,
    now,
  );
  return getSource(db, id) as Source;
}

export function getSource(db: Db, id: string): Source | null {
  const row = one(db, "SELECT * FROM sources WHERE id=?", id);
  return row ? toSource(row) : null;
}

export function getSourceByUrl(db: Db, url: string): Source | null {
  const canonical = canonicalUrl(url) ?? url;
  const row = one(db, "SELECT * FROM sources WHERE url=?", canonical);
  return row ? toSource(row) : null;
}

export function listSources(db: Db, filter: { enabled?: boolean; venueId?: string; kind?: SourceKind } = {}): Source[] {
  const where: string[] = [];
  const params: SQLInputValue[] = [];
  if (filter.enabled !== undefined) {
    where.push("enabled=?");
    params.push(bool(filter.enabled));
  }
  if (filter.venueId !== undefined) {
    where.push("venue_id=?");
    params.push(filter.venueId);
  }
  if (filter.kind !== undefined) {
    where.push("kind=?");
    params.push(filter.kind);
  }
  const clause = where.length ? `WHERE ${where.join(" AND ")}` : "";
  return all(db, `SELECT * FROM sources ${clause} ORDER BY created_at, id`, ...params).map(toSource);
}

export function setSourceEnabled(db: Db, id: string, enabled: boolean, now: number = Date.now()): void {
  run(db, "UPDATE sources SET enabled=?, updated_at=? WHERE id=?", bool(enabled), now, id);
}

/** Enabled sources whose last fetch is older than their interval (or never fetched). */
export function dueSources(db: Db, now: number = Date.now()): Source[] {
  return all(
    db,
    `SELECT s.* FROM sources s LEFT JOIN fetch_state f ON f.source_id = s.id
     WHERE s.enabled = 1 AND (f.last_fetch_at IS NULL OR f.last_fetch_at + s.fetch_interval_ms <= ?)
     ORDER BY COALESCE(f.last_fetch_at, 0), s.id`,
    now,
  ).map(toSource);
}

// ---------------------------------------------------------------------------------------------------------------------
// Fetch state
// ---------------------------------------------------------------------------------------------------------------------

export interface FetchState {
  sourceId: string;
  etag: string | null;
  lastModified: string | null;
  contentHash: string | null;
  lastStatus: number | null;
  lastFetchAt: number | null;
  lastSuccessAt: number | null;
  lastError: string | null;
  consecutiveFailures: number;
  consecutiveZeroResults: number;
  successfulFetches: number;
  lastEventCount: number | null;
  maxEventCount: number;
  lastExtractor: string | null;
}

function toFetchState(row: Row): FetchState {
  return {
    sourceId: str(row.source_id),
    etag: strOrNull(row.etag),
    lastModified: strOrNull(row.last_modified),
    contentHash: strOrNull(row.content_hash),
    lastStatus: numOrNull(row.last_status),
    lastFetchAt: numOrNull(row.last_fetch_at),
    lastSuccessAt: numOrNull(row.last_success_at),
    lastError: strOrNull(row.last_error),
    consecutiveFailures: num(row.consecutive_failures),
    consecutiveZeroResults: num(row.consecutive_zero_results),
    successfulFetches: num(row.successful_fetches),
    lastEventCount: numOrNull(row.last_event_count),
    maxEventCount: num(row.max_event_count),
    lastExtractor: strOrNull(row.last_extractor),
  };
}

export function emptyFetchState(sourceId: string): FetchState {
  return {
    sourceId,
    etag: null,
    lastModified: null,
    contentHash: null,
    lastStatus: null,
    lastFetchAt: null,
    lastSuccessAt: null,
    lastError: null,
    consecutiveFailures: 0,
    consecutiveZeroResults: 0,
    successfulFetches: 0,
    lastEventCount: null,
    maxEventCount: 0,
    lastExtractor: null,
  };
}

export function getFetchState(db: Db, sourceId: string): FetchState {
  const row = one(db, "SELECT * FROM fetch_state WHERE source_id=?", sourceId);
  return row ? toFetchState(row) : emptyFetchState(sourceId);
}

/** Merges `patch` into the current state and writes it. Returns the new state. */
export function saveFetchState(db: Db, sourceId: string, patch: Partial<Omit<FetchState, "sourceId">>): FetchState {
  const next: FetchState = { ...getFetchState(db, sourceId), ...patch, sourceId };
  run(
    db,
    `INSERT INTO fetch_state (source_id,etag,last_modified,content_hash,last_status,last_fetch_at,last_success_at,
       last_error,consecutive_failures,consecutive_zero_results,successful_fetches,last_event_count,max_event_count,
       last_extractor)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
     ON CONFLICT(source_id) DO UPDATE SET etag=excluded.etag, last_modified=excluded.last_modified,
       content_hash=excluded.content_hash, last_status=excluded.last_status, last_fetch_at=excluded.last_fetch_at,
       last_success_at=excluded.last_success_at, last_error=excluded.last_error,
       consecutive_failures=excluded.consecutive_failures, consecutive_zero_results=excluded.consecutive_zero_results,
       successful_fetches=excluded.successful_fetches, last_event_count=excluded.last_event_count,
       max_event_count=excluded.max_event_count, last_extractor=excluded.last_extractor`,
    next.sourceId,
    next.etag,
    next.lastModified,
    next.contentHash,
    next.lastStatus,
    next.lastFetchAt,
    next.lastSuccessAt,
    next.lastError,
    next.consecutiveFailures,
    next.consecutiveZeroResults,
    next.successfulFetches,
    next.lastEventCount,
    next.maxEventCount,
    next.lastExtractor,
  );
  return next;
}

// ---------------------------------------------------------------------------------------------------------------------
// Raw pages (evidence bytes, content-addressed)
// ---------------------------------------------------------------------------------------------------------------------

export function putRawPage(
  db: Db,
  page: { sha256?: string; url: string; contentType: string | null; bytes: Uint8Array },
  now: number = Date.now(),
): string {
  const sha = page.sha256 ?? sha256Hex(page.bytes);
  run(
    db,
    `INSERT INTO raw_pages (sha256,url,content_type,size,bytes,first_seen_at) VALUES (?,?,?,?,?,?)
     ON CONFLICT(sha256) DO NOTHING`,
    sha,
    page.url,
    page.contentType,
    page.bytes.byteLength,
    page.bytes,
    now,
  );
  return sha;
}

export function getRawPage(
  db: Db,
  sha256: string,
): { sha256: string; url: string; contentType: string | null; bytes: Uint8Array } | null {
  const row = one(db, "SELECT * FROM raw_pages WHERE sha256=?", sha256);
  if (!row) return null;
  return {
    sha256: str(row.sha256),
    url: str(row.url),
    contentType: strOrNull(row.content_type),
    bytes: row.bytes as Uint8Array,
  };
}

/** Deletes raw pages older than `before` that are no longer referenced by fetch_state or unpublished outbox rows. */
export function pruneRawPages(db: Db, before: number): number {
  const result = run(
    db,
    `DELETE FROM raw_pages WHERE first_seen_at < ?
       AND sha256 NOT IN (SELECT content_hash FROM fetch_state WHERE content_hash IS NOT NULL)
       AND sha256 NOT IN (SELECT evidence_sha256 FROM publish_outbox WHERE published_at IS NULL AND evidence_sha256 IS NOT NULL)`,
    before,
  );
  return Number(result.changes);
}

// ---------------------------------------------------------------------------------------------------------------------
// Job queue with leases
// ---------------------------------------------------------------------------------------------------------------------

function toJob<P>(row: Row): Job<P> {
  return {
    id: num(row.id),
    kind: str(row.kind),
    payload: json<P>(row.payload, {} as P),
    dedupeKey: strOrNull(row.dedupe_key),
    status: str(row.status) as JobStatus,
    runAfter: num(row.run_after),
    leaseToken: strOrNull(row.lease_token),
    leaseExpiresAt: numOrNull(row.lease_expires_at),
    attempts: num(row.attempts),
    maxAttempts: num(row.max_attempts),
    lastError: strOrNull(row.last_error),
    createdAt: num(row.created_at),
    updatedAt: num(row.updated_at),
  };
}

export interface EnqueueOptions {
  runAfter?: number;
  /** While a job with this key is queued/leased, enqueueing again returns the existing job. */
  dedupeKey?: string | null;
  maxAttempts?: number;
  now?: number;
}

export function enqueueJob<P extends object>(db: Db, kind: string, payload: P, options: EnqueueOptions = {}): Job<P> {
  const now = options.now ?? Date.now();
  return transaction(db, () => {
    if (options.dedupeKey) {
      const existing = one(
        db,
        "SELECT * FROM jobs WHERE dedupe_key=? AND status IN ('queued','leased')",
        options.dedupeKey,
      );
      if (existing) return toJob<P>(existing);
    }
    const result = run(
      db,
      `INSERT INTO jobs (kind,payload,dedupe_key,status,run_after,max_attempts,created_at,updated_at)
       VALUES (?,?,?,'queued',?,?,?,?)`,
      kind,
      JSON.stringify(payload),
      options.dedupeKey ?? null,
      options.runAfter ?? now,
      options.maxAttempts ?? 5,
      now,
      now,
    );
    return toJob<P>(one(db, "SELECT * FROM jobs WHERE id=?", Number(result.lastInsertRowid)) as Row);
  });
}

export interface ClaimOptions {
  kinds?: string[];
  /** Only jobs with one of these dedupe keys (e.g. the feed units the current config still wants). */
  dedupeKeys?: string[];
  leaseMs?: number;
  now?: number;
}

/**
 * Atomically leases the next runnable job: queued with run_after <= now, or leased with an expired lease
 * (the previous worker crashed). Increments attempts. Returns null if nothing is runnable.
 */
export function claimJob<P = Record<string, unknown>>(db: Db, options: ClaimOptions = {}): Job<P> | null {
  const now = options.now ?? Date.now();
  const leaseMs = options.leaseMs ?? 5 * 60 * 1000;
  const token = randomUUID();
  const kinds = options.kinds ?? [];
  const kindClause = kinds.length ? `AND kind IN (${kinds.map(() => "?").join(",")})` : "";
  const keys = options.dedupeKeys;
  if (keys && !keys.length) return null;
  const keyClause = keys ? `AND dedupe_key IN (SELECT value FROM json_each(?))` : "";
  return transaction(db, () => {
    const row = one(
      db,
      `UPDATE jobs SET status='leased', lease_token=?, lease_expires_at=?, attempts=attempts+1, updated_at=?
       WHERE id = (
         SELECT id FROM jobs
         WHERE ((status='queued' AND run_after <= ?) OR (status='leased' AND lease_expires_at <= ?)) ${kindClause}
           ${keyClause}
         ORDER BY run_after, id LIMIT 1
       )
       RETURNING *`,
      token,
      now + leaseMs,
      now,
      now,
      now,
      ...kinds,
      ...(keys ? [JSON.stringify(keys)] : []),
    );
    return row ? toJob<P>(row) : null;
  });
}

/** Extends a lease held by `token`. Returns false if the lease was lost. */
export function extendLease(db: Db, id: number, token: string, leaseMs: number, now: number = Date.now()): boolean {
  const result = run(
    db,
    "UPDATE jobs SET lease_expires_at=?, updated_at=? WHERE id=? AND lease_token=? AND status='leased'",
    now + leaseMs,
    now,
    id,
    token,
  );
  return Number(result.changes) === 1;
}

/** Marks a leased job done. Returns false if the lease was lost (another worker reclaimed it). */
export function finishJob(db: Db, id: number, token: string, now: number = Date.now()): boolean {
  const result = run(
    db,
    `UPDATE jobs SET status='done', lease_token=NULL, lease_expires_at=NULL, finished_at=?, updated_at=?, last_error=NULL
     WHERE id=? AND lease_token=? AND status='leased'`,
    now,
    now,
    id,
    token,
  );
  return Number(result.changes) === 1;
}

/** Default retry backoff: 1m, 4m, 16m, ... capped at 6h. */
export function defaultBackoffMs(attempts: number): number {
  return Math.min(60_000 * 4 ** Math.max(0, attempts - 1), 6 * 60 * 60 * 1000);
}

/**
 * Records a failure for a leased job. Requeues with backoff, or marks it 'dead' once attempts reach max_attempts
 * (or when `retry` is false). Returns the resulting status, or null if the lease was lost.
 */
export function failJob(
  db: Db,
  id: number,
  token: string,
  error: string,
  options: { now?: number; retry?: boolean; retryAfterMs?: number } = {},
): JobStatus | null {
  const now = options.now ?? Date.now();
  return transaction(db, () => {
    const row = one(db, "SELECT * FROM jobs WHERE id=? AND lease_token=? AND status='leased'", id, token);
    if (!row) return null;
    const job = toJob(row);
    const dead = options.retry === false || job.attempts >= job.maxAttempts;
    const status: JobStatus = dead ? "dead" : "queued";
    run(
      db,
      `UPDATE jobs SET status=?, lease_token=NULL, lease_expires_at=NULL, last_error=?, run_after=?, updated_at=?,
         finished_at=?
       WHERE id=?`,
      status,
      error.slice(0, 2000),
      dead ? job.runAfter : now + (options.retryAfterMs ?? defaultBackoffMs(job.attempts)),
      now,
      dead ? now : null,
      id,
    );
    return status;
  });
}

export function getJob<P = Record<string, unknown>>(db: Db, id: number): Job<P> | null {
  const row = one(db, "SELECT * FROM jobs WHERE id=?", id);
  return row ? toJob<P>(row) : null;
}

export function countJobs(db: Db, filter: { status?: JobStatus; kind?: string } = {}): number {
  const where: string[] = [];
  const params: SQLInputValue[] = [];
  if (filter.status) {
    where.push("status=?");
    params.push(filter.status);
  }
  if (filter.kind) {
    where.push("kind=?");
    params.push(filter.kind);
  }
  const clause = where.length ? `WHERE ${where.join(" AND ")}` : "";
  return num(one(db, `SELECT COUNT(*) AS n FROM jobs ${clause}`, ...params)?.n);
}

/**
 * Finishes queued jobs of `kind` whose dedupe key is not in `keep` (units removed from the configuration), so they
 * never run or reschedule themselves again. Leased jobs are left to their worker. Returns the number retired.
 */
export function retireJobs(db: Db, kind: string, keep: Iterable<string>, now: number = Date.now()): number {
  const result = run(
    db,
    `UPDATE jobs SET status='done', finished_at=?, updated_at=?, last_error='retired: no longer configured'
     WHERE kind=? AND status='queued' AND (dedupe_key IS NULL OR dedupe_key NOT IN (SELECT value FROM json_each(?)))`,
    now,
    now,
    kind,
    JSON.stringify([...keep]),
  );
  return Number(result.changes);
}

/** Deletes finished (done/dead) jobs older than `before`. */
export function pruneJobs(db: Db, before: number): number {
  return Number(run(db, "DELETE FROM jobs WHERE status IN ('done','dead') AND updated_at < ?", before).changes);
}

// ---------------------------------------------------------------------------------------------------------------------
// Small key/value state (housekeeping timestamps, daily usage counters)
// ---------------------------------------------------------------------------------------------------------------------

export function getKv(db: Db, key: string): string | null {
  return strOrNull(one(db, "SELECT value FROM kv WHERE key=?", key)?.value);
}

export function setKv(db: Db, key: string, value: string, now: number = Date.now()): void {
  run(
    db,
    "INSERT INTO kv (key,value,updated_at) VALUES (?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at",
    key,
    value,
    now,
  );
}

/**
 * Atomically adds `by` to a numeric counter if the result stays <= `max`. Returns true when consumed. Used for cost
 * caps shared by every process on this SQLite file (e.g. LLM pages per day).
 */
export function consumeCounter(db: Db, key: string, max: number, now: number = Date.now(), by = 1): boolean {
  return transaction(db, () => {
    const current = Number(getKv(db, key) ?? 0);
    if (current + by > max) return false;
    setKv(db, key, String(current + by), now);
    return true;
  });
}

/** Deletes kv rows whose key starts with `prefix` and that were last written before `before`. */
export function pruneKv(db: Db, prefix: string, before: number): number {
  return Number(
    run(db, "DELETE FROM kv WHERE substr(key,1,?)=? AND updated_at < ?", prefix.length, prefix, before).changes,
  );
}

// ---------------------------------------------------------------------------------------------------------------------
// Per-host politeness slots shared by every process using this SQLite file
// ---------------------------------------------------------------------------------------------------------------------

/**
 * Reserves the next request slot for `host`: returns the slot time (>= now) and moves the host's next free slot to
 * slot + interval, under BEGIN IMMEDIATE so concurrent processes (run-once and discover) never share a slot.
 */
export function reserveHostSlot(db: Db, host: string, now: number, intervalMs: number): number {
  return transaction(db, () => {
    const next = numOrNull(one(db, "SELECT next_slot_at FROM host_slots WHERE host=?", host)?.next_slot_at);
    const slot = Math.max(now, next ?? 0);
    run(
      db,
      `INSERT INTO host_slots (host,next_slot_at,updated_at) VALUES (?,?,?)
       ON CONFLICT(host) DO UPDATE SET next_slot_at=excluded.next_slot_at, updated_at=excluded.updated_at`,
      host,
      slot + intervalMs,
      now,
    );
    return slot;
  });
}

/** Pushes a host's next free slot to at least `until` (Retry-After). */
export function deferHostSlot(db: Db, host: string, until: number, now: number = Date.now()): void {
  run(
    db,
    `INSERT INTO host_slots (host,next_slot_at,updated_at) VALUES (?,?,?)
     ON CONFLICT(host) DO UPDATE SET next_slot_at=MAX(host_slots.next_slot_at, excluded.next_slot_at),
       updated_at=excluded.updated_at`,
    host,
    until,
    now,
  );
}

/** The SQLite-backed politeness slot store for the HTTP client (shared by run-once, discover and loop). */
export function hostSlotStore(db: Db): {
  reserve(host: string, now: number, intervalMs: number): number;
  defer(host: string, until: number, now: number): void;
} {
  return {
    reserve: (host, now, intervalMs) => reserveHostSlot(db, host, now, intervalMs),
    defer: (host, until, now) => deferHostSlot(db, host, until, now),
  };
}

/** Deletes slots that are long in the past. */
export function pruneHostSlots(db: Db, before: number): number {
  return Number(run(db, "DELETE FROM host_slots WHERE next_slot_at < ?", before).changes);
}

// ---------------------------------------------------------------------------------------------------------------------
// Event snapshot + changes
// ---------------------------------------------------------------------------------------------------------------------

function toStoredEvent(row: Row): StoredEvent {
  return {
    id: num(row.id),
    sourceId: str(row.source_id),
    venueId: strOrNull(row.venue_id),
    identityKey: str(row.identity_key),
    status: str(row.status) as StoredEventStatus,
    missCount: num(row.miss_count),
    contentHash: str(row.content_hash),
    startLocal: str(row.start_local),
    startUtc: strOrNull(row.start_utc),
    title: str(row.title),
    data: json<ValidatedEvent>(row.data, {} as ValidatedEvent),
    firstSeenAt: num(row.first_seen_at),
    lastSeenAt: num(row.last_seen_at),
    lastChangedAt: num(row.last_changed_at),
  };
}

/** Stable content hash of the publishable facts of a validated event (ignores evidence/warnings ordering noise). */
export function eventContentHash(event: ValidatedEvent): string {
  const { warnings: _warnings, evidence: _evidence, ...facts } = event;
  return sha256Hex(stableStringify(facts));
}

/** JSON.stringify with object keys sorted at every level (undefined members dropped). */
export function stableStringify(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value) ?? "null";
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([, member]) => member !== undefined)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  return `{${entries.map(([key, member]) => `${JSON.stringify(key)}:${stableStringify(member)}`).join(",")}}`;
}

export function listSourceEvents(db: Db, sourceId: string, statuses?: StoredEventStatus[]): StoredEvent[] {
  const filter = statuses?.length ? `AND status IN (${statuses.map(() => "?").join(",")})` : "";
  return all(
    db,
    `SELECT * FROM events WHERE source_id=? ${filter} ORDER BY start_local, id`,
    sourceId,
    ...(statuses ?? []),
  ).map(toStoredEvent);
}

export function getEvent(db: Db, id: number): StoredEvent | null {
  const row = one(db, "SELECT * FROM events WHERE id=?", id);
  return row ? toStoredEvent(row) : null;
}

export function getEventByIdentity(db: Db, sourceId: string, identityKey: string): StoredEvent | null {
  const row = one(db, "SELECT * FROM events WHERE source_id=? AND identity_key=?", sourceId, identityKey);
  return row ? toStoredEvent(row) : null;
}

/** Inserts or replaces the snapshot row for (source, identity). Resets miss_count. Returns the stored row. */
export function upsertEvent(
  db: Db,
  event: ValidatedEvent,
  options: { status?: StoredEventStatus; now?: number; changed?: boolean } = {},
): StoredEvent {
  const now = options.now ?? Date.now();
  const hash = eventContentHash(event);
  run(
    db,
    `INSERT INTO events (source_id,venue_id,identity_key,status,miss_count,content_hash,start_local,start_utc,title,data,
       first_seen_at,last_seen_at,last_changed_at)
     VALUES (?,?,?,?,0,?,?,?,?,?,?,?,?)
     ON CONFLICT(source_id,identity_key) DO UPDATE SET venue_id=excluded.venue_id, status=excluded.status, miss_count=0,
       content_hash=excluded.content_hash, start_local=excluded.start_local, start_utc=excluded.start_utc,
       title=excluded.title, data=excluded.data, last_seen_at=excluded.last_seen_at,
       last_changed_at=CASE WHEN events.content_hash<>excluded.content_hash OR events.status<>excluded.status OR ?
         THEN excluded.last_changed_at ELSE events.last_changed_at END`,
    event.sourceId,
    event.venueId,
    event.identityKey,
    options.status ?? "active",
    hash,
    event.startLocal,
    event.startUtc,
    event.title,
    JSON.stringify(event),
    now,
    now,
    now,
    bool(options.changed ?? false),
  );
  return getEventByIdentity(db, event.sourceId, event.identityKey) as StoredEvent;
}

export function setEventMissCount(db: Db, id: number, missCount: number): void {
  run(db, "UPDATE events SET miss_count=? WHERE id=?", missCount, id);
}

export function setEventStatus(db: Db, id: number, status: StoredEventStatus, now: number = Date.now()): void {
  run(db, "UPDATE events SET status=?, last_changed_at=? WHERE id=?", status, now, id);
}

export interface EventChange {
  id: number;
  eventId: number;
  sourceId: string;
  identityKey: string;
  change: ChangeKind;
  before: ValidatedEvent | null;
  after: ValidatedEvent | null;
  at: number;
}

export function recordEventChange(db: Db, change: Omit<EventChange, "id" | "at"> & { at?: number }): number {
  const result = run(
    db,
    "INSERT INTO event_changes (event_id,source_id,identity_key,change,before,after,at) VALUES (?,?,?,?,?,?,?)",
    change.eventId,
    change.sourceId,
    change.identityKey,
    change.change,
    change.before ? JSON.stringify(change.before) : null,
    change.after ? JSON.stringify(change.after) : null,
    change.at ?? Date.now(),
  );
  return Number(result.lastInsertRowid);
}

export function listEventChanges(db: Db, filter: { eventId?: number; sourceId?: string } = {}): EventChange[] {
  const where: string[] = [];
  const params: SQLInputValue[] = [];
  if (filter.eventId !== undefined) {
    where.push("event_id=?");
    params.push(filter.eventId);
  }
  if (filter.sourceId !== undefined) {
    where.push("source_id=?");
    params.push(filter.sourceId);
  }
  const clause = where.length ? `WHERE ${where.join(" AND ")}` : "";
  return all(db, `SELECT * FROM event_changes ${clause} ORDER BY id`, ...params).map((row) => ({
    id: num(row.id),
    eventId: num(row.event_id),
    sourceId: str(row.source_id),
    identityKey: str(row.identity_key),
    change: str(row.change) as ChangeKind,
    before: json<ValidatedEvent | null>(row.before, null),
    after: json<ValidatedEvent | null>(row.after, null),
    at: num(row.at),
  }));
}

// ---------------------------------------------------------------------------------------------------------------------
// Alerts
// ---------------------------------------------------------------------------------------------------------------------

function toAlert(row: Row): Alert {
  return {
    id: num(row.id),
    kind: str(row.kind) as AlertKind,
    sourceId: strOrNull(row.source_id),
    candidateId: numOrNull(row.candidate_id),
    message: str(row.message),
    details: json<Record<string, unknown>>(row.details, {}),
    createdAt: num(row.created_at),
    resolvedAt: numOrNull(row.resolved_at),
  };
}

/** Raises an alert unless an identical unresolved one (same kind + source + candidate) already exists. */
export function raiseAlert(
  db: Db,
  alert: {
    kind: AlertKind;
    message: string;
    sourceId?: string | null;
    candidateId?: number | null;
    details?: Record<string, unknown>;
  },
  now: number = Date.now(),
): Alert {
  return transaction(db, () => {
    const existing = one(
      db,
      `SELECT * FROM alerts WHERE resolved_at IS NULL AND kind=? AND source_id IS ? AND candidate_id IS ?`,
      alert.kind,
      alert.sourceId ?? null,
      alert.candidateId ?? null,
    );
    if (existing) return toAlert(existing);
    const result = run(
      db,
      "INSERT INTO alerts (kind,source_id,candidate_id,message,details,created_at) VALUES (?,?,?,?,?,?)",
      alert.kind,
      alert.sourceId ?? null,
      alert.candidateId ?? null,
      alert.message,
      JSON.stringify(alert.details ?? {}),
      now,
    );
    return toAlert(one(db, "SELECT * FROM alerts WHERE id=?", Number(result.lastInsertRowid)) as Row);
  });
}

export function resolveAlerts(
  db: Db,
  filter: { kind?: AlertKind; sourceId?: string; id?: number },
  now: number = Date.now(),
): number {
  const where = ["resolved_at IS NULL"];
  const params: SQLInputValue[] = [];
  if (filter.id !== undefined) {
    where.push("id=?");
    params.push(filter.id);
  }
  if (filter.kind !== undefined) {
    where.push("kind=?");
    params.push(filter.kind);
  }
  if (filter.sourceId !== undefined) {
    where.push("source_id=?");
    params.push(filter.sourceId);
  }
  return Number(run(db, `UPDATE alerts SET resolved_at=? WHERE ${where.join(" AND ")}`, now, ...params).changes);
}

export function listAlerts(db: Db, filter: { open?: boolean; kind?: AlertKind; sourceId?: string } = {}): Alert[] {
  const where: string[] = [];
  const params: SQLInputValue[] = [];
  if (filter.open !== undefined) where.push(filter.open ? "resolved_at IS NULL" : "resolved_at IS NOT NULL");
  if (filter.kind !== undefined) {
    where.push("kind=?");
    params.push(filter.kind);
  }
  if (filter.sourceId !== undefined) {
    where.push("source_id=?");
    params.push(filter.sourceId);
  }
  const clause = where.length ? `WHERE ${where.join(" AND ")}` : "";
  return all(db, `SELECT * FROM alerts ${clause} ORDER BY id`, ...params).map(toAlert);
}

// ---------------------------------------------------------------------------------------------------------------------
// Venue candidates
// ---------------------------------------------------------------------------------------------------------------------

function toCandidate(row: Row): Candidate {
  return {
    id: num(row.id),
    name: str(row.name),
    normalizedName: str(row.normalized_name),
    address: strOrNull(row.address),
    city: strOrNull(row.city),
    lat: numOrNull(row.lat),
    lng: numOrNull(row.lng),
    website: strOrNull(row.website),
    websiteDomain: strOrNull(row.website_domain),
    primaryPlaceId: strOrNull(row.primary_place_id),
    discoveredFrom: str(row.discovered_from) as DiscoveryFeed,
    evidence: json<Record<string, unknown>>(row.evidence, {}),
    status: str(row.status) as CandidateStatus,
    statusReason: strOrNull(row.status_reason),
    matchedVenueId: strOrNull(row.matched_venue_id),
    sourceUrl: strOrNull(row.source_url),
    sourceKind: strOrNull(row.source_kind) as SourceKind | null,
    timezone: strOrNull(row.timezone),
    provenEventCount: num(row.proven_event_count),
    attempts: num(row.attempts),
    nextAttemptAt: numOrNull(row.next_attempt_at),
    createdAt: num(row.created_at),
    updatedAt: num(row.updated_at),
  };
}

export function insertCandidate(db: Db, input: NewCandidate, now: number = Date.now()): Candidate {
  const result = run(
    db,
    `INSERT INTO venue_candidates (name,normalized_name,address,city,lat,lng,website,website_domain,primary_place_id,
       discovered_from,evidence,status,timezone,next_attempt_at,created_at,updated_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
    input.name,
    normalizeName(input.name),
    input.address ?? null,
    input.city ?? null,
    input.lat ?? null,
    input.lng ?? null,
    input.website ?? null,
    input.website ? registrableDomain(input.website) : null,
    input.primaryPlaceId ?? null,
    input.discoveredFrom,
    JSON.stringify(input.evidence ?? {}),
    input.status ?? "new",
    input.timezone ?? null,
    input.nextAttemptAt ?? null,
    now,
    now,
  );
  return getCandidate(db, Number(result.lastInsertRowid)) as Candidate;
}

export function getCandidate(db: Db, id: number): Candidate | null {
  const row = one(db, "SELECT * FROM venue_candidates WHERE id=?", id);
  return row ? toCandidate(row) : null;
}

export type CandidatePatch = Partial<
  Omit<Candidate, "id" | "createdAt" | "updatedAt" | "normalizedName" | "websiteDomain">
>;

const CANDIDATE_COLUMNS: Record<keyof CandidatePatch, string> = {
  name: "name",
  address: "address",
  city: "city",
  lat: "lat",
  lng: "lng",
  website: "website",
  primaryPlaceId: "primary_place_id",
  discoveredFrom: "discovered_from",
  evidence: "evidence",
  status: "status",
  statusReason: "status_reason",
  matchedVenueId: "matched_venue_id",
  sourceUrl: "source_url",
  sourceKind: "source_kind",
  timezone: "timezone",
  provenEventCount: "proven_event_count",
  attempts: "attempts",
  nextAttemptAt: "next_attempt_at",
};

/** Updates the given fields (name -> normalized_name and website -> website_domain are kept in sync). */
export function updateCandidate(db: Db, id: number, patch: CandidatePatch, now: number = Date.now()): Candidate {
  const sets: string[] = ["updated_at=?"];
  const params: SQLInputValue[] = [now];
  for (const [key, value] of Object.entries(patch) as [keyof CandidatePatch, unknown][]) {
    const column = CANDIDATE_COLUMNS[key];
    if (!column || value === undefined) continue;
    sets.push(`${column}=?`);
    params.push(key === "evidence" ? JSON.stringify(value ?? {}) : (value as SQLInputValue));
    if (key === "name") {
      sets.push("normalized_name=?");
      params.push(normalizeName(String(value)));
    }
    if (key === "website") {
      sets.push("website_domain=?");
      params.push(value ? registrableDomain(String(value)) : null);
    }
  }
  run(db, `UPDATE venue_candidates SET ${sets.join(", ")} WHERE id=?`, ...params, id);
  const updated = getCandidate(db, id);
  if (!updated) throw new Error(`Unknown candidate ${id}`);
  return updated;
}

export function listCandidates(
  db: Db,
  filter: { status?: CandidateStatus | CandidateStatus[]; websiteDomain?: string; limit?: number } = {},
): Candidate[] {
  const where: string[] = [];
  const params: SQLInputValue[] = [];
  const statuses = filter.status === undefined ? [] : Array.isArray(filter.status) ? filter.status : [filter.status];
  if (statuses.length) {
    where.push(`status IN (${statuses.map(() => "?").join(",")})`);
    params.push(...statuses);
  }
  if (filter.websiteDomain !== undefined) {
    where.push("website_domain=?");
    params.push(filter.websiteDomain);
  }
  const clause = where.length ? `WHERE ${where.join(" AND ")}` : "";
  const limit = filter.limit ? `LIMIT ${Math.trunc(filter.limit)}` : "";
  return all(db, `SELECT * FROM venue_candidates ${clause} ORDER BY id ${limit}`, ...params).map(toCandidate);
}

/** Candidates in `statuses` whose next_attempt_at is null or due. */
export function dueCandidates(db: Db, statuses: CandidateStatus[], now: number = Date.now(), limit = 50): Candidate[] {
  if (!statuses.length) return [];
  return all(
    db,
    `SELECT * FROM venue_candidates WHERE status IN (${statuses.map(() => "?").join(",")})
       AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
     ORDER BY COALESCE(next_attempt_at, 0), id LIMIT ?`,
    ...statuses,
    now,
    Math.trunc(limit),
  ).map(toCandidate);
}

/** Candidates within a lat/lng box (cheap prefilter for proximity clustering). */
export function candidatesNear(db: Db, lat: number, lng: number, meters: number): Candidate[] {
  const dLat = meters / 111_320;
  const dLng = meters / (111_320 * Math.max(Math.cos((lat * Math.PI) / 180), 0.01));
  return all(
    db,
    "SELECT * FROM venue_candidates WHERE lat BETWEEN ? AND ? AND lng BETWEEN ? AND ? ORDER BY id",
    lat - dLat,
    lat + dLat,
    lng - dLng,
    lng + dLng,
  ).map(toCandidate);
}

// ---------------------------------------------------------------------------------------------------------------------
// Place-id aliases (many Google place ids -> one venue or candidate)
// ---------------------------------------------------------------------------------------------------------------------

export interface PlaceAlias {
  placeId: string;
  provider: string;
  venueId: string | null;
  candidateId: number | null;
  isCanonical: boolean;
  types: string[];
  displayName: string | null;
  lat: number | null;
  lng: number | null;
}

function toPlaceAlias(row: Row): PlaceAlias {
  return {
    placeId: str(row.place_id),
    provider: str(row.provider),
    venueId: strOrNull(row.venue_id),
    candidateId: numOrNull(row.candidate_id),
    isCanonical: num(row.is_canonical) === 1,
    types: json<string[]>(row.types, []),
    displayName: strOrNull(row.display_name),
    lat: numOrNull(row.lat),
    lng: numOrNull(row.lng),
  };
}

/**
 * Records that `placeId` belongs to a venue and/or candidate. When `isCanonical` is set, other aliases of the same
 * owner lose canonical status so there is exactly one canonical id per owner.
 */
export function upsertPlaceAlias(
  db: Db,
  alias: Omit<PlaceAlias, "provider" | "types" | "displayName" | "lat" | "lng"> &
    Partial<Pick<PlaceAlias, "provider" | "types" | "displayName" | "lat" | "lng">>,
  now: number = Date.now(),
): PlaceAlias {
  if (alias.venueId == null && alias.candidateId == null) throw new Error("Place alias needs a venue or candidate");
  return transaction(db, () => {
    if (alias.isCanonical) {
      if (alias.venueId != null)
        run(
          db,
          "UPDATE venue_place_ids SET is_canonical=0 WHERE venue_id=? AND place_id<>?",
          alias.venueId,
          alias.placeId,
        );
      if (alias.candidateId != null)
        run(
          db,
          "UPDATE venue_place_ids SET is_canonical=0 WHERE candidate_id=? AND place_id<>?",
          alias.candidateId,
          alias.placeId,
        );
    }
    run(
      db,
      `INSERT INTO venue_place_ids (place_id,provider,venue_id,candidate_id,is_canonical,types,display_name,lat,lng,
         created_at,updated_at)
       VALUES (?,?,?,?,?,?,?,?,?,?,?)
       ON CONFLICT(place_id) DO UPDATE SET provider=excluded.provider, venue_id=excluded.venue_id,
         candidate_id=excluded.candidate_id, is_canonical=excluded.is_canonical, types=excluded.types,
         display_name=COALESCE(excluded.display_name, venue_place_ids.display_name),
         lat=COALESCE(excluded.lat, venue_place_ids.lat), lng=COALESCE(excluded.lng, venue_place_ids.lng),
         updated_at=excluded.updated_at`,
      alias.placeId,
      alias.provider ?? "google",
      alias.venueId,
      alias.candidateId,
      bool(alias.isCanonical),
      JSON.stringify(alias.types ?? []),
      alias.displayName ?? null,
      alias.lat ?? null,
      alias.lng ?? null,
      now,
      now,
    );
    return toPlaceAlias(one(db, "SELECT * FROM venue_place_ids WHERE place_id=?", alias.placeId) as Row);
  });
}

/** Resolves any known place id (canonical or alias) to its owner. */
export function resolvePlaceId(db: Db, placeId: string): PlaceAlias | null {
  const row = one(db, "SELECT * FROM venue_place_ids WHERE place_id=?", placeId);
  return row ? toPlaceAlias(row) : null;
}

export function listPlaceAliases(db: Db, owner: { venueId?: string; candidateId?: number }): PlaceAlias[] {
  if (owner.venueId !== undefined)
    return all(
      db,
      "SELECT * FROM venue_place_ids WHERE venue_id=? ORDER BY is_canonical DESC, place_id",
      owner.venueId,
    ).map(toPlaceAlias);
  if (owner.candidateId !== undefined)
    return all(
      db,
      "SELECT * FROM venue_place_ids WHERE candidate_id=? ORDER BY is_canonical DESC, place_id",
      owner.candidateId,
    ).map(toPlaceAlias);
  return [];
}

// ---------------------------------------------------------------------------------------------------------------------
// Publish outbox
// ---------------------------------------------------------------------------------------------------------------------

function toOutboxItem(row: Row): OutboxItem {
  return {
    id: num(row.id),
    eventId: num(row.event_id),
    sourceId: str(row.source_id),
    venueId: strOrNull(row.venue_id),
    identityKey: str(row.identity_key),
    change: str(row.change) as ChangeKind,
    event: json<ValidatedEvent>(row.payload, {} as ValidatedEvent),
    observedAt: num(row.observed_at),
    evidenceSha256: strOrNull(row.evidence_sha256),
    attempts: num(row.attempts),
    createdAt: num(row.created_at),
  };
}

/**
 * Queues an observation for publishing. Identical payloads for the same event are deduplicated
 * (returns null when an identical payload is already queued or published).
 */
export function enqueueOutbox(
  db: Db,
  item: {
    eventId: number;
    change: ChangeKind;
    event: ValidatedEvent;
    observedAt: number;
    evidenceSha256: string | null;
  },
  now: number = Date.now(),
): number | null {
  const payload = JSON.stringify(item.event);
  const payloadHash = sha256Hex(`${item.change}\n${payload}`);
  const result = run(
    db,
    `INSERT INTO publish_outbox (event_id,source_id,venue_id,identity_key,change,payload,payload_hash,observed_at,
       evidence_sha256,created_at)
     VALUES (?,?,?,?,?,?,?,?,?,?)
     ON CONFLICT(event_id,payload_hash) DO NOTHING`,
    item.eventId,
    item.event.sourceId,
    item.event.venueId,
    item.event.identityKey,
    item.change,
    payload,
    payloadHash,
    item.observedAt,
    item.evidenceSha256,
    now,
  );
  return Number(result.changes) === 1 ? Number(result.lastInsertRowid) : null;
}

export function pendingOutbox(db: Db, limit = 100, maxAttempts = 10): OutboxItem[] {
  return all(
    db,
    "SELECT * FROM publish_outbox WHERE published_at IS NULL AND attempts < ? ORDER BY id LIMIT ?",
    maxAttempts,
    Math.trunc(limit),
  ).map(toOutboxItem);
}

export function markOutboxPublished(db: Db, ids: number[], now: number = Date.now()): void {
  const statement = db.prepare("UPDATE publish_outbox SET published_at=?, last_error=NULL WHERE id=?");
  transaction(db, () => {
    for (const id of ids) statement.run(now, id);
  });
}

/**
 * Outbox retention: deletes published rows older than `publishedBefore`, and (only when publishing is off, so nothing
 * would ever drain them) unpublished rows older than `pendingBefore`, so their evidence pages become prunable.
 */
export function pruneOutbox(db: Db, options: { publishedBefore: number; pendingBefore?: number | null }): number {
  let n = Number(
    run(db, "DELETE FROM publish_outbox WHERE published_at IS NOT NULL AND published_at < ?", options.publishedBefore)
      .changes,
  );
  if (options.pendingBefore != null) {
    n += Number(
      run(db, "DELETE FROM publish_outbox WHERE published_at IS NULL AND created_at < ?", options.pendingBefore)
        .changes,
    );
  }
  return n;
}

export function markOutboxFailed(db: Db, id: number, error: string): void {
  run(db, "UPDATE publish_outbox SET attempts=attempts+1, last_error=? WHERE id=?", error.slice(0, 2000), id);
}

// ---------------------------------------------------------------------------------------------------------------------
// Events production already has (synced read-only from Postgres); see src/publish/known-events.ts
// ---------------------------------------------------------------------------------------------------------------------

export const KNOWN_EVENTS_SYNCED_KEY = "known_events:synced_at";

export interface KnownEventRow {
  origin: string;
  originKey: string;
  venueId: string | null;
  startUtc: string;
  normTitle: string;
  urlKey: string | null;
}

/** Replaces the whole known-events set in one transaction and stamps the sync time. */
export function replaceKnownEvents(db: Db, rows: KnownEventRow[], now: number = Date.now()): number {
  return transaction(db, () => {
    run(db, "DELETE FROM known_events");
    const insert = db.prepare(
      "INSERT OR REPLACE INTO known_events (origin,origin_key,venue_id,start_utc,norm_title,url_key) VALUES (?,?,?,?,?,?)",
    );
    for (const r of rows) insert.run(r.origin, r.originKey, r.venueId, r.startUtc, r.normTitle, r.urlKey);
    setKv(db, KNOWN_EVENTS_SYNCED_KEY, String(now), now);
    return Number((one(db, "SELECT COUNT(*) AS n FROM known_events") as Row).n);
  });
}

/** Epoch ms of the last known-events sync, or null when never synced. */
export function knownEventsSyncedAt(db: Db): number | null {
  const value = Number(getKv(db, KNOWN_EVENTS_SYNCED_KEY));
  return Number.isFinite(value) && value > 0 ? value : null;
}

export function knownEventsByVenue(db: Db, venueId: string, fromUtc: string, toUtc: string): KnownEventRow[] {
  return all(
    db,
    "SELECT * FROM known_events WHERE venue_id=? AND start_utc>=? AND start_utc<=?",
    venueId,
    fromUtc,
    toUtc,
  ).map(toKnownEvent);
}

export function knownEventsByUrl(db: Db, urlKey: string): KnownEventRow[] {
  return all(db, "SELECT * FROM known_events WHERE url_key=?", urlKey).map(toKnownEvent);
}

function toKnownEvent(row: Row): KnownEventRow {
  return {
    origin: String(row.origin),
    originKey: String(row.origin_key),
    venueId: strOrNull(row.venue_id),
    startUtc: String(row.start_utc),
    normTitle: String(row.norm_title),
    urlKey: strOrNull(row.url_key),
  };
}
