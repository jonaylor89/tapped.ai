/**
 * Venue-name comparison used by identity resolution.
 *
 * Names are normalized with the shared `normalizeName` (accents/punctuation stripped, leading "the" dropped,
 * "&" -> "and"), then generic venue words ("bar", "club", "lounge", "live", "music hall", ...) are removed so
 * "The Hi-Fi" ~ "HiFi Indy" style variants compare on their distinctive tokens. Distinctive extra words such as
 * "Annex", "East" or "Upstairs" are kept: they usually mean a different room and must never auto-merge.
 */
import { normalizeName } from "../db.js";

/** Words that describe the kind of venue rather than identify it. */
export const GENERIC_NAME_TOKENS: ReadonlySet<string> = new Set([
  "the",
  "and",
  "at",
  "of",
  "on",
  "a",
  "bar",
  "club",
  "lounge",
  "live",
  "music",
  "hall",
  "venue",
  "nightclub",
  "night",
  "pub",
  "tavern",
  "saloon",
  "cafe",
  "restaurant",
  "grill",
  "theater",
  "theatre",
  "co",
  "company",
  "llc",
  "inc",
]);

export type NameRelation = "same" | "similar" | "different";

/** Similarity at/above which two names are considered the same venue. */
export const SAME_NAME_THRESHOLD = 0.8;

function stopTokens(extra: Iterable<string> | undefined): Set<string> {
  const stops = new Set(GENERIC_NAME_TOKENS);
  if (extra) for (const word of extra) for (const token of normalizeName(word).split(" ")) if (token) stops.add(token);
  return stops;
}

/**
 * Distinctive tokens of a venue name. `extraStop` adds context words (typically the city name) that should not
 * count as distinguishing ("Mercy Lounge Nashville" ~ "Mercy Lounge"). Falls back to all tokens when every
 * token is generic ("The Bar" -> ["bar"]).
 */
export function nameTokens(name: string, extraStop?: Iterable<string>): string[] {
  const all = normalizeName(name).split(" ").filter(Boolean);
  const stops = stopTokens(extraStop);
  const distinctive = all.filter((token) => !stops.has(token));
  if (distinctive.length) return distinctive;
  const genericOnly = all.filter((token) => GENERIC_NAME_TOKENS.has(token));
  return genericOnly.length ? genericOnly : all;
}

/** Compact key: distinctive tokens joined without spaces ("hi fi" and "hifi" both -> "hifi"). */
export function nameKey(name: string, extraStop?: Iterable<string>): string {
  return nameTokens(name, extraStop).join("");
}

/**
 * Token-set similarity in [0, 1] (Jaccard over distinctive tokens), with 1 for equal compact keys so spacing and
 * hyphenation differences ("Hi-Fi" / "HiFi") do not matter.
 */
export function nameSimilarity(a: string, b: string, extraStop?: Iterable<string>): number {
  const ta = nameTokens(a, extraStop);
  const tb = nameTokens(b, extraStop);
  if (!ta.length || !tb.length) return 0;
  if (ta.join("") === tb.join("")) return 1;
  const sa = new Set(ta);
  const sb = new Set(tb);
  let inter = 0;
  for (const token of sa) if (sb.has(token)) inter++;
  // Tokens that only differ by spacing ("hi fi" vs "hifi") get partial credit through the compact forms.
  if (inter === 0) {
    const ca = ta.join("");
    const cb = tb.join("");
    if (ca.length >= 4 && cb.length >= 4 && (ca.includes(cb) || cb.includes(ca))) {
      return Math.min(ca.length, cb.length) / Math.max(ca.length, cb.length) / 2;
    }
  }
  return inter / (sa.size + sb.size - inter);
}

/**
 * "same": confidently the same name. "similar": shares distinctive words but differs (e.g. "The Hi-Fi" vs
 * "Hi-Fi Annex" — rooms in one building); never auto-merged, routed to review. "different": unrelated.
 */
export function compareNames(a: string, b: string, extraStop?: Iterable<string>): NameRelation {
  const score = nameSimilarity(a, b, extraStop);
  if (score >= SAME_NAME_THRESHOLD) return "same";
  if (score > 0) return "similar";
  return "different";
}
