import * as cheerio from "cheerio";
import { normalizeName } from "../db.js";
import { isTicketingUrl } from "../denylist.js";
import type { EventCategory, EventStatus, ExtractedEvent, ExtractedPrice, Page } from "../types.js";
import { parseHttpUrl } from "../url.js";

/** A blank event with every field present, for extractors to fill. */
export function blankEvent(extractor: string): ExtractedEvent {
  return {
    title: null,
    start: null,
    timezone: null,
    startInstant: null,
    end: null,
    doors: null,
    description: null,
    imageUrl: null,
    eventUrl: null,
    ticketUrl: null,
    performers: [],
    prices: [],
    isFree: null,
    status: null,
    category: null,
    evidence: [],
    extractor,
    sourceEventId: null,
    rawDateText: null,
    location: null,
  };
}

const ENTITY_RE = /&(?:#\d+|#x[0-9a-f]+|[a-z][a-z0-9]+);/i;

/** Decodes HTML entities (twice if the text was double-encoded, as WordPress often does). */
export function decodeEntities(value: string): string {
  let out = value;
  for (let i = 0; i < 2 && ENTITY_RE.test(out); i++) {
    out = cheerio
      .load(
        `<textarea>${out.replace(/</g, "&lt;")}</textarea>`,
        null,
        false,
      )("textarea")
      .text();
  }
  return out;
}

/** Single-line text: tags stripped, entities decoded, whitespace collapsed. Null for empty/non-strings. */
export function cleanText(value: unknown): string | null {
  if (typeof value === "number") return String(value);
  if (typeof value !== "string") return null;
  let s = value;
  if (/<[a-z/!]/i.test(s)) s = cheerio.load(`<div>${s}</div>`, null, false)("div").text();
  s = decodeEntities(s).replace(/[   ]/g, " ").replace(/[​-‍﻿]/g, "").replace(/\s+/g, " ").trim();
  return s || null;
}

/** Multi-line text from HTML: block elements and <br> become newlines. */
export function cleanMultiline(value: unknown, maxLength = 4000): string | null {
  if (typeof value !== "string") return null;
  let s = value;
  if (/<[a-z/!]/i.test(s)) {
    const withBreaks = s.replace(/<br\s*\/?>/gi, "\n").replace(/<\/(p|div|li|h[1-6]|tr)>/gi, "\n");
    const $ = cheerio.load(`<div>${withBreaks}</div>`, null, false);
    $("script,style").remove();
    s = $("div").first().text();
  }
  s = decodeEntities(s)
    .replace(/\r\n?/g, "\n")
    .replace(/[   ]/g, " ")
    .replace(/[ \t]+/g, " ")
    .split("\n")
    .map((line) => line.trim())
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  if (!s) return null;
  return s.length > maxLength ? `${s.slice(0, maxLength - 1)}…` : s;
}

/** Resolves a possibly-relative http(s) URL against `base`. Returns null for other schemes or garbage. */
export function resolveUrl(value: unknown, base: string): string | null {
  if (typeof value !== "string") return null;
  const raw = decodeEntities(value.trim());
  if (!raw || raw.startsWith("#") || /^(javascript|mailto|tel|data):/i.test(raw)) return null;
  try {
    const url = new URL(raw.startsWith("//") ? `https:${raw}` : raw, base);
    return parseHttpUrl(url)?.href ?? null;
  } catch {
    return null;
  }
}

export function pageBase(page: Page): string {
  return page.finalUrl || page.url;
}

// ---------------------------------------------------------------------------------------------------------------------
// Prices
// ---------------------------------------------------------------------------------------------------------------------

const CURRENCY_SYMBOLS: Record<string, string> = { $: "USD", "£": "GBP", "€": "EUR", "¥": "JPY" };

/** "15", "15.00", "$15", "1,250.50" -> cents. */
export function toCents(value: unknown): number | null {
  if (typeof value === "number") return Number.isFinite(value) && value >= 0 ? Math.round(value * 100) : null;
  if (typeof value !== "string") return null;
  const m = value.replace(/,(?=\d{3}\b)/g, "").match(/(\d+(?:\.\d{1,2})?)/);
  if (!m) return null;
  const n = Number(m[1]);
  return Number.isFinite(n) ? Math.round(n * 100) : null;
}

export function priceKindFromLabel(label: string | null | undefined): ExtractedPrice["kind"] {
  const l = (label ?? "").toLowerCase();
  if (/\b(adv|advance|presale|pre-sale|early)/.test(l)) return "advance";
  if (/\b(door|doors|dos|day of)/.test(l)) return "door";
  if (/\b(ga|general|ticket|admission|entry|cover)/.test(l) || !l) return "ticket";
  return "other";
}

/**
 * Parses free-text price strings ("$15 adv / $20 dos", "$10-$25", "Free", "FREE w/ RSVP", "$12.50").
 * Returns prices and a free flag (true only when the text says free and lists no amount).
 */
export function parsePriceText(raw: string | null | undefined): { prices: ExtractedPrice[]; isFree: boolean | null } {
  const text = cleanText(raw);
  if (!text) return { prices: [], isFree: null };
  const prices: ExtractedPrice[] = [];
  const amountRe =
    /([$£€¥])?\s?(\d+(?:[.,]\d{2})?)(?:\s?(?:-|–|to)\s?([$£€¥])?\s?(\d+(?:[.,]\d{2})?))?\s*([a-z][a-z .]{0,14})?/gi;
  for (const m of text.matchAll(amountRe)) {
    const symbol = m[1] ?? m[3];
    const label = m[5]?.trim() ?? "";
    // Bare numbers without a currency symbol are only prices when the whole string is a number ("15", "15.00").
    if (!symbol && !/^\d+(?:[.,]\d{2})?$/.test(text.trim()) && !/\b(usd|dollars?)\b/i.test(label)) continue;
    const min = toCents(m[2].replace(",", "."));
    const max = m[4] ? toCents(m[4].replace(",", ".")) : min;
    prices.push({
      kind: priceKindFromLabel(label),
      minCents: min,
      maxCents: max,
      currency: symbol ? CURRENCY_SYMBOLS[symbol] : /\busd\b/i.test(label) ? "USD" : null,
      text,
    });
  }
  const saysFree = /\b(free|no cover|complimentary)\b(?!\s+(before|after|until|till)\b)/i.test(text);
  if (!prices.length && saysFree) return { prices: [], isFree: true };
  if (prices.length && prices.every((p) => p.minCents === 0 && p.maxCents === 0)) return { prices: [], isFree: true };
  return { prices, isFree: prices.length ? false : null };
}

// ---------------------------------------------------------------------------------------------------------------------
// Status / category hints
// ---------------------------------------------------------------------------------------------------------------------

/** Maps schema.org eventStatus (URL or bare) and iCal/CMS status words. */
export function mapStatus(value: unknown): EventStatus | null {
  if (typeof value !== "string" || !value.trim()) return null;
  const v = value
    .trim()
    .toLowerCase()
    .replace(/^.*[/:#]/, "");
  if (/cancel/.test(v)) return "canceled";
  if (/postpone/.test(v)) return "postponed";
  if (/reschedul/.test(v)) return "rescheduled";
  if (/sold.?out/.test(v)) return "sold_out";
  if (/scheduled|confirmed|tentative|movedonline/.test(v)) return "scheduled";
  return null;
}

const TITLE_STATUS_RE = /^\s*[[(*]?\s*(cancel+ed|postponed|rescheduled|sold[\s-]?out)\s*[\])*!]?\s*(?:[:\-–—|!]\s*)?/i;

/**
 * Venues often mark status in the title ("CANCELLED: The Band", "[SOLD OUT] The Band"). Moves that into `status`
 * (unless a structured status already says otherwise) and strips the prefix from the title.
 */
export function applyTitleStatus(ev: ExtractedEvent): void {
  if (!ev.title) return;
  const m = ev.title.match(TITLE_STATUS_RE);
  if (!m) return;
  const rest = ev.title.slice(m[0].length).trim();
  if (!rest) return;
  const status = mapStatus(m[1]);
  if (status && (ev.status === null || ev.status === "scheduled")) ev.status = status;
  ev.title = rest;
}

const TYPE_CATEGORY: Record<string, EventCategory> = {
  musicevent: "music",
  comedyevent: "comedy",
  theaterevent: "theater",
  danceevent: "dance",
};

const LABEL_RULES: [RegExp, EventCategory][] = [
  [/\bopen[\s-]?mic\b/i, "open_mic"],
  [/\b(comedy|comedian|comedians|stand[\s-]?up|improv)\b/i, "comedy"],
  [/\b(theat(er|re)|musical theat|play|drama|burlesque|cabaret)\b/i, "theater"],
  [/\b(dance performance|ballet|contemporary dance|tap dance|modern dance)\b/i, "dance"],
  [
    /\b(music|concert|live music|band|jazz|blues|rock|punk|metal|hip[\s-]?hop|rap|country|folk|bluegrass|indie|edm|electronic|dj|singer|songwriter|orchestra|symphony|r&b|soul|funk|reggae|americana|gig|tribute|choir|recital)s?\b/i,
    "music",
  ],
];

/**
 * Category hint from explicit structured signals: schema.org @type values and site category/tag labels, plus an
 * unmistakable "open mic" title. Returns null when nothing is explicit; validation makes the final call.
 */
export function categoryHint(types: string[], labels: string[], title: string | null): EventCategory | null {
  for (const t of types) {
    const c = TYPE_CATEGORY[t.toLowerCase().replace(/^.*[/:#]/, "")];
    if (c) return c;
  }
  if (title && /\bopen[\s-]?mic\b/i.test(title)) return "open_mic";
  const joined = labels.filter(Boolean).join(" | ");
  if (joined) {
    for (const [re, category] of LABEL_RULES) if (re.test(joined)) return category;
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------
// Dedupe
// ---------------------------------------------------------------------------------------------------------------------

function dayAndTime(ev: ExtractedEvent): string {
  return (ev.start ?? "").slice(0, 16);
}

/** Keys under which two extracted events are considered the same occurrence. */
export function dedupeKeys(ev: ExtractedEvent): string[] {
  const keys: string[] = [];
  const when = dayAndTime(ev);
  // Sites often repeat one @id/identifier on every occurrence of a recurring event, so the id alone is not an
  // occurrence key: it is combined with the start (bare id only when there is no date at all).
  if (ev.sourceEventId) keys.push(when ? `id:${ev.sourceEventId}|${when}` : `id:${ev.sourceEventId}`);
  if (ev.eventUrl && when) keys.push(`url:${ev.eventUrl.replace(/\/$/, "")}|${when}`);
  if (ev.title && when) keys.push(`title:${normalizeName(ev.title)}|${when}`);
  return keys;
}

function filledFields(ev: ExtractedEvent): number {
  let n = 0;
  for (const value of Object.values(ev)) {
    if (Array.isArray(value) ? value.length : value !== null && value !== undefined && value !== "") n++;
  }
  return n;
}

/** Fills null/empty fields of `primary` from `other` (same occurrence). */
export function mergeEvents(primary: ExtractedEvent, other: ExtractedEvent): ExtractedEvent {
  const out: ExtractedEvent = { ...primary };
  const rec = out as unknown as Record<string, unknown>;
  for (const [key, value] of Object.entries(other)) {
    if (key === "extractor") continue;
    const current = rec[key];
    const empty = current === null || current === undefined || (Array.isArray(current) && current.length === 0);
    if (empty && value !== null && value !== undefined) rec[key] = value;
  }
  return out;
}

/**
 * Removes duplicate occurrences, keeping first-seen order. When `preferFirst` is false the richer record wins as the
 * base; the other always fills its gaps.
 */
export function dedupeEvents(events: ExtractedEvent[], preferFirst = false): ExtractedEvent[] {
  const out: ExtractedEvent[] = [];
  const index = new Map<string, number>();
  for (const ev of events) {
    const keys = dedupeKeys(ev);
    const hit = keys.map((k) => index.get(k)).find((i) => i !== undefined);
    if (hit === undefined) {
      const i = out.push(ev) - 1;
      for (const k of keys) index.set(k, i);
      continue;
    }
    const existing = out[hit];
    out[hit] =
      preferFirst || filledFields(existing) >= filledFields(ev) ? mergeEvents(existing, ev) : mergeEvents(ev, existing);
    for (const k of dedupeKeys(out[hit])) if (!index.has(k)) index.set(k, hit);
  }
  return out;
}

export function uniqueStrings(values: (string | null | undefined)[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const v of values) {
    if (!v) continue;
    const key = v.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(v);
  }
  return out;
}

export function looksLikeHtml(page: Page): boolean {
  const ct = (page.contentType ?? "").toLowerCase();
  if (ct.includes("html") || ct.includes("xml")) return true;
  if (ct && !ct.includes("text/plain") && !ct.includes("octet-stream")) return false;
  return /<(html|head|body|div|script)\b/i.test(page.text.slice(0, 5000));
}

/** Parses a JSON page body; null when the body is not JSON. */
export function parseJsonPage(page: Page): unknown {
  const ct = (page.contentType ?? "").toLowerCase();
  const trimmed = page.text.replace(/^﻿/, "").trimStart();
  if (!ct.includes("json") && !(trimmed.startsWith("{") || trimmed.startsWith("["))) return null;
  try {
    return JSON.parse(trimmed);
  } catch {
    return null;
  }
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function asArray<T = unknown>(value: unknown): T[] {
  if (value === null || value === undefined) return [];
  return (Array.isArray(value) ? value : [value]) as T[];
}

/**
 * `eventUrl` must be a page on the venue's own site. A ticketing-platform link given as the event URL is moved to
 * `ticketUrl` (a string that is never fetched).
 */
export function moveTicketingEventUrl(ev: ExtractedEvent): ExtractedEvent {
  if (!ev.eventUrl || !isTicketingUrl(ev.eventUrl)) return ev;
  return { ...ev, ticketUrl: ev.ticketUrl ?? ev.eventUrl, eventUrl: null };
}
