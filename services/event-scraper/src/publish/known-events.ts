import { all, type Db } from "../db.js";
import { normalizeTitle, urlKey } from "../reconcile/identity.js";
import type { ValidatedEvent } from "../types.js";
import { addDays, dateOf, localDate } from "../validate/time.js";

/**
 * Events production already has, from ANY crawler (the legacy event-crawler and this scraper's own published events),
 * read live from `scraped_events`. An incoming event that matches one is dropped before it is stored, reconciled or
 * published. If that table cannot be read the run fails: it never continues without the check.
 *
 * Match (local start date within one day, so a legacy instant stored in the wrong zone still matches):
 * - the same event URL, when the titles also match (or, for an untitled stored event, on the exact local date); or
 * - at the same venue, matching titles: equal after normalization, or every word of the shorter title appears in the
 *   longer one ("moe." vs "moe. at Wellmont Theater").
 */

export interface KnownEvent {
  origin: string;
  originKey: string;
  venueId: string | null;
  startUtc: string;
  title: string;
  url: string | null;
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

function toKnown(row: Record<string, unknown>): KnownEvent {
  return {
    origin: String(row.source),
    originKey: String(row.source_key),
    venueId: row.venue_id == null ? null : String(row.venue_id),
    startUtc: (row.start_time as Date).toISOString(),
    title: normalizeTitle(row.title == null ? "" : String(row.title)),
    url: urlKey(row.event_url == null ? null : String(row.event_url)),
  };
}

/** The ways one URL may have been stored; `event_url` holds what the crawler saw, not our canonical form. */
function urlSpellings(eventUrl: string, key: string): string[] {
  const bare = key.replace(/\/+$/, "");
  return [...new Set([eventUrl, key, bare, `${bare}/`])];
}

export type KnownEventInput = Pick<ValidatedEvent, "venueId" | "title" | "startLocal" | "timezone" | "eventUrl">;

/** The production event this one duplicates, or null. */
export async function findKnownEvent(db: Db, event: KnownEventInput): Promise<KnownEvent | null> {
  const date = dateOf(event.startLocal);
  const from = addDays(date, -1);
  const to = addDays(date, 1);
  const localDay = (row: KnownEvent) => localDate(Date.parse(row.startUtc), event.timezone);
  const near = (row: KnownEvent) => localDay(row) >= from && localDay(row) <= to;
  const title = normalizeTitle(event.title);
  // Wide UTC window; the local-date checks are the real filter.
  const windowStart = `${addDays(date, -2)}T00:00:00Z`;
  const windowEnd = `${addDays(date, 3)}T00:00:00Z`;
  const url = urlKey(event.eventUrl);

  const matchesUrl = (row: KnownEvent) => {
    if (!url || row.url !== url) return false;
    // An untitled stored event only matches on its exact local date (its URL may be a shared calendar page).
    return row.title ? near(row) && titlesMatch(title, row.title) : localDay(row) === date;
  };

  if (event.venueId) {
    const rows = await all(
      db,
      `SELECT source, source_key, venue_id, start_time, title, event_url FROM scraped_events
       WHERE venue_id=? AND start_time>=?::timestamptz AND start_time<?::timestamptz`,
      event.venueId,
      windowStart,
      windowEnd,
    );
    const known = rows.map(toKnown);
    const hit =
      known.find(matchesUrl) ?? (title ? known.find((row) => near(row) && titlesMatch(title, row.title)) : null);
    if (hit) return hit;
  }

  // Same URL without a venue on one side. `event_url` has no index of its own and this table must not get one from
  // here; the date range keeps the query on the existing upcoming index.
  if (url && event.eventUrl) {
    const rows = await all(
      db,
      `SELECT source, source_key, venue_id, start_time, title, event_url FROM scraped_events
       WHERE music_classification='music' AND start_time>=?::timestamptz AND start_time<?::timestamptz
         AND event_url = ANY(?::text[])${event.venueId ? " AND venue_id IS NULL" : ""}`,
      windowStart,
      windowEnd,
      urlSpellings(event.eventUrl, url),
    );
    return rows.map(toKnown).find(matchesUrl) ?? null;
  }
  return null;
}
