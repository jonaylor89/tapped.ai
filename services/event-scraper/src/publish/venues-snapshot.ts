/**
 * Venue snapshot: production venues -> the scraper schema's `venues` table (+ their Google place id as an alias).
 *
 * Nothing here writes to application tables. The source is one SELECT on `ingestion_profiles`, which is all the
 * scraper's role may read of them. The same rows can be loaded from a JSON file instead.
 */
import { readFileSync } from "node:fs";
import { all, type Db, listPlaceAliases, resolvePlaceId, transaction, upsertPlaceAlias, upsertVenues } from "../db.js";
import type { Clock, Venue, VenueSnapshotSource } from "../types.js";
import { systemClock } from "../types.js";
import { parseHttpUrl } from "../url.js";

/**
 * Exact snapshot query. It reads the `ingestion_profiles` view (services/api.tapped.ai migration
 * 20261024010000_postgres_ingestion.sql), which the least-privilege `tapped_ingestion` role can already SELECT, so the
 * snapshot role needs no access to the `users` table itself. The view already excludes deleted and shadow-banned
 * users. `doc.venueInfo` is a JSON object only when `users.venue_enabled` is true (it is JSON `null` otherwise, hence
 * `jsonb_typeof`). `doc.location` is built from `users.location` (PostGIS point -> lat/lng) and `users.place_id`.
 * Production stores no venue street address or IANA timezone, so those stay null locally (sources carry a timezone).
 */
export const VENUE_SNAPSHOT_SQL = `SELECT p.id,
  p.username,
  p.doc->>'artistName' AS name,
  p.venue_website_url AS website,
  (p.doc->'location'->>'lat')::float8 AS lat,
  (p.doc->'location'->>'lng')::float8 AS lng,
  NULLIF(p.doc->'location'->>'placeId', '') AS place_id
FROM ingestion_profiles p
WHERE jsonb_typeof(p.doc->'venueInfo') = 'object'
ORDER BY p.id`;

/** Minimal query surface so tests can pass a fake instead of a real connection. */
export interface ReadOnlyQueryable {
  query(sql: string): Promise<{ rows: Record<string, unknown>[] }>;
}

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function finite(value: unknown, min: number, max: number): number | null {
  const n = typeof value === "string" && value.trim() ? Number(value) : value;
  return typeof n === "number" && Number.isFinite(n) && n >= min && n <= max ? n : null;
}

function website(value: unknown): string | null {
  const raw = text(value);
  if (!raw) return null;
  const url = parseHttpUrl(raw);
  if (!url) return null;
  // Never keep credentials from a profile URL.
  url.username = "";
  url.password = "";
  return url.href;
}

function timezone(value: unknown): string | null {
  const tz = text(value);
  if (!tz) return null;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return tz;
  } catch {
    return null;
  }
}

/**
 * Normalizes one loose venue record (a snapshot row or a JSON-file entry). Returns null for rows without an id.
 * Accepted keys: id, name|artistName|username, address, lat, lng, website|websiteUrl|venue_website_url,
 * googlePlaceId|placeId|place_id, timezone.
 */
export function toSnapshotVenue(row: Record<string, unknown>, syncedAt: number): Venue | null {
  const id = text(row.id);
  if (!id) return null;
  const lat = finite(row.lat, -90, 90);
  const lng = finite(row.lng, -180, 180);
  const hasPoint = lat !== null && lng !== null && !(lat === 0 && lng === 0);
  return {
    id,
    name: text(row.name) ?? text(row.artistName) ?? text(row.username) ?? id,
    address: text(row.address),
    lat: hasPoint ? lat : null,
    lng: hasPoint ? lng : null,
    website: website(row.website ?? row.websiteUrl ?? row.venue_website_url),
    googlePlaceId: text(row.googlePlaceId ?? row.placeId ?? row.place_id),
    timezone: timezone(row.timezone),
    syncedAt,
  };
}

/** Production snapshot via a read-only connection. */
export class PostgresVenueSnapshot implements VenueSnapshotSource {
  constructor(
    private readonly db: ReadOnlyQueryable,
    private readonly clock: Clock = systemClock,
  ) {}

