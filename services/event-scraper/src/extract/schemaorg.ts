/**
 * Maps schema.org Event-shaped objects (from JSON-LD or converted microdata) to ExtractedEvent.
 */
import type { ExtractContext, ExtractedEvent, ExtractedLocation, ExtractedPrice, Page } from "../types.js";
import { type ParsedDate, parseClockOrDate, parseDateValue } from "./time.js";
import {
  applyTitleStatus,
  asArray,
  blankEvent,
  categoryHint,
  cleanMultiline,
  cleanText,
  isRecord,
  mapStatus,
  pageBase,
  priceKindFromLabel,
  resolveUrl,
  toCents,
  uniqueStrings,
} from "./util.js";

/** schema.org Event and its subtypes. */
export const EVENT_TYPES = new Set(
  [
    "Event",
    "MusicEvent",
    "ComedyEvent",
    "TheaterEvent",
    "DanceEvent",
    "Festival",
    "SocialEvent",
    "EducationEvent",
    "ScreeningEvent",
    "LiteraryEvent",
    "ExhibitionEvent",
    "VisualArtsEvent",
    "ChildrensEvent",
    "SportsEvent",
    "BusinessEvent",
    "FoodEvent",
    "PublicationEvent",
    "SaleEvent",
    "DeliveryEvent",
    "Hackathon",
    "CourseInstance",
    "EventSeries",
    "OnDemandEvent",
    "BroadcastEvent",
  ].map((t) => t.toLowerCase()),
);

