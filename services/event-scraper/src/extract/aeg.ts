/**
 * AEG venue sites (The National, ...) render their schedule from a public JSON file on the venue site's own content
 * host: `{ meta, events: [{ eventId, title: {...}, eventDateTimeISO, ... }] }`. The source URL is that file.
 * Ticket links are recorded as strings and never fetched.
 */
import type { ExtractContext, ExtractedEvent, Extractor, Page } from "../types.js";
import {
  applyTitleStatus,
  asArray,
  blankEvent,
  categoryHint,
  cleanMultiline,
  cleanText,
  dedupeEvents,
  isRecord,
  parseJsonPage,
} from "./util.js";

function eventsOf(data: unknown): Record<string, unknown>[] {
  if (!isRecord(data)) return [];
  return asArray(data.events)
    .filter(isRecord)
    .filter((e) => typeof e.eventDateTimeISO === "string" && isRecord(e.title));
}

export function looksLikeAegEvents(data: unknown): boolean {
  return isRecord(data) && isRecord(data.meta) && eventsOf(data).length > 0;
}

/** "2026-11-07T20:00:00" -> "2026-11-07T20:00"; anything else is not a local datetime. */
function localMinute(value: unknown): string | null {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(value) ? value.slice(0, 16) : null;
}

function names(value: unknown): string[] {
  const text = cleanText(value);
  if (!text) return [];
  return text
    .split(/\s*,\s*/)
    .map((name) => name.trim())
    .filter(Boolean);
}

export function extractAeg(page: Page, _ctx: ExtractContext): ExtractedEvent[] {
  const out: ExtractedEvent[] = [];
  for (const item of eventsOf(parseJsonPage(page))) {
    if (item.active === false || item.private === true || (item.publishStatus ?? 1) !== 1) continue;
    const title = item.title as Record<string, unknown>;
    const ticketing = isRecord(item.ticketing) ? item.ticketing : {};
    const ev = blankEvent("aeg");
    ev.title = cleanText(title.eventTitleText) ?? cleanText(title.headlinersText);
    ev.start = localMinute(item.eventDateTime);
    ev.startInstant = item.eventDateTimeISO as string;
    ev.timezone = cleanText(item.eventDateTimeZone);
    ev.rawDateText = item.eventDateTimeISO as string;
    ev.doors = localMinute(item.doorDateTime);
    ev.description = cleanMultiline(item.bio) ?? cleanMultiline(item.description);
    ev.ticketUrl = cleanText(ticketing.url) ?? cleanText(ticketing.ticketURL);
    ev.performers = [...new Set([...names(title.headlinersText), ...names(title.supportingText)])];
    ev.category = categoryHint([], [], ev.title);
    const status = cleanText(ticketing.status)?.toLowerCase() ?? "";
    if (/cancel/.test(status)) ev.status = "canceled";
    else if (/postpone/.test(status)) ev.status = "postponed";
    else if (/resched/.test(status)) ev.status = "rescheduled";
    else if (/sold\s*out/.test(status)) ev.status = "sold_out";
    applyTitleStatus(ev);
    ev.sourceEventId = cleanText(item.eventId) ? `aeg:${cleanText(item.eventId)}` : null;
    out.push(ev);
  }
  return dedupeEvents(out);
}

export const aegExtractor: Extractor = {
  name: "aeg",
  canHandle: (page) => looksLikeAegEvents(parseJsonPage(page)),
  extract: (page, ctx) => extractAeg(page, ctx),
};
