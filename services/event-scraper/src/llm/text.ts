import * as cheerio from "cheerio";

/**
 * Page text helpers shared by the LLM prompt builder and evidence-quote verification.
 * - `pageToText` turns HTML into readable line-oriented text (block elements become line breaks).
 * - `cleanPageText` additionally strips boilerplate (nav, footer, cookie banners, forms) for the LLM.
 * - `chunkText` splits long text on line boundaries with overlap so events straddling a boundary survive.
 */

const ALWAYS_REMOVE = "script, style, noscript, template, svg, canvas, iframe, object, embed, link, meta, head";

/** Elements that are almost never event content. Removed only for the LLM view (quotes are verified on the full text). */
const BOILERPLATE_SELECTORS = [
  "nav",
  "footer",
  "form",
  "button",
  "select",
  "dialog",
  "[role=navigation]",
  "[role=banner]",
  "[role=contentinfo]",
  "[role=search]",
  "[role=dialog]",
  "[aria-hidden=true]",
  "[hidden]",
];

/** id/class fragments of banners, menus and widgets that drown event text. */
const BOILERPLATE_HINT =
  /(^|[-_\s])(cookie|consent|gdpr|newsletter|subscribe|signup|sign-up|popup|modal|share|social|breadcrumb|skip-link|menu|navbar|site-header|site-footer|mailchimp)([-_\s]|$)/i;

const BLOCK_TAGS = new Set([
  "address",
  "article",
  "aside",
  "blockquote",
  "br",
  "dd",
  "details",
  "div",
  "dl",
  "dt",
  "fieldset",
  "figcaption",
  "figure",
  "footer",
  "h1",
  "h2",
  "h3",
  "h4",
  "h5",
  "h6",
  "header",
  "hr",
  "li",
  "main",
  "nav",
  "ol",
  "p",
  "pre",
  "section",
  "summary",
  "table",
  "tbody",
  "td",
  "tfoot",
  "th",
  "thead",
  "time",
  "tr",
  "ul",
]);

export function looksLikeHtml(text: string, contentType?: string | null): boolean {
  if (contentType) {
    const ct = contentType.toLowerCase();
    if (ct.includes("html") || ct.includes("xml+xhtml")) return true;
    if (ct.includes("json") || ct.includes("calendar") || ct.startsWith("text/plain")) return false;
  }
  return /<\s*(html|body|div|p|span|section|article|li|table|a)\b/i.test(text.slice(0, 20_000));
}

/** Structural view of domhandler nodes (avoids importing the transitive domhandler package). */
interface RawNode {
  type: string;
  name?: string;
  data?: string;
  attribs?: Record<string, string>;
  children?: RawNode[];
}

/** Line the LLM text uses between listing items (li, article, tr, role=listitem). */
export const ITEM_SEPARATOR = "---";
const ITEM_TAGS = new Set(["li", "article", "tr"]);

interface TextOptions {
  stripBoilerplate: boolean;
  /** Emit ITEM_SEPARATOR lines between listing items (LLM text only). */
  items?: boolean;
}

function render(html: string, options: TextOptions): string {
  const $ = cheerio.load(html);
  $(ALWAYS_REMOVE).remove();
  if (options.stripBoilerplate) {
    $(BOILERPLATE_SELECTORS.join(", ")).remove();
    $("[id], [class]").each((_, el) => {
      const node = $(el);
      const tag = (el as { tagName?: string }).tagName?.toLowerCase();
      if (tag === "body" || tag === "html" || tag === "main" || tag === "article") return;
      const hint = `${node.attr("id") ?? ""} ${node.attr("class") ?? ""}`;
      if (BOILERPLATE_HINT.test(hint)) node.remove();
    });
  }
  const out: string[] = [];
  const walk = (nodes: RawNode[]): void => {
    for (const node of nodes) {
      if (node.type === "text") {
        out.push(node.data ?? "");
        continue;
      }
      if (node.type !== "tag" && node.type !== "root") continue;
      const tag = (node.name ?? "").toLowerCase();
      const block = BLOCK_TAGS.has(tag);
      // Listing items are kept apart for the LLM, so a title is never paired with a neighbouring item's date.
      const item = options.items === true && (ITEM_TAGS.has(tag) || node.attribs?.role === "listitem");
      if (item) out.push(`\n${ITEM_SEPARATOR}\n`);
      if (block) out.push("\n");
      if (tag === "img" && !options.stripBoilerplate && node.attribs?.alt) out.push(` ${node.attribs.alt} `);
      if (tag === "td" || tag === "th") out.push(" ");
      walk(node.children ?? []);
      if (block) out.push("\n");
    }
  };
  const body = $("body").get(0) as unknown as RawNode | undefined;
  walk(body ? (body.children ?? []) : (($.root().get(0) as unknown as RawNode).children ?? []));
  return tidy(out.join(""));
}

