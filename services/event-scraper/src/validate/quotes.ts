import { normalizeForMatch, normalizeForMatchSpaced, pageToText } from "../llm/text.js";

/**
 * Verbatim evidence verification. A quote is accepted only if, after normalization (entities decoded, case folded,
 * typographic punctuation unified, whitespace differences ignored), it appears in the page's visible text AND the
 * match starts and ends on word boundaries of the page text. So "Band A — Nov 1" never verifies against a page that
 * says "Band A — Nov 15" (whitespace-insensitive substring matching alone would accept it).
 */

/** Quotes shorter than this (after normalization) prove nothing and are rejected. */
export const MIN_QUOTE_CHARS = 4;

export interface QuoteIndex {
  /** Normalized haystack (whitespace removed). */
  readonly haystack: string;
  has(quote: string): boolean;
  /** Start offsets (in `haystack`) of every word-boundary match of the quote; empty when it does not verify. */
  positions(quote: string): number[];
}

const WORD_CHAR = /[\p{L}\p{N}]/u;

/**
 * Whitespace-free text plus, for every character, whether whitespace (a word break) preceded it in the original.
 */
function compact(text: string): { chars: string; breakBefore: boolean[] } {
  const spaced = normalizeForMatchSpaced(text);
  let chars = "";
  const breakBefore: boolean[] = [];
  let pendingBreak = true;
  for (const ch of spaced) {
    if (ch === " ") {
      pendingBreak = true;
      continue;
    }
    chars += ch;
    for (let i = 0; i < ch.length; i++) breakBefore.push(pendingBreak && i === 0);
    pendingBreak = false;
  }
  breakBefore.push(true); // end of text
  return { chars, breakBefore };
}

/** Builds a matcher over a page (HTML or plain text). Visible text plus the raw markup-stripped body are both used. */
export function buildQuoteIndex(pageText: string, contentType?: string | null): QuoteIndex {
  const visible = pageToText(pageText, contentType);
  // Also match against tag-stripped raw text so quotes from attributes-free inline markup ("<b>8</b>pm") still match.
  const raw = pageText.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/gi, " ").replace(/<[^>]*>/g, " ");
  const a = compact(visible);
  const b = compact(raw);
  // \u0000 separates the two texts and counts as a word break on both sides.
  const haystack = `${a.chars}\u0000${b.chars}`;
  const breakBefore = [...a.breakBefore.slice(0, -1), true, ...b.breakBefore];
  const isWord = (ch: string | undefined) => ch !== undefined && WORD_CHAR.test(ch);
  const positions = (quote: string): number[] => {
    const needle = normalizeForMatch(quote);
    if (needle.length < MIN_QUOTE_CHARS || needle.includes("\u0000")) return [];
    const startsWord = isWord(needle[0]);
    const endsWord = isWord(needle[needle.length - 1]);
    const found: number[] = [];
    for (let at = haystack.indexOf(needle); at !== -1; at = haystack.indexOf(needle, at + 1)) {
      const end = at + needle.length;
      // A match may not start or end inside a word of the page ("nov 1" inside "nov 15", "and a" inside "band a").
      if (startsWord && isWord(haystack[at - 1]) && !breakBefore[at]) continue;
      if (endsWord && isWord(haystack[end]) && !breakBefore[end]) continue;
      found.push(at);
    }
    return found;
  };
  return {
    haystack,
    has: (quote: string) => positions(quote).length > 0,
    positions,
  };
}

/** Max distance (whitespace-free characters) between a name quote and a separate date quote for the same event. */
export const NAME_DATE_PROXIMITY = 200;

/**
 * True when a name quote and a date quote occur close together on the page (in the same text copy), as on listings
 * that put the title and the date in separate elements. Distance is measured end-to-start in either order.
 */
export function quotesNear(
  index: QuoteIndex,
  nameQuote: string,
  dateQuote: string,
  max = NAME_DATE_PROXIMITY,
): boolean {
  const split = index.haystack.indexOf("\u0000");
  const side = (at: number) => (at < split ? 0 : 1);
  const nameLen = normalizeForMatch(nameQuote).length;
  const dateLen = normalizeForMatch(dateQuote).length;
  for (const a of index.positions(nameQuote)) {
    for (const b of index.positions(dateQuote)) {
      if (side(a) !== side(b)) continue;
      const gap = b >= a ? b - (a + nameLen) : a - (b + dateLen);
      if (gap <= max) return true;
    }
  }
  return false;
}

export interface QuoteCheck {
  verified: string[];
  missing: string[];
  tooShort: string[];
}

