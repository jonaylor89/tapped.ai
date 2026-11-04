import { readFileSync } from "node:fs";
import {
  type Db,
  type KnownEventRow,
  knownEventsByUrl,
  knownEventsByVenue,
  knownEventsSyncedAt,
  replaceKnownEvents,
} from "../db.js";
import { normalizeTitle, urlKey } from "../reconcile/identity.js";
import type { ValidatedEvent } from "../types.js";
import { addDays, dateOf, localDate } from "../validate/time.js";
import type { ReadOnlyQueryable } from "./venues-snapshot.js";

/**
 * Events production Postgres already has, from ANY crawler (the legacy event-crawler and this scraper's own published
 * events). They are pulled read-only into SQLite (`known_events`) and an incoming event that matches one is dropped
 * before it is stored, reconciled or published: an event already in Postgres is never scraped into it again.
 *
 * Match (same venue, local start date within one day, so a legacy instant stored in the wrong zone still matches):
 * - the same event URL, when the titles also match (or, for an untitled stored event, on the exact local date); or
 * - matching titles: equal after normalization, or every word of the shorter title appears in the longer one
 *   ("moe." vs "moe. at Wellmont Theater").
 */

/** Upcoming events (from two days ago) with a venue; far-future placeholders past three years are ignored. */
export const KNOWN_EVENTS_SQL = `SELECT e.source, e.source_key, e.venue_id, e.start_time, e.title, e.event_url
FROM scraped_events e
WHERE e.venue_id IS NOT NULL AND e.start_time IS NOT NULL
  AND e.start_time >= now() - interval '2 days' AND e.start_time < now() + interval '3 years'
ORDER BY e.venue_id, e.start_time`;

/** A sync older than this is stale: scraping and publishing refuse to run on it. */
export const KNOWN_EVENTS_MAX_AGE_MS = 24 * 60 * 60 * 1000;

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function instant(value: unknown): string | null {
  const ms = value instanceof Date ? value.getTime() : typeof value === "string" ? Date.parse(value) : Number.NaN;
  return Number.isFinite(ms) ? new Date(ms).toISOString() : null;
}

/** Normalizes one Postgres row or JSON-file entry; rows without a key or start are dropped. */
export function toKnownEvent(row: Record<string, unknown>): KnownEventRow | null {
  const origin = text(row.source ?? row.origin);
  const originKey = text(row.source_key ?? row.sourceKey ?? row.originKey);
  const startUtc = instant(row.start_time ?? row.startTime ?? row.startUtc);
  if (!origin || !originKey || !startUtc) return null;
  return {
    origin,
    originKey,
    venueId: text(row.venue_id ?? row.venueId),
    startUtc,
    normTitle: normalizeTitle(text(row.title) ?? ""),
    urlKey: urlKey(text(row.event_url ?? row.eventUrl)),
  };
}

export interface KnownEventsSyncResult {
  knownEvents: number;
  syncedAt: string;
}

/** Pulls every upcoming production event (read-only) and replaces the local set. */
export async function syncKnownEvents(db: Db, source: ReadOnlyQueryable, now: number): Promise<KnownEventsSyncResult> {
  const { rows } = await source.query(KNOWN_EVENTS_SQL);
  return store(db, rows, now);
}

/** Same, from a JSON file (an array of rows, or `{ "events": [...] }`), for offline use. */
export function importKnownEventsFile(db: Db, path: string, now: number): KnownEventsSyncResult {
  const parsed: unknown = JSON.parse(readFileSync(path, "utf8"));
  const list = Array.isArray(parsed) ? parsed : (parsed as { events?: unknown } | null)?.events;
  if (!Array.isArray(list)) throw new Error("Known events file must be an array or { events: [...] }");
  return store(
    db,
    list.filter((r): r is Record<string, unknown> => !!r && typeof r === "object" && !Array.isArray(r)),
    now,
  );
}

function store(db: Db, rows: Record<string, unknown>[], now: number): KnownEventsSyncResult {
  const known = rows.flatMap((row) => toKnownEvent(row) ?? []);
  return { knownEvents: replaceKnownEvents(db, known, now), syncedAt: new Date(now).toISOString() };
}

/** Why the local known-events set cannot be trusted right now, or null when it is fresh. */
export function knownEventsProblem(db: Db, now: number, maxAgeMs: number = KNOWN_EVENTS_MAX_AGE_MS): string | null {
  const syncedAt = knownEventsSyncedAt(db);
  if (syncedAt === null) return "never_synced";
  if (now - syncedAt > maxAgeMs) return "stale";
  return null;
}

function words(title: string): string[] {
  return title.split(" ").filter(Boolean);
}

export function titlesMatch(a: string, b: string): boolean {
  if (!a || !b) return false;
  if (a === b) return true;
  const [short, long] = a.length <= b.length ? [a, b] : [b, a];
  if (short.length < 3) return false;
  const longWords = new Set(words(long));
  return words(short).every((w) => longWords.has(w));
}

export type KnownEventInput = Pick<ValidatedEvent, "venueId" | "title" | "startLocal" | "timezone" | "eventUrl">;

/** The production event this one duplicates, or null. */
export function findKnownEvent(db: Db, event: KnownEventInput): KnownEventRow | null {
  const date = dateOf(event.startLocal);
  const from = addDays(date, -1);
  const to = addDays(date, 1);
  const near = (row: KnownEventRow) => {
    const d = localDate(Date.parse(row.startUtc), event.timezone);
    return d >= from && d <= to;
  };
  const sameDay = (row: KnownEventRow) => localDate(Date.parse(row.startUtc), event.timezone) === date;
  const title = normalizeTitle(event.title);
  const sameVenue = (row: KnownEventRow) => !event.venueId || !row.venueId || row.venueId === event.venueId;

  const url = urlKey(event.eventUrl);
  if (url) {
    for (const row of knownEventsByUrl(db, url)) {
      if (!sameVenue(row)) continue;
      // An untitled stored event only matches on its exact local date (its URL may be a shared calendar page).
      if (row.normTitle ? near(row) && titlesMatch(title, row.normTitle) : sameDay(row)) return row;
    }
  }
  if (!event.venueId || !title) return null;
  // Wide UTC window; the local-date check above is the real filter.
  for (const row of knownEventsByVenue(db, event.venueId, `${addDays(date, -2)}T00:00`, `${addDays(date, 3)}T00:00`)) {
    if (near(row) && titlesMatch(title, row.normTitle)) return row;
  }
  return null;
}
