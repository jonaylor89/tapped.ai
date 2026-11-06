/**
 * City listing feed: configured, NON-ticketing local calendars (alt-weeklies, city/arts council calendars).
 * Each page is fetched politely, the venues named in its events are pulled out (schema.org JSON-LD `location`,
 * microdata `itemprop=location`, iCal LOCATION) and recorded as candidates. Venue identity is still resolved by
 * name + area (+ coordinates when present); a listing never becomes the source of a venue's events.
 *
 * `ExtractedEvent` intentionally has no venue field (the venue of a source is known from the source row), so the
 * venue references are parsed here from the listing page itself. Additional references (e.g. an LLM pass) can be
 * plugged in through `extraRefs`.
 */
import { load } from "cheerio";
import type { Db } from "../db.js";
import { isTicketingUrl, ticketingMatch } from "../denylist.js";
import { FetchBlockedError } from "../fetch.js";
import type { BoundingBox, Clock, HttpClient, Page } from "../types.js";
import { systemClock } from "../types.js";
import { parseHttpUrl, registrableDomain } from "../url.js";
import { type IdentityOptions, type RecordKind, recordProbe } from "./resolve.js";

export interface ListingFeedConfig {
  url: string;
  /** City the listing covers (used for name-only matching and stored on candidates). */
  city: string;
  timezone: string;
  /** Optional box the listing covers; venues with coordinates outside it are ignored. */
  area?: BoundingBox | null;
  label?: string | null;
}

export interface ListingVenueRef {
  name: string;
  address: string | null;
  lat: number | null;
  lng: number | null;
  /** The venue's own website, if the listing links it (never the listing's own venue page, never ticketing). */
  website: string | null;
  /** Link to the venue page on the listing site, kept as evidence only. */
  listingVenueUrl: string | null;
  eventCount: number;
  sampleEvents: string[];
}

interface RawRef {
  name: string;
  address: string | null;
  lat: number | null;
  lng: number | null;
  url: string | null;
  eventTitle: string | null;
}

const NOT_A_VENUE =
  /^(online|virtual|tba|tbd|various( locations)?|multiple locations|livestream|zoom|see (website|details))$/i;

function asArray<T>(value: T | T[] | null | undefined): T[] {
  if (value == null) return [];
  return Array.isArray(value) ? value : [value];
}

function text(value: unknown): string | null {
  if (typeof value === "string") return value.trim() || null;
  if (typeof value === "number") return String(value);
  return null;
}

function num(value: unknown): number | null {
  const n = typeof value === "string" ? Number.parseFloat(value) : typeof value === "number" ? value : Number.NaN;
  return Number.isFinite(n) ? n : null;
}

function isType(node: Record<string, unknown>, suffix: string): boolean {
  return asArray(node["@type"] as string | string[]).some((type) => typeof type === "string" && type.endsWith(suffix));
}

function addressText(address: unknown): string | null {
  if (typeof address === "string") return address.trim() || null;
  if (address && typeof address === "object") {
    const a = address as Record<string, unknown>;
    const parts = [a.streetAddress, a.addressLocality, a.addressRegion, a.postalCode].map(text).filter(Boolean);
    return parts.length ? parts.join(", ") : null;
  }
  return null;
}

/** Splits a free-text location ("The Hi-Fi, 1043 Virginia Ave, Indianapolis") into name + address. */
export function splitLocationText(value: string): { name: string; address: string | null } | null {
  const cleaned = value.replace(/\\,/g, ",").replace(/\s+/g, " ").trim();
  if (!cleaned) return null;
  const [first, ...rest] = cleaned.split(/\s*[,\n]\s*|\s+-\s+/);
  const name = (first ?? "").trim();
  if (!name || /^\d/.test(name) || NOT_A_VENUE.test(name)) return null;
  return { name, address: rest.length ? rest.join(", ") : null };
}

function refFromLocation(location: unknown, eventTitle: string | null): RawRef | null {
  if (typeof location === "string") {
    const split = splitLocationText(location);
    return split ? { ...split, lat: null, lng: null, url: null, eventTitle } : null;
  }
  if (!location || typeof location !== "object") return null;
  const place = location as Record<string, unknown>;
  if (isType(place, "VirtualLocation")) return null;
  const name = text(place.name);
  if (!name || NOT_A_VENUE.test(name)) return null;
  const geo = (place.geo ?? {}) as Record<string, unknown>;
  const url =
    text(place.url) ??
    asArray(place.sameAs as string | string[])
      .map(text)
      .find(Boolean) ??
    null;
  return {
    name,
    address: addressText(place.address),
    lat: num(geo.latitude),
    lng: num(geo.longitude),
    url,
    eventTitle,
  };
}