export function verifyQuotes(quotes: string[], index: QuoteIndex): QuoteCheck {
  const out: QuoteCheck = { verified: [], missing: [], tooShort: [] };
  for (const quote of quotes) {
    if (typeof quote !== "string") continue;
    if (normalizeForMatch(quote).length < MIN_QUOTE_CHARS) out.tooShort.push(quote);
    else if (index.has(quote)) out.verified.push(quote);
    else out.missing.push(quote);
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------------
// Does a quote support the extracted facts?
// ---------------------------------------------------------------------------------------------------------------------

const MONTH_WORDS = [
  "jan(?:uary)?",
  "feb(?:ruary)?",
  "mar(?:ch)?",
  "apr(?:il)?",
  "may",
  "june?",
  "july?",
  "aug(?:ust)?",
  "sep(?:t(?:ember)?)?",
  "oct(?:ober)?",
  "nov(?:ember)?",
  "dec(?:ember)?",
];

/**
 * True when the quote names this month/day as a date: "Nov 1", "November 1st", "1 Nov", "1st of November", "11/1",
 * "11/01/2026", "2026-11-01". Digits are compared at word boundaries, so "Nov 1" never matches "Nov 15".
 */
export function quoteMentionsDate(quote: string, month: number, day: number): boolean {
  if (month < 1 || month > 12 || day < 1 || day > 31) return false;
  const text = normalizeForMatchSpaced(quote);
  const name = MONTH_WORDS[month - 1] as string;
  const d = `0?${day}(?:st|nd|rd|th)?`;
  const m = `0?${month}`;
  const patterns = [
    // "Nov 1", "Nov. 1st", "November 1, 2026", "Friday, November 1"
    new RegExp(`(?<![a-z])${name}\\.?,?\\s*${d}(?![0-9])`),
    // "1 Nov", "1st of November"
    new RegExp(`(?<![0-9])${d}\\s*(?:of\\s+)?${name}(?![a-z])`),
    // "11/1", "11/01/2026", "11.1.", "2026-11-01"
    new RegExp(`(?<![0-9])${m}[/.-]0?${day}(?![0-9])`),
    // day-first numeric "1/11", "01.11.2026"
    new RegExp(`(?<![0-9])0?${day}[/.]${m}(?![0-9])`),
  ];
  return patterns.some((re) => re.test(text));
}

/** True when `needle` (title, performer) appears in the quote, ignoring case, spacing and typographic punctuation. */
export function quoteContains(quote: string, needle: string): boolean {
  const n = normalizeForMatch(needle);
  return n.length >= MIN_QUOTE_CHARS && normalizeForMatch(quote).includes(n);
}

const COMPACT_MONTHS: Array<[number, string]> = [
  [1, "jan(?:uary)?"],
  [2, "feb(?:ruary)?"],
  [3, "mar(?:ch)?"],
  [4, "apr(?:il)?"],
  [5, "may"],
  [6, "june?"],
  [7, "july?"],
  [8, "aug(?:ust)?"],
  [9, "sep(?:t(?:ember)?)?"],
  [10, "oct(?:ober)?"],
  [11, "nov(?:ember)?"],
  [12, "dec(?:ember)?"],
];
const COMPACT_MONTH_RE = new RegExp(`(${COMPACT_MONTHS.map(([, re]) => re).join("|")})\\.?,?(\\d{1,2})(?!\\d)`, "g");
const COMPACT_NUMERIC_RE = /(?<!\d)(?:20\d{2}-)?(\d{1,2})[/.-](\d{1,2})(?![\d])/g;

interface DateMention {
  at: number;
  end: number;
  month: number;
  day: number;
}

function monthNumber(word: string): number {
  for (const [n, re] of COMPACT_MONTHS) if (new RegExp(`^(?:${re})$`).test(word)) return n;
  return 0;
}

/**
 * Date mentions ("nov6", "november6,2026", "11/06", "2026-11-06") in a whitespace-free haystack slice. Ordinal suffixes
 * are not matched: in compact text "nov03the..." the "th" belongs to the next word.
 */
function dateMentions(haystack: string, from: number, to: number): DateMention[] {
  const slice = haystack.slice(from, to);
  const found: DateMention[] = [];
  for (const m of slice.matchAll(COMPACT_MONTH_RE)) {
    const month = monthNumber(m[1] as string);
    const day = Number(m[2]);
    if (month && day >= 1 && day <= 31)
      found.push({ at: from + (m.index ?? 0), end: from + (m.index ?? 0) + m[0].length, month, day });
  }
  for (const m of slice.matchAll(COMPACT_NUMERIC_RE)) {
    const month = Number(m[1]);
    const day = Number(m[2]);
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31)
      found.push({ at: from + (m.index ?? 0), end: from + (m.index ?? 0) + m[0].length, month, day });
  }
  return found;
}

/**
 * True when, for some occurrence of the name quote on the page, the date mention nearest to it (either side, within
 * `max` characters, same text copy) is one of `dates`. Listings put each item's date next to its own title; a model
 * that pairs a title with the neighbouring item's date fails this check even though that date is also close by.
 */
export function nearestDateIs(
  index: QuoteIndex,
  nameQuote: string,
  dates: Array<[number, number]>,
  max = NAME_DATE_PROXIMITY,
): boolean {
  const haystack = index.haystack;
  const split = haystack.indexOf("\u0000");
  const nameLen = normalizeForMatch(nameQuote).length;
  for (const at of index.positions(nameQuote)) {
    const lo = at < split ? 0 : split + 1;
    const hi = at < split ? split : haystack.length;
    const end = at + nameLen;
    const mentions = dateMentions(haystack, Math.max(lo, at - max - 20), Math.min(hi, end + max + 20));
    let best: DateMention | null = null;
    let bestGap = Number.POSITIVE_INFINITY;
    for (const m of mentions) {
      if (m.end > at && m.at < end) continue; // inside the title itself ("Nov 5 Showcase")
      const gap = m.at >= end ? m.at - end : at - m.end;
      if (gap <= max && gap < bestGap) {
        best = m;
        bestGap = gap;
      }
    }
    if (best && dates.some(([month, day]) => best.month === month && best.day === day)) return true;
  }
  return false;
}
