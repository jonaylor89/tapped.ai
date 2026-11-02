import type { ExtractedPrice } from "../types.js";

/**
 * Parses free-form price text ("$15 adv / $20 dos", "$10-$15", "Free w/ RSVP", "No cover", "SOLD OUT") into
 * integer-cent prices plus free / sold-out flags.
 */

export interface ParsedPriceText {
  prices: ExtractedPrice[];
  isFree: boolean | null;
  soldOut: boolean;
}

const CURRENCY_SYMBOLS: Record<string, string> = { $: "USD", "€": "EUR", "£": "GBP", "¥": "JPY" };
const CURRENCY_CODES = /\b(USD|CAD|AUD|NZD|EUR|GBP|MXN|JPY)\b/i;

const FREE_RE =
  /\b(free(?:\s+(?:show|entry|admission|event|concert|for all|with rsvp|w\/\s*rsvp))?|no cover|free admission|admission is free|no charge|complimentary|\$0(?:\.00)?(?!\.?\d))\b/i;
const NOT_FREE_RE = /\bfree\s+(?:drink|parking|shot|beer|merch|t-?shirt|food|popcorn|refill|wifi)\w*/gi;
export const SOLD_OUT_RE = /\bsold[\s-]*out\b/i;

/** Amount like "$15", "15.50", "€20", "USD 12", "15 dollars". Returns cents or null. */
function toCents(raw: string): number | null {
  const n = Number(raw.replace(/,/g, ""));
  if (!Number.isFinite(n) || n < 0 || n > 100_000) return null;
  return Math.round(n * 100);
}

function kindFor(context: string): ExtractedPrice["kind"] {
  const c = context.toLowerCase();
  if (/\b(adv|advance|presale|pre-sale|early\s*bird|online)\b/.test(c)) return "advance";
  if (/\b(door|doors|dos|day\s*of(\s*show)?|at the door)\b/.test(c)) return "door";
  if (/\b(vip|reserved|table|meet|package|premium|balcony|ga|general admission|student|members?)\b/.test(c)) {
    return /\b(ga|general admission)\b/.test(c) ? "ticket" : "other";
  }
  return "ticket";
}

/** "1,500.00" -> "1500.00" (thousands groups); "15,50" -> "15.50" (decimal comma). */
function amountText(raw: string): string {
  return /^\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?$/.test(raw) ? raw.replace(/,/g, "") : raw.replace(",", ".");
}

/**
 * Kind of the i-th of several amounts in one segment. Labels are either all before their amounts ("adv $15 dos $20")
 * or all after them ("$15 adv $20 dos"); the style is decided by whether the text before the first amount names a
 * kind. Each amount is then classified by its own label text only.
 */
function kindNear(segment: string, amounts: Array<{ start: number; end: number }>, i: number): ExtractedPrice["kind"] {
  const first = amounts[0] as { start: number };
  const prefixStyle = kindFor(segment.slice(0, first.start)) !== "ticket";
  const amount = amounts[i] as { start: number; end: number };
  const label = prefixStyle
    ? segment.slice(i === 0 ? 0 : (amounts[i - 1] as { end: number }).end, amount.start)
    : segment.slice(amount.end, i + 1 < amounts.length ? (amounts[i + 1] as { start: number }).start : segment.length);
  return kindFor(label);
}

export function detectCurrency(text: string, fallback: string | null = "USD"): string | null {
  for (const [symbol, code] of Object.entries(CURRENCY_SYMBOLS)) if (text.includes(symbol)) return code;
  const m = CURRENCY_CODES.exec(text);
  return m ? (m[1] as string).toUpperCase() : fallback;
}

/**
 * Parses price text. Segments are split on "/", ";", "|", "," and newlines; each segment's money amounts become one
 * price (a "$10-$15" range keeps min and max). Bare numbers without a currency marker are only accepted in a segment
 * that also says adv/door/ticket/cover/admission so years and times never become prices.
 */