function walkJsonLd(node: unknown, visit: (event: Record<string, unknown>) => void, depth = 0): void {
  if (depth > 8 || node == null) return;
  if (Array.isArray(node)) {
    for (const item of node) walkJsonLd(item, visit, depth + 1);
    return;
  }
  if (typeof node !== "object") return;
  const obj = node as Record<string, unknown>;
  if (isType(obj, "Event")) visit(obj);
  if (obj["@graph"]) walkJsonLd(obj["@graph"], visit, depth + 1);
  if (obj.itemListElement) walkJsonLd(obj.itemListElement, visit, depth + 1);
  if (obj.item) walkJsonLd(obj.item, visit, depth + 1);
  if (obj.subEvent) walkJsonLd(obj.subEvent, visit, depth + 1);
}

function parseJsonLoose(raw: string): unknown {
  try {
    return JSON.parse(raw);
  } catch {
    try {
      // Common breakage: raw newlines/tabs inside strings, trailing commas.
      return JSON.parse(raw.replace(/[\n\r\t]+/g, " ").replace(/,\s*([}\]])/g, "$1"));
    } catch {
      return null;
    }
  }
}

function refsFromIcs(ics: string): RawRef[] {
  const unfolded = ics.replace(/\r?\n[ \t]/g, "");
  const refs: RawRef[] = [];
  for (const block of unfolded.split(/BEGIN:VEVENT/).slice(1)) {
    const location = block.match(/^LOCATION[^:\n]*:(.*)$/m)?.[1];
    const summary = block.match(/^SUMMARY[^:\n]*:(.*)$/m)?.[1]?.trim() ?? null;
    const geo = block.match(/^GEO[^:\n]*:([-\d.]+);([-\d.]+)/m);
    if (!location) continue;
    const split = splitLocationText(location);
    if (!split) continue;
    refs.push({
      ...split,
      lat: geo ? num(geo[1]) : null,
      lng: geo ? num(geo[2]) : null,
      url: null,
      eventTitle: summary,
    });
  }
  return refs;
}

function refsFromHtml(html: string): RawRef[] {
  const $ = load(html);
  const refs: RawRef[] = [];
  $('script[type="application/ld+json"]').each((_, el) => {
    const data = parseJsonLoose($(el).text());
    walkJsonLd(data, (event) => {
      const title = text(event.name);
      for (const location of asArray(event.location as unknown)) {
        const ref = refFromLocation(location, title);
        if (ref) refs.push(ref);
      }
    });
  });
  $('[itemscope][itemtype*="schema.org/"][itemtype$="Event"]').each((_, el) => {
    const event = $(el);
    const title = event.find('[itemprop="name"]').first().text().trim() || null;
    const location = event.find('[itemprop="location"]').first();
    if (!location.length) return;
    const name =
      location.find('[itemprop="name"]').first().text().trim() ||
      (location.attr("itemscope") === undefined ? location.text().trim() : "");
    if (!name || NOT_A_VENUE.test(name)) return;
    const address = location.find('[itemprop="address"]').first().text().replace(/\s+/g, " ").trim() || null;
    const url =
      location.find('[itemprop="url"]').first().attr("href") ?? location.find("a[href]").first().attr("href") ?? null;
    const lat = num(location.find('[itemprop="latitude"]').attr("content"));
    const lng = num(location.find('[itemprop="longitude"]').attr("content"));
    refs.push({ name, address, lat, lng, url, eventTitle: title });
  });
  return refs;
}

/** Extracts the venue references named by events on a listing page (HTML or iCal). */
export function extractListingVenueRefs(page: Pick<Page, "text" | "contentType" | "finalUrl">): ListingVenueRef[] {
  const isIcs = (page.contentType ?? "").includes("calendar") || /^\s*BEGIN:VCALENDAR/.test(page.text);
  const raw = isIcs ? refsFromIcs(page.text) : refsFromHtml(page.text);
  return aggregateRefs(raw, page.finalUrl);
}

function resolveUrl(href: string, base: string): string | null {
  try {
    return parseHttpUrl(new URL(href, base).href)?.href ?? null;
  } catch {
    return null;
  }
}

