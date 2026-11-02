/**
 * Squarespace events collections: "<collection url>?format=json" returns `upcoming` / `past` arrays whose items carry
 * epoch-ms `startDate`/`endDate` (true instants) and the site's IANA `website.timeZone`.
 */
import * as cheerio from "cheerio";
import { isTicketingUrl } from "../denylist.js";
import type { ExtractContext, ExtractedEvent, ExtractedLocation, Extractor, Page } from "../types.js";
import { parseHttpUrl } from "../url.js";
import { instantToLocal } from "./time.js";
import {
  applyTitleStatus,
  asArray,
  blankEvent,
  categoryHint,
  cleanMultiline,
  cleanText,
  dedupeEvents,
  isRecord,
  pageBase,
  parseJsonPage,
  parsePriceText,
  resolveUrl,
} from "./util.js";

/** "https://venue.com/shows" -> "https://venue.com/shows?format=json" (other query params dropped). */
export function squarespaceJsonUrl(collectionUrl: string): string | null {
  const url = parseHttpUrl(collectionUrl);
  if (!url) return null;
  url.hash = "";
  url.search = "";
  url.searchParams.set("format", "json");
  return url.href;
}

function eventItems(data: Record<string, unknown>): Record<string, unknown>[] {
  const items = [...asArray(data.upcoming), ...asArray(data.items)].filter(isRecord);
  return items.filter((i) => typeof i.startDate === "number" || typeof i.startDate === "string");
}

export function looksLikeSquarespaceEvents(data: unknown): data is Record<string, unknown> {
  if (!isRecord(data)) return false;
  const collection = isRecord(data.collection) ? data.collection : null;
  if (Array.isArray(data.upcoming)) return true;
  if (collection && /event/i.test(String(collection.typeName ?? collection.type ?? ""))) return true;
  return Boolean(collection) && eventItems(data).length > 0;
}

function sqsLocation(loc: unknown): ExtractedLocation | null {
  if (!isRecord(loc)) return null;
  const name = cleanText(loc.addressTitle);
  const address = [loc.addressLine1, loc.addressLine2, loc.addressCountry].map(cleanText).filter(Boolean).join(", ");
  const lat = Number(loc.markerLat ?? loc.mapLat);
  const lng = Number(loc.markerLng ?? loc.mapLng);
  if (!name && !address) return null;
  // Squarespace's default map pin (its NYC office) is not real data.
  const defaultPin = Math.abs(lat - 40.7207559) < 1e-4 && Math.abs(lng + 74.0007613) < 1e-4;
  return {
    name,
    address: address || null,
    lat: Number.isFinite(lat) && lat !== 0 && !defaultPin ? lat : null,
    lng: Number.isFinite(lng) && lng !== 0 && !defaultPin ? lng : null,
    url: null,
  };
}

/** First outbound ticket-ish link in the event body (recorded only; never fetched). */
function ticketLinkFromHtml(html: unknown, base: string): string | null {
  if (typeof html !== "string" || !html.includes("<a")) return null;
  const $ = cheerio.load(html, null, false);
  let found: string | null = null;
  $("a[href]").each((_, a) => {
    if (found) return;
    const href = resolveUrl($(a).attr("href"), base);
    if (!href) return;
    if (isTicketingUrl(href) || /\b(tickets?|buy|rsvp)\b/i.test($(a).text())) found = href;
  });
  return found;
}

function toDate(value: unknown): Date | null {
  const n =
    typeof value === "number" ? value : typeof value === "string" && /^\d+$/.test(value) ? Number(value) : Number.NaN;
  if (Number.isFinite(n)) return new Date(n);
  if (typeof value === "string") {
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

export function extractSquarespace(page: Page, ctx: ExtractContext): ExtractedEvent[] {
  const data = parseJsonPage(page);
  if (!looksLikeSquarespaceEvents(data)) return [];
  const base = pageBase(page);
  const origin = new URL(base).origin;
  const out: ExtractedEvent[] = [];
  for (const item of eventItems(data)) {
    const start = toDate(item.startDate);
    if (!start) continue;
    const ev = blankEvent("squarespace");
    ev.title = cleanText(item.title);
    ev.startInstant = start.toISOString();
    ev.start = instantToLocal(start, ctx.timezone);
    ev.rawDateText = String(item.startDate);
    const end = toDate(item.endDate);
    if (end && end.getTime() > start.getTime()) ev.end = instantToLocal(end, ctx.timezone);
    ev.description = cleanMultiline(item.excerpt) ?? cleanMultiline(item.body);
    ev.eventUrl = resolveUrl(item.fullUrl, origin);
    ev.imageUrl = resolveUrl(item.assetUrl, base);
    ev.ticketUrl =
      resolveUrl(item.sourceUrl, base) ?? ticketLinkFromHtml(item.body, base) ?? ticketLinkFromHtml(item.excerpt, base);
    ev.location = sqsLocation(item.location);
    const labels = [...asArray(item.categories), ...asArray(item.tags)]
      .map(cleanText)
      .filter((l): l is string => Boolean(l));
    ev.category = categoryHint([], labels, ev.title);
    const priceText = cleanText(item.excerpt)?.match(
      /(?:\$\s?\d[^.\n]{0,40}|free (?:show|entry|admission)|no cover)/i,
    )?.[0];
    if (priceText) {
      const parsed = parsePriceText(priceText);
      ev.prices = parsed.prices;
      ev.isFree = parsed.isFree;
    }
    applyTitleStatus(ev);
    ev.sourceEventId = typeof item.id === "string" ? `sqs:${item.id}` : null;
    out.push(ev);
  }
  return dedupeEvents(out);
}

export const squarespaceExtractor: Extractor = {
  name: "squarespace",
  canHandle: (page) => looksLikeSquarespaceEvents(parseJsonPage(page)),
  extract: (page, ctx) => extractSquarespace(page, ctx),
};