  async listVenues(): Promise<Venue[]> {
    const { rows } = await this.db.query(VENUE_SNAPSHOT_SQL);
    const syncedAt = this.clock.now().getTime();
    return rows.flatMap((row) => toSnapshotVenue(row, syncedAt) ?? []);
  }
}

/** Standalone snapshot from a JSON file: either an array of venue objects or `{ "venues": [...] }`. */
export class JsonFileVenueSnapshot implements VenueSnapshotSource {
  constructor(
    private readonly path: string,
    private readonly clock: Clock = systemClock,
  ) {}

  async listVenues(): Promise<Venue[]> {
    const parsed: unknown = JSON.parse(readFileSync(this.path, "utf8"));
    const list = Array.isArray(parsed)
      ? parsed
      : parsed && typeof parsed === "object" && Array.isArray((parsed as { venues?: unknown }).venues)
        ? (parsed as { venues: unknown[] }).venues
        : null;
    if (!list) throw new Error("Venue snapshot file must be an array or { venues: [...] }");
    const syncedAt = this.clock.now().getTime();
    return list.flatMap((entry) =>
      entry && typeof entry === "object" && !Array.isArray(entry)
        ? (toSnapshotVenue(entry as Record<string, unknown>, syncedAt) ?? [])
        : [],
    );
  }
}

/**
 * Picks the snapshot source: a JSON file (VENUE_SNAPSHOT_FILE) wins, else `ingestion_profiles` on the scraper's own
 * connection, whose role can only read it. Returns null when neither is available.
 */
export function venueSnapshotFromEnv(
  env: NodeJS.ProcessEnv = process.env,
  clock: Clock = systemClock,
  db: Db | null = null,
) {
  if (env.VENUE_SNAPSHOT_FILE) return new JsonFileVenueSnapshot(env.VENUE_SNAPSHOT_FILE, clock);
  if (db) return new PostgresVenueSnapshot({ query: (sql) => all(db, sql).then((rows) => ({ rows })) }, clock);
  return null;
}

export interface VenueSyncResult {
  venues: number;
  placeAliasesAdded: number;
  /** Place ids already owned by a DIFFERENT venue; left untouched (shared place ids do not prove identity). */
  placeAliasConflicts: { placeId: string; venueId: string; ownerVenueId: string }[];
}

/**
 * Pulls the snapshot and upserts it locally. Each venue's Google place id is recorded in venue_place_ids so any alias
 * the discovery loop later finds resolves to it. A place id claimed by another venue is reported, never reassigned.
 */
export async function syncVenueSnapshot(
  db: Db,
  source: VenueSnapshotSource,
  now: number = Date.now(),
): Promise<VenueSyncResult> {
  const venues = await source.listVenues();
  const result: VenueSyncResult = { venues: 0, placeAliasesAdded: 0, placeAliasConflicts: [] };
  await transaction(db, async () => {
    result.venues = await upsertVenues(db, venues);
    for (const venue of venues) {
      if (!venue.googlePlaceId) continue;
      const existing = await resolvePlaceId(db, venue.googlePlaceId);
      if (existing?.venueId === venue.id) continue;
      if (existing?.venueId) {
        result.placeAliasConflicts.push({
          placeId: venue.googlePlaceId,
          venueId: venue.id,
          ownerVenueId: existing.venueId,
        });
        continue;
      }
      const hasCanonical = (await listPlaceAliases(db, { venueId: venue.id })).some((alias) => alias.isCanonical);
      await upsertPlaceAlias(
        db,
        {
          placeId: venue.googlePlaceId,
          venueId: venue.id,
          candidateId: existing?.candidateId ?? null,
          isCanonical: existing ? existing.isCanonical : !hasCanonical,
          provider: existing?.provider ?? "google",
          types: existing?.types ?? [],
          displayName: existing?.displayName ?? venue.name,
          lat: existing?.lat ?? venue.lat,
          lng: existing?.lng ?? venue.lng,
        },
        now,
      );
      result.placeAliasesAdded++;
    }
  });
  return result;
}
