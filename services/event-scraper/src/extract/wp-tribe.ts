/**
 * WordPress "The Events Calendar" (Modern Tribe / StellarWP) REST API: /wp-json/tribe/events/v1/events.
 * Only ever used on the venue's own WordPress site.
 */
import { isTicketingUrl } from "../denylist.js";
import type { ExtractContext, ExtractedEvent, ExtractedLocation, Extractor, Page } from "../types.js";
import { normalizedHost, parseHttpUrl } from "../url.js";
import { instantToLocal, isValidTimeZone, localToInstant, trimLocal } from "./time.js";
import {
  applyTitleStatus,
  asArray,
  blankEvent,
  categoryHint,
  cleanMultiline,
  cleanText,
  dedupeEvents,
  isRecord,
  mapStatus,
  pageBase,
  parseJsonPage,
  parsePriceText,
  resolveUrl,
  toCents,
} from "./util.js";

export const TRIBE_API_PATH = "/wp-json/tribe/events/v1/events";
export const TRIBE_DEFAULT_MAX_PAGES = 5;

/**
 * Builds the events endpoint for a WordPress site (or for a wp-json root discovered on a page).
 * `startDate` defaults to the API's own default ("now"); we pass the venue-local date for stable results.
 */
export function tribeEventsApiUrl(
  siteOrApiRoot: string,
  opts: { startDate?: string; perPage?: number } = {},
): string | null {
  const url = parseHttpUrl(siteOrApiRoot);
  if (!url) return null;
  let path = url.pathname;
  if (/\/wp-json\/tribe\/events\/v1\/events\/?$/.test(path)) {
    // already the endpoint
  } else if (/\/wp-json\/tribe\/events\/v1\/?$/.test(path)) {
    path = `${path.replace(/\/$/, "")}/events`;
  } else if (/\/wp-json\/?$/.test(path)) {
    path = `${path.replace(/\/$/, "")}/tribe/events/v1/events`;
  } else if (url.searchParams.get("rest_route")) {
    // Sites without pretty permalinks: ?rest_route=/tribe/events/v1/events
    url.searchParams.set("rest_route", "/tribe/events/v1/events");
    path = url.pathname;
  } else {
    // WordPress may live in a subdirectory; keep the path prefix up to (not including) any known front-end slug.
    const prefix = path.replace(/\/(events|calendar|shows|event)(\/.*)?$/i, "").replace(/\/$/, "");
    path = `${prefix}${TRIBE_API_PATH}`;
  }
  url.pathname = path;
  url.hash = "";
  url.searchParams.set("per_page", String(opts.perPage ?? 50));
  if (opts.startDate) url.searchParams.set("start_date", opts.startDate);
  return url.href;
}

export function looksLikeTribeJson(data: unknown): data is Record<string, unknown> {
  if (!isRecord(data) || !Array.isArray(data.events)) return false;
  if ("rest_url" in data || "next_rest_url" in data || "total_pages" in data) return true;
  const first = data.events[0];
  return isRecord(first) && "start_date" in first && ("utc_start_date" in first || "all_day" in first);
}

/** next_rest_url of a tribe response, only when it stays on the same host and is not a ticketing URL. */
export function tribeNextPageUrl(data: unknown, currentUrl: string): string | null {
  if (!isRecord(data) || typeof data.next_rest_url !== "string") return null;
  const next = resolveUrl(data.next_rest_url, currentUrl);
  if (!next || isTicketingUrl(next)) return null;
  if (normalizedHost(next) !== normalizedHost(currentUrl)) return null;
  return next;
}

function tribeLocation(venue: unknown): ExtractedLocation | null {
  const v = asArray(venue).find(isRecord);
  if (!v) return null;
  const name = cleanText(v.venue);
  const address = [v.address, v.city, v.stateprovince ?? v.state ?? v.province, v.zip, v.country]
    .map(cleanText)
    .filter(Boolean)
    .join(", ");
  const lat = v.geo_lat === undefined || v.geo_lat === "" ? Number.NaN : Number(v.geo_lat);
  const lng = v.geo_lng === undefined || v.geo_lng === "" ? Number.NaN : Number(v.geo_lng);
  return {
    name,
    address: address || null,
    lat: Number.isFinite(lat) ? lat : null,
    lng: Number.isFinite(lng) ? lng : null,
    url: typeof v.website === "string" ? resolveUrl(v.website, "https://invalid.invalid/") : null,
  };
}

function tribeImage(image: unknown, base: string): string | null {
  if (typeof image === "string") return resolveUrl(image, base);
  if (!isRecord(image)) return null;
  return resolveUrl(image.url, base);
}