export function parsePriceText(
  text: string | null | undefined,
  defaultCurrency: string | null = "USD",
): ParsedPriceText {
  const result: ParsedPriceText = { prices: [], isFree: null, soldOut: false };
  if (!text) return result;
  const source = text.replace(/\s+/g, " ").trim();
  if (!source) return result;
  result.soldOut = SOLD_OUT_RE.test(source);
  const freeProbe = source.replace(NOT_FREE_RE, " ");
  const mentionsFree = FREE_RE.test(freeProbe);
  const currency = detectCurrency(source, defaultCurrency);

  for (const segment of source.split(/\s*(?:\/|;|\||,(?!\d{3})|\n|\+(?=\s*\$))\s*/)) {
    if (!segment) continue;
    const amounts: Array<{ cents: number; start: number; end: number }> = [];
    // Thousands groups first ("$1,500"), then plain amounts with an optional decimal part ("$15", "$12.50", "€15,50").
    const moneyRe =
      /(?:[$€£¥]\s?(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d{1,5}(?:[.,]\d{1,2})?)(?![\d,])|(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d{1,5}(?:\.\d{1,2})?)\s?(?:usd|cad|eur|gbp|dollars?|bucks)\b)/gi;
    for (const m of segment.matchAll(moneyRe)) {
      const cents = toCents(amountText(m[1] ?? m[2] ?? ""));
      if (cents !== null) amounts.push({ cents, start: m.index ?? 0, end: (m.index ?? 0) + m[0].length });
    }
    if (!amounts.length && /\b(adv|advance|door|dos|tickets?|cover|admission|entry|ga)\b/i.test(segment)) {
      for (const m of segment.matchAll(
        /(?<![\d:])(\d{1,4}(?:\.\d{2})?)(?![\d:]|\s?(?:am|pm|p\.m\.|a\.m\.|\+|yrs?|years))/gi,
      )) {
        const cents = toCents(m[1] as string);
        if (cents !== null && cents <= 100_000)
          amounts.push({ cents, start: m.index ?? 0, end: (m.index ?? 0) + m[0].length });
      }
    }
    if (!amounts.length) continue;
    const values = amounts.map((a) => a.cents);
    const isRange = amounts.length === 2 && /\d\s*(?:-|–|—|to)\s*[$€£¥]?\s*\d/.test(segment);
    if (isRange || amounts.length === 1) {
      result.prices.push({
        kind: kindFor(segment),
        minCents: Math.min(...values),
        maxCents: Math.max(...values),
        currency,
        text: segment,
      });
    } else {
      // Several amounts in one segment ("$15 adv $20 dos"): each amount is labeled by the words next to it only.
      for (const [i, amount] of amounts.entries()) {
        result.prices.push({
          kind: kindNear(segment, amounts, i),
          minCents: amount.cents,
          maxCents: amount.cents,
          currency,
          text: segment,
        });
      }
    }
  }

  const paid = result.prices.some((p) => (p.maxCents ?? p.minCents ?? 0) > 0);
  if (mentionsFree && !paid) result.isFree = true;
  else if (paid) result.isFree = mentionsFree && /\bfree\b.*\b(before|until|with)\b/i.test(source) ? null : false;
  if (result.isFree === true && !result.prices.length) {
    result.prices.push({ kind: "ticket", minCents: 0, maxCents: 0, currency, text: source });
  }
  return result;
}

/** Normalizes extractor-supplied prices: integer cents, min <= max, non-negative, upper-case currency. */
export function normalizePrices(prices: ExtractedPrice[], defaultCurrency: string | null = "USD"): ExtractedPrice[] {
  const out: ExtractedPrice[] = [];
  const seen = new Set<string>();
  for (const price of prices ?? []) {
    if (!price) continue;
    let min = typeof price.minCents === "number" && Number.isFinite(price.minCents) ? Math.round(price.minCents) : null;
    let max = typeof price.maxCents === "number" && Number.isFinite(price.maxCents) ? Math.round(price.maxCents) : null;
    if (min !== null && min < 0) min = null;
    if (max !== null && max < 0) max = null;
    if (min === null && max === null) {
      // Text-only price: try to parse it.
      if (price.text) {
        const parsed = parsePriceText(price.text, defaultCurrency);
        for (const p of parsed.prices)
          pushUnique(out, seen, { ...p, kind: price.kind && price.kind !== "ticket" ? price.kind : p.kind });
      }
      continue;
    }
    if (min === null) min = max;
    if (max === null) max = min;
    if ((min as number) > (max as number)) [min, max] = [max, min];
    const currency = price.currency ? price.currency.toUpperCase().slice(0, 3) : defaultCurrency;
    const kind: ExtractedPrice["kind"] = ["ticket", "advance", "door", "other"].includes(price.kind)
      ? price.kind
      : "ticket";
    pushUnique(out, seen, { kind, minCents: min, maxCents: max, currency, text: price.text?.trim() || null });
  }
  return out;
}

function pushUnique(out: ExtractedPrice[], seen: Set<string>, price: ExtractedPrice): void {
  const key = `${price.kind}|${price.minCents}|${price.maxCents}|${price.currency}`;
  if (seen.has(key)) return;
  seen.add(key);
  out.push(price);
}
