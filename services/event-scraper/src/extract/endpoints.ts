/**
 * Finds machine-readable calendar endpoints advertised by a venue page: iCal feeds, The Events Calendar REST API and
 * Squarespace events collections. Ticketing-platform URLs are never returned.
 */
import * as cheerio from "cheerio";
import { isTicketingUrl } from "../denylist.js";
import { normalizedHost, parseHttpUrl, registrableDomain } from "../url.js";
import { squarespaceJsonUrl } from "./squarespace.js";
import { tribeEventsApiUrl } from "./wp-tribe.js";

export type StructuredEndpointKind = "ical" | "wp_tribe" | "squarespace";

export interface StructuredEndpoint {
  kind: StructuredEndpointKind;
  url: string;
  /** Same registrable domain as the page (the venue's own site). */
  sameSite: boolean;
  /** Public calendar host that is safe to follow even though it is off-site (Google Calendar ICS). */
  trustedCalendarHost: boolean;
  /** Short reason for logs/review ("link[rel=alternate][type=text/calendar]", "tribe markup"...). */
  reason: string;
  /** Higher is better; endpoints are returned sorted by it. */
  confidence: number;
}

/** Off-site hosts that serve public calendars (not ticketing). */
export const TRUSTED_CALENDAR_HOSTS = new Set(["calendar.google.com"]);

const EVENT_PATH_RE =
  /^\/(events?|shows?|calendar|concerts?|upcoming(-events|-shows)?|live(-music)?|music|whats-on|schedule|lineup)\/?$/i;

