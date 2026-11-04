import { normalizeName } from "../db.js";
import { canonicalUrl } from "../url.js";

/**
 * Event identity within a source.
 *
 * - With the site's own stable id (WP post id, iCal UID, Squarespace item id):
 *     `<scope>|<local date>|id:<sourceEventId>|t:<HH:mm or "-">`
 * - Else with an event-specific URL on the venue's site (not the calendar page itself):
 *     `<scope>|<local date>|url:<canonical url>|t:<HH:mm or "-">`
 * - Else: `<scope>|<local date>|<HH:mm or "-">|<normalized title>`
 *
 * The local date is always part of the key because recurring events (weekly open mic, iCal RRULE expansions) share
 * one id/URL across occurrences, and the start time is part of it because early and late sets of one show often
 * share one id/URL on the same day. A same-day time change of an id/URL event is still an update: reconcile keeps
 * the stored key when exactly one stored and exactly one incoming event share the key without its time
 * (see `identityBase`). `scope` is the venue id, or `src:<sourceId>` for venue-less listing sources.
 */

export interface IdentityInput {
  venueId: string | null;
  sourceId: string;
  /** "YYYY-MM-DD" or "YYYY-MM-DDTHH:mm". */
  startLocal: string;
  title: string;
  sourceEventId?: string | null;
  eventUrl?: string | null;
  /** URL of the page the event was found on (and the source URL); such URLs are not event-specific. */
  pageUrls?: Array<string | null | undefined>;
}

const TITLE_NOISE =
  /^(sold[\s-]*out|cancel+ed|postponed|rescheduled|moved|new date|just announced|tonight|this week|free|all ages|21\+|18\+)\s*[:!\-–—|]*\s*/i;

/** Title normalized for identity: status prefixes dropped, accents/punctuation stripped, max 120 chars. */
export function normalizeTitle(title: string): string {
  let t = title.trim();
  for (let i = 0; i < 3; i++) {
    const next = t.replace(TITLE_NOISE, "");
    if (next === t) break;
    t = next;
  }
  t = t.replace(/\s*[([](sold[\s-]*out|cancel+ed|postponed|rescheduled|all ages|21\+|18\+)[)\]]\s*$/i, "");
  return normalizeName(t).slice(0, 120);
}

function stripTrackingParams(url: string): string {
  try {
    const u = new URL(url);
    for (const key of [...u.searchParams.keys()]) {
      if (/^(utm_|fbclid|gclid|mc_|_ga|ref$|source$)/i.test(key)) u.searchParams.delete(key);
    }
    if (u.pathname.length > 1) u.pathname = u.pathname.replace(/\/+$/, "");
    return u.href;
  } catch {
    return url;
  }
}

export function urlKey(url: string | null | undefined): string | null {
  if (!url) return null;
  const canonical = canonicalUrl(url);
  return canonical ? stripTrackingParams(canonical) : null;
}

const TIME_SUFFIX = /\|t:(\d{2}:\d{2}|-)$/;

/**
 * The id/URL identity without its time segment, or null for title-based keys. Two keys with the same base are the
 * same site event on the same day at (possibly) different times.
 */
export function identityBase(key: string): string | null {
  if (!TIME_SUFFIX.test(key) || !/\|(id|url):/.test(key)) return null;
  return key.replace(TIME_SUFFIX, "");
}

export function computeIdentityKey(input: IdentityInput): string {
  const scope = input.venueId ?? `src:${input.sourceId}`;
  const date = input.startLocal.slice(0, 10);
  const time = /T(\d{2}:\d{2})/.exec(input.startLocal)?.[1] ?? "-";
  const sid = input.sourceEventId?.trim();
  if (sid) return `${scope}|${date}|id:${sid.slice(0, 200)}|t:${time}`;

  const eventUrl = urlKey(input.eventUrl);
  if (eventUrl) {
    const pages = new Set((input.pageUrls ?? []).map(urlKey).filter((u): u is string => !!u));
    let path = "/";
    try {
      path = new URL(eventUrl).pathname;
    } catch {
      // ignore
    }
    if (!pages.has(eventUrl) && path !== "/" && path !== "")
      return `${scope}|${date}|url:${eventUrl.slice(0, 300)}|t:${time}`;
  }

  return `${scope}|${date}|${time}|${normalizeTitle(input.title)}`;
}