function aggregateRefs(raw: RawRef[], listingUrl: string): ListingVenueRef[] {
  const listingDomain = registrableDomain(listingUrl);
  const byName = new Map<string, ListingVenueRef>();
  for (const ref of raw) {
    const key = ref.name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, " ")
      .trim();
    if (!key) continue;
    const absolute = ref.url ? resolveUrl(ref.url, listingUrl) : null;
    const ownSite =
      absolute && !isTicketingUrl(absolute) && registrableDomain(absolute) !== listingDomain ? absolute : null;
    const listingVenueUrl = absolute && registrableDomain(absolute) === listingDomain ? absolute : null;
    const existing = byName.get(key);
    if (existing) {
      existing.eventCount++;
      existing.address ??= ref.address;
      existing.lat ??= ref.lat;
      existing.lng ??= ref.lng;
      existing.website ??= ownSite;
      existing.listingVenueUrl ??= listingVenueUrl;
      if (ref.eventTitle && existing.sampleEvents.length < 5) existing.sampleEvents.push(ref.eventTitle);
    } else {
      byName.set(key, {
        name: ref.name,
        address: ref.address,
        lat: ref.lat,
        lng: ref.lng,
        website: ownSite,
        listingVenueUrl,
        eventCount: 1,
        sampleEvents: ref.eventTitle ? [ref.eventTitle] : [],
      });
    }
  }
  return [...byName.values()];
}

export interface ListingDiscoverOptions extends IdentityOptions {
  /** Venues need at least this many events on the listing to become candidates. Default 1. */
  minEvents?: number;
  /** Extra venue references (e.g. from an LLM pass over the page). */
  extraRefs?: (page: Page, feed: ListingFeedConfig) => Promise<ListingVenueRef[]> | ListingVenueRef[];
  clock?: Clock;
}

export interface ListingDiscoverSummary {
  url: string;
  status: "ok" | "rejected_ticketing" | "blocked" | "http_error" | "not_modified";
  message?: string;
  venues: number;
  outcomes: Record<RecordKind, number>;
  candidateIds: number[];
}

/** Fetches one configured listing and records the venues it names. Ticketing domains are refused outright. */
export async function discoverFromListing(
  db: Db,
  http: HttpClient,
  feed: ListingFeedConfig,
  options: ListingDiscoverOptions = {},
): Promise<ListingDiscoverSummary> {
  const summary: ListingDiscoverSummary = {
    url: feed.url,
    status: "ok",
    venues: 0,
    outcomes: { created: 0, merged: 0, matched_venue: 0, needs_review: 0 },
    candidateIds: [],
  };
  const ticketing = ticketingMatch(feed.url);
  if (ticketing) return { ...summary, status: "rejected_ticketing", message: `ticketing platform (${ticketing})` };
  let result: Awaited<ReturnType<HttpClient["get"]>>;
  try {
    result = await http.get({ url: feed.url });
  } catch (error) {
    if (error instanceof FetchBlockedError) {
      return {
        ...summary,
        status: error.reason === "ticketing" ? "rejected_ticketing" : "blocked",
        message: error.message,
      };
    }
    throw error;
  }
  if (result.notModified) return { ...summary, status: "not_modified" };
  if (result.status < 200 || result.status >= 300) {
    return { ...summary, status: "http_error", message: `HTTP ${result.status}` };
  }
  const page: Page = {
    url: result.url,
    finalUrl: result.finalUrl,
    contentType: result.contentType,
    text: result.text,
    body: result.body,
    fetchedAt: result.fetchedAt,
  };
  const refs = [...extractListingVenueRefs(page), ...(options.extraRefs ? await options.extraRefs(page, feed) : [])];
  const now = options.now ?? (options.clock ?? systemClock).now().getTime();
  for (const ref of refs) {
    if (ref.eventCount < (options.minEvents ?? 1)) continue;
    if (feed.area && ref.lat != null && ref.lng != null) {
      const { south, west, north, east } = feed.area;
      if (ref.lat < south || ref.lat > north || ref.lng < west || ref.lng > east) continue;
    }
    summary.venues++;
    const outcome = await recordProbe(
      db,
      {
        name: ref.name,
        address: ref.address,
        city: feed.city,
        lat: ref.lat,
        lng: ref.lng,
        website: ref.website,
        timezone: feed.timezone,
        discoveredFrom: "listing",
        observationKey: `listing:${feed.url}`,
        observation: {
          listingUrl: feed.url,
          listingVenueUrl: ref.listingVenueUrl,
          eventCount: ref.eventCount,
          sampleEvents: ref.sampleEvents,
        },
        area: feed.area ?? null,
      },
      { ...options, now },
    );
    summary.outcomes[outcome.kind]++;
    summary.candidateIds.push(outcome.candidate.id);
  }
  return summary;
}