function toHttp(href: string, base: string): URL | null {
  const raw = href.trim().replace(/^webcals?:\/\//i, "https://");
  try {
    return parseHttpUrl(new URL(raw, base));
  } catch {
    return null;
  }
}

/** ICS URL for a Google Calendar embed (`/calendar/embed?src=<id>`), or null. */
export function googleCalendarIcsUrl(embedUrl: string): string | null {
  const url = parseHttpUrl(embedUrl);
  if (!url || url.hostname !== "calendar.google.com") return null;
  if (/\/calendar\/ical\//.test(url.pathname)) return url.href;
  const src = url.searchParams.get("src") ?? url.searchParams.get("cid");
  if (!src) return null;
  let id = src;
  if (url.searchParams.get("cid") && !src.includes("@")) {
    try {
      id = Buffer.from(src, "base64").toString("utf8");
    } catch {
      return null;
    }
  }
  if (!/^[\w.+-]+@[\w.-]+$/.test(id)) return null;
  return `https://calendar.google.com/calendar/ical/${encodeURIComponent(id)}/public/basic.ics`;
}

export function discoverStructuredEndpoints(html: string, pageUrl: string): StructuredEndpoint[] {
  const page = parseHttpUrl(pageUrl);
  if (!page) return [];
  const $ = cheerio.load(html);
  const pageDomain = registrableDomain(page);
  const found = new Map<string, StructuredEndpoint>();

  const add = (kind: StructuredEndpointKind, rawUrl: string | null, reason: string, confidence: number) => {
    if (!rawUrl) return;
    const url = parseHttpUrl(rawUrl);
    if (!url || isTicketingUrl(url.href)) return;
    url.hash = "";
    const href = url.href;
    const host = normalizedHost(url) ?? "";
    const sameSite = registrableDomain(url) === pageDomain;
    const trustedCalendarHost = TRUSTED_CALENDAR_HOSTS.has(host);
    if (!sameSite && !trustedCalendarHost) return;
    const existing = found.get(href);
    if (existing && existing.confidence >= confidence) return;
    found.set(href, { kind, url: href, sameSite, trustedCalendarHost, reason, confidence });
  };

  // --- iCal -------------------------------------------------------------------------------------------------------
  $('link[type="text/calendar" i][href]').each((_, el) => {
    add("ical", toHttp($(el).attr("href") ?? "", page.href)?.href ?? null, "link[type=text/calendar]", 0.95);
  });
  $("a[href], area[href]").each((_, el) => {
    const href = $(el).attr("href") ?? "";
    const url = toHttp(href, page.href);
    if (!url) return;
    const isWebcal = /^webcals?:/i.test(href.trim());
    const path = url.pathname.toLowerCase();
    if (isWebcal || path.endsWith(".ics") || path.endsWith(".ical") || path.endsWith(".ifb")) {
      add("ical", url.href, isWebcal ? "webcal link" : ".ics link", 0.85);
    } else if (url.searchParams.get("ical") === "1" || url.searchParams.has("outlook-ical")) {
      // TEC export links: /events/?ical=1 (a list export, good) vs single-event exports under /event/<slug>/.
      const single = /\/event\/[^/]+\/?$/.test(url.pathname);
      add("ical", url.href, "tribe ical export link", single ? 0.3 : 0.8);
    } else if (url.hostname === "calendar.google.com") {
      add("ical", googleCalendarIcsUrl(url.href), "google calendar link", 0.7);
    }
  });
  $("iframe[src]").each((_, el) => {
    const src = toHttp($(el).attr("src") ?? "", page.href);
    if (src?.hostname === "calendar.google.com")
      add("ical", googleCalendarIcsUrl(src.href), "google calendar embed", 0.75);
  });

  // --- The Events Calendar (WordPress) ----------------------------------------------------------------------------
  // No start_date: the API defaults to "now" in the site's own zone, which is exactly the window we want.
  const tribeAlternate = $('link[rel="alternate"][href*="/tribe/events/v1"]').attr("href");
  const wpJsonRoot = $('link[rel="https://api.w.org/"]').attr("href");
  const tribeMarkup =
    $(".tribe-events, .tribe-events-calendar, .tribe-common, .tribe-events-view, [class*='tribe-events-']").length >
      0 ||
    /\/wp-content\/plugins\/the-events-calendar\//i.test(html) ||
    /tribe_events|tribe-events-calendar|TribeEventsPro|tribe_l10n_datatables/i.test(html);
  if (tribeAlternate) {
    const abs = toHttp(tribeAlternate, page.href);
    add("wp_tribe", abs ? tribeEventsApiUrl(abs.href) : null, "link[rel=alternate] tribe api", 0.92);
  }
  if (tribeMarkup) {
    const root = wpJsonRoot ? toHttp(wpJsonRoot, page.href) : null;
    const apiUrl = root ? tribeEventsApiUrl(root.href) : tribeEventsApiUrl(page.origin);
    add("wp_tribe", apiUrl, wpJsonRoot ? "tribe markup + wp-json root" : "tribe markup", wpJsonRoot ? 0.9 : 0.7);
  }

  // --- Squarespace -----------------------------------------------------------------------------------------------
  const isSquarespace =
    /Static\.SQUARESPACE_CONTEXT|static1\.squarespace\.com|squarespace-cdn\.com|<!-- This is Squarespace\. -->/i.test(
      html,
    ) || /squarespace/i.test($('meta[name="generator" i]').attr("content") ?? "");
  if (isSquarespace) {
    const eventListOnPage =
      $(
        ".eventlist, .eventlist-event, [data-controller='EventList'], .summary-item-record-type-event, .user-items-list-events",
      ).length > 0 || /"typeName"\s*:\s*"events"|collection-type-events|view-list.*eventlist/i.test(html);
    if (eventListOnPage && !$(".summary-item-record-type-event").length) {
      add("squarespace", squarespaceJsonUrl(page.href), "squarespace event list on page", 0.9);
    }
    // Summary blocks embed another collection: data-block-json contains its collectionId; links to it point at the list.
    $("a[href]").each((_, el) => {
      const url = toHttp($(el).attr("href") ?? "", page.href);
      if (!url || normalizedHost(url) !== normalizedHost(page)) return;
      if (EVENT_PATH_RE.test(url.pathname))
        add("squarespace", squarespaceJsonUrl(url.href), "squarespace events nav link", 0.5);
    });
  }

  return [...found.values()].sort((a, b) => b.confidence - a.confidence);
}