/** Collapses runs of spaces, trims lines and drops blank lines (nested blocks would otherwise double them). */
export function tidy(text: string): string {
  return text
    .replace(/\r\n?/g, "\n")
    .replace(/[\t\f\v  -   　]+/g, " ")
    .replace(/[​-‍﻿]/g, "")
    .split("\n")
    .map((line) => line.replace(/ {2,}/g, " ").trim())
    .join("\n")
    .replace(/\n{2,}/g, "\n")
    .trim()
    .replace(/^(?:---(?:\n|$))+/, "")
    .replace(/(?:\n---)+$/, "")
    .replace(/(?:\n---)+(?=\n)/g, "\n---")
    .trim();
}

/** Full readable text of a page (nothing but scripts/styles removed). Non-HTML content is returned tidied. */
export function pageToText(text: string, contentType?: string | null): string {
  if (!looksLikeHtml(text, contentType)) return tidy(text);
  return render(text, { stripBoilerplate: false });
}

/** Readable text with boilerplate removed, for the LLM prompt. Falls back to the full text if stripping empties it. */
export function cleanPageText(text: string, contentType?: string | null): string {
  if (!looksLikeHtml(text, contentType)) return tidy(text);
  const cleaned = render(text, { stripBoilerplate: true, items: true });
  return cleaned.length >= 200 ? cleaned : render(text, { stripBoilerplate: false, items: true });
}

export interface ChunkOptions {
  /** Max characters per chunk (default 24_000, ~6k tokens). */
  maxChars?: number;
  /** Characters of trailing context repeated at the start of the next chunk (default 1_500). */
  overlapChars?: number;
  /** Hard cap on chunks returned (default 6). Remaining text is dropped. */
  maxChunks?: number;
}

/** Splits text on line boundaries into overlapping chunks. Very long single lines are hard-split. */
export function chunkText(text: string, options: ChunkOptions = {}): string[] {
  const maxChars = Math.max(500, options.maxChars ?? 24_000);
  const overlap = Math.min(Math.max(0, options.overlapChars ?? 1_500), Math.floor(maxChars / 2));
  const maxChunks = Math.max(1, options.maxChunks ?? 6);
  if (text.length <= maxChars) return text ? [text] : [];

  const lines: string[] = [];
  for (const line of text.split("\n")) {
    if (line.length <= maxChars - overlap) lines.push(line);
    else for (let i = 0; i < line.length; i += maxChars - overlap) lines.push(line.slice(i, i + maxChars - overlap));
  }

  const chunks: string[] = [];
  let current: string[] = [];
  let size = 0;
  for (const line of lines) {
    if (size + line.length + 1 > maxChars && current.length) {
      chunks.push(current.join("\n"));
      if (chunks.length >= maxChunks) return chunks;
      // Carry trailing lines as overlap.
      const carry: string[] = [];
      let carried = 0;
      for (let i = current.length - 1; i >= 0; i--) {
        const l = current[i] as string;
        if (carried + l.length + 1 > overlap) break;
        carry.unshift(l);
        carried += l.length + 1;
      }
      current = carry;
      size = carried;
    }
    current.push(line);
    size += line.length + 1;
  }
  if (current.length) chunks.push(current.join("\n"));
  return chunks.slice(0, maxChunks);
}

// ---------------------------------------------------------------------------------------------------------------------
// Entity decoding + quote matching normalization
// ---------------------------------------------------------------------------------------------------------------------