/** Bare, lower-cased type names: "http://schema.org/MusicEvent" -> "musicevent". */
export function typeNames(value: unknown): string[] {
  return asArray(value)
    .filter((t): t is string => typeof t === "string")
    .map((t) =>
      t
        .trim()
        .replace(/^.*[/:#]/, "")
        .toLowerCase(),
    )
    .filter(Boolean);
}

export function isEventObject(obj: unknown): obj is Record<string, unknown> {
  return isRecord(obj) && typeNames(obj["@type"]).some((t) => EVENT_TYPES.has(t));
}

function first(value: unknown): unknown {
  return Array.isArray(value) ? value[0] : value;
}

function textOf(value: unknown): string | null {
  const v = first(value);
  if (isRecord(v)) return cleanText(v["@value"] ?? v.name ?? v.text);
  return cleanText(v);
}

function dateRaw(value: unknown): string | null {
  const v = first(value);
  if (typeof v === "string") return v.trim() || null;
  if (isRecord(v) && typeof v["@value"] === "string") return v["@value"];
  return null;
}

function urlOf(value: unknown, base: string): string | null {
  for (const v of asArray(value)) {
    const candidate = isRecord(v) ? (v.url ?? v.contentUrl ?? v["@id"]) : v;
    const url = resolveUrl(candidate, base);
    if (url) return url;
  }
  return null;
}

function addressText(value: unknown): string | null {
  const v = first(value);
  if (typeof v === "string") return cleanText(v);
  if (!isRecord(v)) return null;
  const parts = [v.streetAddress, v.addressLocality, v.addressRegion, v.postalCode, v.addressCountry]
    .map((p) => (isRecord(p) ? textOf(p.name) : cleanText(p)))
    .filter(Boolean);
  return parts.length ? parts.join(", ") : null;
}

function locationOf(value: unknown, base: string): { location: ExtractedLocation | null; virtualOnly: boolean } {
  const places = asArray(value);
  let physical: ExtractedLocation | null = null;
  let sawVirtual = false;
  for (const p of places) {
    if (typeof p === "string") {
      physical ??= { name: cleanText(p), address: null, lat: null, lng: null, url: null };
      continue;
    }
    if (!isRecord(p)) continue;
    if (typeNames(p["@type"]).includes("virtuallocation")) {
      sawVirtual = true;
      continue;
    }
    const geo = isRecord(p.geo) ? p.geo : null;
    const lat = geo ? Number(geo.latitude) : Number.NaN;
    const lng = geo ? Number(geo.longitude) : Number.NaN;
    physical ??= {
      name: textOf(p.name),
      address: addressText(p.address),
      lat: Number.isFinite(lat) ? lat : null,
      lng: Number.isFinite(lng) ? lng : null,
      url: resolveUrl(first(p.url) ?? first(p.sameAs), base),
    };
  }
  return { location: physical, virtualOnly: sawVirtual && !physical };
}

function performersOf(...values: unknown[]): string[] {
  const names: (string | null)[] = [];
  for (const value of values) {
    for (const p of asArray(value)) {
      names.push(isRecord(p) ? textOf(p.name) : cleanText(p));
    }
  }
  return uniqueStrings(names);
}

function offersOf(value: unknown, base: string) {
  const prices: ExtractedPrice[] = [];
  let ticketUrl: string | null = null;
  let soldOut = false;
  const queue = asArray(value);
  for (let i = 0; i < queue.length && i < 50; i++) {
    const offer = queue[i];
    if (!isRecord(offer)) continue;
    if (offer.offers) queue.push(...asArray(offer.offers)); // AggregateOffer.offers
    ticketUrl ??= resolveUrl(first(offer.url), base);
    const availability = typeof offer.availability === "string" ? offer.availability : "";
    if (/soldout/i.test(availability.replace(/[\s_-]/g, ""))) soldOut = true;
    const spec = isRecord(offer.priceSpecification) ? offer.priceSpecification : null;
    const priceValue = offer.price ?? spec?.price;
    const low = offer.lowPrice ?? spec?.minPrice;
    const high = offer.highPrice ?? spec?.maxPrice;
    const min = toCents(low ?? priceValue);
    const max = toCents(high ?? priceValue ?? low);
    if (min === null && max === null) continue;
    const currency = cleanText(offer.priceCurrency ?? spec?.priceCurrency);
    const label = cleanText(offer.name) ?? cleanText(offer.category) ?? null;
    prices.push({
      kind: priceKindFromLabel(label),
      minCents: min,
      maxCents: max ?? min,
      currency: currency ? currency.toUpperCase() : null,
      // Keep free-text prices ("$15 adv / $20 dos") but not bare numbers, which add nothing to min/max.
      text:
        label ??
        (typeof priceValue === "string" && !/^\s*\d+(\.\d+)?\s*$/.test(priceValue) ? cleanText(priceValue) : null),
    });
  }
  // Collapse duplicate offers (same kind and amounts).
  const seen = new Set<string>();
  const unique = prices.filter((p) => {
    const k = `${p.kind}|${p.minCents}|${p.maxCents}|${p.currency}`;
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
  return { prices: unique, ticketUrl, soldOut };
}

function keywordsOf(obj: Record<string, unknown>): string[] {
  const out: string[] = [];
  for (const key of ["keywords", "genre", "about", "eventType", "category"]) {
    for (const v of asArray(obj[key])) {
      const t = isRecord(v) ? textOf(v.name) : cleanText(v);
      if (t) out.push(...t.split(/\s*,\s*/));
    }
  }
  return out;
}

/** True when an offset-carrying date should be read as the venue's wall clock (numeric offset, not "Z"). */
function prefersWallClock(parsed: ParsedDate): boolean {
  return Boolean(parsed.instant && parsed.wallClock && parsed.zone && parsed.zone.toUpperCase() !== "Z");
}

/** Converts one schema.org Event object. Returns null for online-only events or ones without any title/date. */
export function eventFromSchema(
  obj: Record<string, unknown>,
  page: Page,
  ctx: ExtractContext,
  extractor: string,
): ExtractedEvent | null {
  const base = pageBase(page);
  const tz = ctx.timezone;
  const ev = blankEvent(extractor);
  const types = typeNames(obj["@type"]);

  const attendance = typeof obj.eventAttendanceMode === "string" ? obj.eventAttendanceMode : "";
  const { location, virtualOnly } = locationOf(obj.location, base);
  if (/online/i.test(attendance) && !/mixed/i.test(attendance) && !location) return null;
  if (virtualOnly) return null;
  ev.location = location;

  ev.title = textOf(obj.name) ?? textOf(obj.headline) ?? textOf(obj.alternateName);

  const startRaw = dateRaw(obj.startDate);
  ev.rawDateText = startRaw;
  const start = parseDateValue(startRaw, tz);
  const useWallClock = start ? prefersWallClock(start) : false;
  if (start) {
    // With a numeric offset the digits before it are what the venue typed; validation compares them with the
    // instant (in the venue zone) and keeps the wall clock when the site's offset is wrong (e.g. "+00:00" written
    // for a New York show). "Z" values are usually machine-generated true UTC, so they keep the converted time.
    ev.start = useWallClock ? (start.wallClock ?? start.local) : start.local;
    ev.startInstant = start.instant;
  }
  const endRaw = dateRaw(obj.endDate);
  const end = endRaw ? parseDateValue(endRaw, tz) : null;
  ev.end = end
    ? useWallClock && end.wallClock && end.zone === start?.zone
      ? end.wallClock
      : end.local
    : parseClockOrDate(endRaw, tz);
  // A date-only end equal to the start date carries no information.
  if (ev.end && ev.start && ev.end === ev.start.slice(0, 10)) ev.end = null;
  ev.doors = parseClockOrDate(dateRaw(obj.doorTime), tz);
  if (!ev.title && !ev.start) return null;

  ev.description = cleanMultiline(first(obj.description));
  ev.imageUrl = urlOf(obj.image, base) ?? urlOf(obj.thumbnailUrl, base);
  const id = typeof obj["@id"] === "string" ? obj["@id"] : null;
  ev.eventUrl =
    resolveUrl(first(obj.url), base) ?? (id && /^https?:/i.test(id) ? resolveUrl(id.split("#")[0], base) : null);
  if (ev.eventUrl && ev.eventUrl === base && !first(obj.url)) ev.eventUrl = null;
  ev.performers = performersOf(obj.performer, obj.performers);

  const offers = offersOf(obj.offers, base);
  ev.prices = offers.prices;
  ev.ticketUrl = offers.ticketUrl && offers.ticketUrl !== ev.eventUrl ? offers.ticketUrl : null;

  if (typeof obj.isAccessibleForFree === "boolean") ev.isFree = obj.isAccessibleForFree;
  else if (typeof obj.isAccessibleForFree === "string") ev.isFree = /^true$/i.test(obj.isAccessibleForFree);
  else if (ev.prices.length && ev.prices.every((p) => p.minCents === 0 && (p.maxCents ?? 0) === 0)) ev.isFree = true;
  else if (ev.prices.some((p) => (p.minCents ?? 0) > 0)) ev.isFree = false;
  if (ev.isFree) ev.prices = ev.prices.filter((p) => (p.maxCents ?? 0) > 0);

  ev.status = mapStatus(first(obj.eventStatus));
  if (offers.soldOut && (ev.status === null || ev.status === "scheduled")) ev.status = "sold_out";

  applyTitleStatus(ev);
  ev.category = categoryHint(types, keywordsOf(obj), ev.title);
  const identifier = textOf(obj.identifier);
  ev.sourceEventId = identifier ?? (id && !/^_:/.test(id) ? id : null);
  return ev;
}

/**
 * Finds Event objects anywhere in a parsed JSON-LD document: top-level arrays, @graph, ItemList/ListItem.item,
 * nested `event`/`events` on Places/Organizations, and EventSeries.subEvent (the series itself is dropped when it has
 * dated sub-events).
 */
export function collectEventObjects(root: unknown): Record<string, unknown>[] {
  const out: Record<string, unknown>[] = [];
  const seen = new Set<unknown>();
  const visit = (node: unknown, depth: number) => {
    if (depth > 12 || node === null || typeof node !== "object" || seen.has(node)) return;
    seen.add(node);
    if (Array.isArray(node)) {
      for (const n of node) visit(n, depth + 1);
      return;
    }
    const obj = node as Record<string, unknown>;
    if (isEventObject(obj)) {
      const subs = asArray(obj.subEvent ?? obj.subEvents).filter(isEventObject);
      const datedSubs = subs.filter((s) => s.startDate);
      if (datedSubs.length) {
        for (const s of datedSubs) visit(s, depth + 1);
        return;
      }
      out.push(obj);
      return;
    }
    for (const [key, value] of Object.entries(obj)) {
      if (key === "@context") continue;
      visit(value, depth + 1);
    }
  };
  visit(root, 0);
  return out;
}
