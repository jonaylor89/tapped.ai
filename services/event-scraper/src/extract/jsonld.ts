import * as cheerio from "cheerio";
import type { ExtractContext, ExtractedEvent, Extractor, Page } from "../types.js";
import { collectEventObjects, eventFromSchema } from "./schemaorg.js";
import { dedupeEvents, looksLikeHtml } from "./util.js";

/**
 * Lenient JSON parse for hand-written / CMS-templated JSON-LD: strips HTML comments and CDATA, escapes raw control
 * characters inside strings, removes trailing commas and, as a last resort, wraps concatenated top-level objects in an
 * array. Returns undefined when the block is unrecoverable.
 */
export function parseJsonLenient(raw: string): unknown {
  const text = raw
    .replace(/^﻿/, "")
    .replace(/^\s*<!--/, "")
    .replace(/-->\s*$/, "")
    .replace(/^\s*\/\/\s*<!\[CDATA\[/, "")
    .replace(/\/\/\s*\]\]>\s*$/, "")
    .replace(/^\s*<!\[CDATA\[/, "")
    .replace(/\]\]>\s*$/, "")
    .trim();
  if (!text) return undefined;
  try {
    return JSON.parse(text);
  } catch {
    // fall through to repair
  }
  const repaired = repairJson(text);
  try {
    return JSON.parse(repaired);
  } catch {
    // fall through
  }
  try {
    return JSON.parse(`[${repaired.replace(/}\s*{/g, "},{")}]`);
  } catch {
    return undefined;
  }
}

function repairJson(text: string): string {
  let out = "";
  let inString = false;
  let escaped = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      if (escaped) {
        // Invalid escapes like "\'" become a plain character.
        out += /["\\/bfnrtu]/.test(ch) ? `\\${ch}` : ch;
        escaped = false;
      } else if (ch === "\\") {
        escaped = true;
      } else if (ch === '"') {
        inString = false;
        out += ch;
      } else if (ch === "\n" || ch === "\r" || ch === "\t") {
        out += ch === "\t" ? "\\t" : "\\n";
      } else {
        out += ch;
      }
      continue;
    }
    if (ch === '"') {
      inString = true;
      out += ch;
      continue;
    }
    if (ch === ",") {
      // Drop trailing commas before } or ].
      let j = i + 1;
      while (j < text.length && /\s/.test(text[j])) j++;
      if (text[j] === "}" || text[j] === "]") continue;
    }
    out += ch;
  }
  return out;
}

/** All parsed JSON-LD blocks in an HTML document (unparseable blocks are skipped). */
export function jsonLdBlocks(html: string): unknown[] {
  const $ = cheerio.load(html);
  const blocks: unknown[] = [];
  $('script[type="application/ld+json" i], script[type^="application/ld+json" i]').each((_, el) => {
    const parsed = parseJsonLenient($(el).text());
    if (parsed !== undefined) blocks.push(parsed);
  });
  return blocks;
}

export function extractJsonLd(page: Page, ctx: ExtractContext, extractor = "jsonld"): ExtractedEvent[] {
  const events: ExtractedEvent[] = [];
  for (const block of jsonLdBlocks(page.text)) {
    for (const obj of collectEventObjects(block)) {
      const ev = eventFromSchema(obj, page, ctx, extractor);
      if (ev) events.push(ev);
    }
  }
  return dedupeEvents(events);
}

export const jsonLdExtractor: Extractor = {
  name: "jsonld",
  canHandle: (page) => looksLikeHtml(page) && /application\/ld\+json/i.test(page.text),
  extract: (page, ctx) => extractJsonLd(page, ctx),
};