const NAMED_ENTITIES: Record<string, string> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " ",
  ndash: "–",
  mdash: "—",
  lsquo: "‘",
  rsquo: "’",
  sbquo: "‚",
  ldquo: "“",
  rdquo: "”",
  bdquo: "„",
  hellip: "…",
  middot: "·",
  bull: "•",
  copy: "©",
  reg: "®",
  trade: "™",
  deg: "°",
  euro: "€",
  pound: "£",
  cent: "¢",
  times: "×",
  frac12: "½",
  aacute: "á",
  eacute: "é",
  iacute: "í",
  oacute: "ó",
  uacute: "ú",
  ntilde: "ñ",
  uuml: "ü",
  ouml: "ö",
  auml: "ä",
  ccedil: "ç",
  egrave: "è",
  agrave: "à",
  Aacute: "Á",
  Eacute: "É",
  Ntilde: "Ñ",
};

/** Decodes numeric and common named HTML entities. Unknown entities are left as-is. */
export function decodeEntities(text: string): string {
  return text.replace(/&(#x[0-9a-f]+|#\d+|[a-z][a-z0-9]*);/gi, (match, body: string) => {
    if (body[0] === "#") {
      const code = body[1] === "x" || body[1] === "X" ? Number.parseInt(body.slice(2), 16) : Number(body.slice(1));
      if (!Number.isFinite(code) || code <= 0 || code > 0x10ffff) return match;
      try {
        return String.fromCodePoint(code);
      } catch {
        return match;
      }
    }
    return NAMED_ENTITIES[body] ?? NAMED_ENTITIES[body.toLowerCase()] ?? match;
  });
}

/** Strips tags and decodes entities from a short HTML fragment (titles, descriptions). */
export function stripTags(fragment: string): string {
  return decodeEntities(
    fragment
      .replace(/<\s*br\s*\/?>/gi, "\n")
      .replace(/<\/(p|div|li|h\d)>/gi, "\n")
      .replace(/<[^>]*>/g, " "),
  );
}

/**
 * Canonical form for verbatim-quote matching: entities decoded, Unicode NFKC, case-folded, typographic quotes and
 * dashes unified, and ALL whitespace removed (so line breaks/indentation differences never matter).
 */
export function normalizeForMatch(text: string): string {
  return foldForMatch(text).replace(/[\s ​-‍﻿]+/g, "");
}

/** Like `normalizeForMatch` but whitespace runs become one space, so word boundaries survive ("nov 1" vs "nov 15"). */
export function normalizeForMatchSpaced(text: string): string {
  return foldForMatch(text)
    .replace(/[\s ​-‍﻿]+/g, " ")
    .trim();
}

function foldForMatch(text: string): string {
  return decodeEntities(text)
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[‘’‚‛′`´]/g, "'")
    .replace(/[“”„‟″]/g, '"')
    .replace(/[‐‑‒–—―−]/g, "-")
    .replace(/…/g, "...");
}

const MONTH =
  "(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)";
const DATE_PATTERNS = [
  new RegExp(`\\b${MONTH}\\.?\\s+\\d{1,2}(?:st|nd|rd|th)?\\b`, "gi"), // Nov 5, November 5th
  new RegExp(`\\b\\d{1,2}(?:st|nd|rd|th)?\\s+${MONTH}\\b`, "gi"), // 5 Nov
  /\b\d{1,2}\/\d{1,2}(?:\/\d{2,4})?\b/g, // 11/5, 11/05/2026
  /\b20\d{2}-\d{2}-\d{2}\b/g, // 2026-11-05
];

/**
 * Distinct date-like mentions in page text (e.g. "Nov 5", "11/05", "2026-11-05"). A cheap, deterministic signal used to
 * decide whether a page is worth an LLM call: event calendars mention many dates, menus and about pages mention few.
 */
export function countDateMentions(text: string): number {
  const seen = new Set<string>();
  for (const pattern of DATE_PATTERNS) {
    for (const match of text.matchAll(pattern)) seen.add(match[0].toLowerCase().replace(/\s+/g, " "));
  }
  return seen.size;
}

/** Minimum distinct date mentions before a page goes to the LLM fallback. */
export const MIN_DATE_MENTIONS_FOR_LLM = 3;

export function looksLikeEventListing(text: string, contentType?: string | null): boolean {
  return countDateMentions(cleanPageText(text, contentType)) >= MIN_DATE_MENTIONS_FOR_LLM;
}