function tribeEvent(raw: Record<string, unknown>, base: string, ctx: ExtractContext): ExtractedEvent | null {
  const ev = blankEvent("wp_tribe");
  ev.title = cleanText(raw.title);
  const tzRaw = typeof raw.timezone === "string" ? raw.timezone : null;
  const eventTz = isValidTimeZone(tzRaw) && tzRaw?.includes("/") ? tzRaw : null;
  const allDay = raw.all_day === true || raw.all_day === "1" || raw.all_day === 1;
  const startLocal = typeof raw.start_date === "string" ? trimLocal(raw.start_date.replace(" ", "T")) : null;
  const endLocal = typeof raw.end_date === "string" ? trimLocal(raw.end_date.replace(" ", "T")) : null;
  const utcStart = typeof raw.utc_start_date === "string" ? new Date(`${raw.utc_start_date.replace(" ", "T")}Z`) : null;
  ev.rawDateText = typeof raw.start_date === "string" ? raw.start_date : null;

  if (allDay && startLocal) {
    ev.start = startLocal.slice(0, 10);
    const endDate = endLocal?.slice(0, 10);
    if (endDate && endDate !== ev.start) ev.end = endDate;
  } else if (utcStart && !Number.isNaN(utcStart.getTime()) && (eventTz || !startLocal)) {
    // Trust the UTC instant when the site states an IANA zone; express it in venue time.
    ev.startInstant = utcStart.toISOString();
    ev.start = instantToLocal(utcStart, ctx.timezone);
    const utcEnd = typeof raw.utc_end_date === "string" ? new Date(`${raw.utc_end_date.replace(" ", "T")}Z`) : null;
    if (utcEnd && !Number.isNaN(utcEnd.getTime()) && utcEnd.getTime() > utcStart.getTime()) {
      ev.end = instantToLocal(utcEnd, ctx.timezone);
    }
  } else if (startLocal) {
    // "UTC+0"-style site zones are a common misconfiguration: the wall-clock start_date is what the venue typed.
    ev.start = startLocal;
    if (endLocal && endLocal > startLocal) ev.end = endLocal;
    const inst = eventTz ? localToInstant(startLocal, eventTz) : null;
    ev.startInstant = inst ? inst.toISOString() : null;
  }
  if (!ev.title && !ev.start) return null;

  ev.description = cleanMultiline(raw.description) ?? cleanMultiline(raw.excerpt);
  ev.eventUrl = resolveUrl(raw.url, base);
  ev.imageUrl = tribeImage(raw.image, base);
  // "website" on a tribe event is the external event/ticket link. Recorded as a string, never fetched.
  const website = resolveUrl(raw.website, base);
  ev.ticketUrl = website && website !== ev.eventUrl ? website : null;

  const costDetails = isRecord(raw.cost_details) ? raw.cost_details : null;
  const values = asArray(costDetails?.values)
    .map(toCents)
    .filter((n): n is number => n !== null);
  const costText = cleanText(raw.cost);
  const parsed = parsePriceText(costText);
  if (parsed.prices.length || parsed.isFree !== null) {
    ev.prices = parsed.prices;
    ev.isFree = parsed.isFree;
  } else if (values.length) {
    const min = Math.min(...values);
    const max = Math.max(...values);
    if (max === 0) ev.isFree = true;
    else {
      const code = typeof costDetails?.currency_code === "string" ? costDetails.currency_code.toUpperCase() : null;
      const symbol = typeof costDetails?.currency_symbol === "string" ? costDetails.currency_symbol : null;
      ev.prices = [
        {
          kind: "ticket",
          minCents: min,
          maxCents: max,
          currency: code ?? (symbol === "$" ? "USD" : null),
          text: costText,
        },
      ];
      ev.isFree = false;
    }
  }

  const labels = [...asArray(raw.categories), ...asArray(raw.tags)]
    .map((c) => (isRecord(c) ? cleanText(c.name) : cleanText(c)))
    .filter((c): c is string => Boolean(c));
  ev.category = categoryHint([], labels, ev.title);
  ev.location = tribeLocation(raw.venue);
  // TEC's event-status feature (when enabled) exposes "canceled"/"postponed".
  ev.status = mapStatus(raw.event_status);
  applyTitleStatus(ev);
  const id = raw.id ?? raw.global_id;
  ev.sourceEventId = id !== undefined && id !== null ? `wp:${String(id)}` : null;
  return ev;
}

function eventsFromJson(data: Record<string, unknown>, base: string, ctx: ExtractContext): ExtractedEvent[] {
  const out: ExtractedEvent[] = [];
  for (const raw of asArray(data.events)) {
    if (!isRecord(raw)) continue;
    const ev = tribeEvent(raw, base, ctx);
    if (ev) out.push(ev);
  }
  return out;
}

/**
 * Extracts a tribe events response and, when `ctx.http` is available, follows `next_rest_url` on the same host up to
 * `maxPages` pages total.
 */
export async function extractWpTribe(
  page: Page,
  ctx: ExtractContext,
  maxPages = TRIBE_DEFAULT_MAX_PAGES,
): Promise<ExtractedEvent[]> {
  const data = parseJsonPage(page);
  if (!looksLikeTribeJson(data)) return [];
  const base = pageBase(page);
  const events = eventsFromJson(data, base, ctx);
  let next = tribeNextPageUrl(data, base);
  const visited = new Set([base]);
  for (let pageNo = 1; next && ctx.http && pageNo < maxPages && !visited.has(next); pageNo++) {
    visited.add(next);
    let res: Awaited<ReturnType<NonNullable<ExtractContext["http"]>["get"]>>;
    try {
      res = await ctx.http.get({ url: next, accept: "application/json" });
    } catch {
      break;
    }
    if (res.status < 200 || res.status >= 300 || res.notModified) break;
    let json: unknown;
    try {
      json = JSON.parse(res.text);
    } catch {
      break;
    }
    if (!looksLikeTribeJson(json)) break;
    events.push(...eventsFromJson(json, res.finalUrl, ctx));
    next = tribeNextPageUrl(json, res.finalUrl);
  }
  return dedupeEvents(events);
}

export const wpTribeExtractor: Extractor = {
  name: "wp_tribe",
  canHandle: (page) => looksLikeTribeJson(parseJsonPage(page)),
  extract: (page, ctx) => extractWpTribe(page, ctx),
};
