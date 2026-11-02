import * as cheerio from "cheerio";
import type { ExtractContext, ExtractedEvent, Extractor, Page } from "../types.js";
import { collectEventObjects, eventFromSchema } from "./schemaorg.js";
import { dedupeEvents, looksLikeHtml } from "./util.js";

type CheerioAPI = cheerio.CheerioAPI;
// domhandler is not a direct dependency; derive its node types from cheerio's own signatures (in a form that
// declaration emit can name, so `pnpm build` works).
type AnyNode = Parameters<CheerioAPI["contains"]>[0];
type Element = Extract<AnyNode, { tagName: string }>;

const URL_PROP_TAGS = new Set(["a", "area", "link"]);
const SRC_PROP_TAGS = new Set(["img", "audio", "video", "source", "iframe", "embed", "track"]);

function isElement(node: AnyNode): node is Element {
  return node.type === "tag" || node.type === "script" || node.type === "style";
}

function propValue($: CheerioAPI, el: Element): string {
  const tag = el.tagName.toLowerCase();
  const attr = (name: string) => el.attribs[name];
  if (attr("content") !== undefined) return attr("content");
  if (tag === "meta") return attr("content") ?? "";
  if (URL_PROP_TAGS.has(tag)) return attr("href") ?? "";
  if (SRC_PROP_TAGS.has(tag)) return attr("src") ?? "";
  if (tag === "object") return attr("data") ?? "";
  if (tag === "time") return attr("datetime") ?? $(el).text();
  if (tag === "data" || tag === "meter") return attr("value") ?? $(el).text();
  return $(el).text();
}

/**
 * Converts one microdata item (an element with `itemscope`) into a JSON-LD-like object: `@type` from itemtype, each
 * itemprop as a key (arrays when repeated), nested itemscopes as nested objects.
 */
export function microdataItem($: CheerioAPI, root: Element, depth = 0): Record<string, unknown> {
  const obj: Record<string, unknown> = {};
  const itemtype = root.attribs.itemtype;
  if (itemtype) obj["@type"] = itemtype.trim().split(/\s+/);
  if (root.attribs.itemid) obj["@id"] = root.attribs.itemid;
  const add = (name: string, value: unknown) => {
    const prev = obj[name];
    if (prev === undefined) obj[name] = value;
    else if (Array.isArray(prev)) prev.push(value);
    else obj[name] = [prev, value];
  };
  const walk = (node: Element) => {
    for (const child of node.children) {
      if (!isElement(child)) continue;
      const props = child.attribs.itemprop?.trim().split(/\s+/).filter(Boolean) ?? [];
      const scoped = child.attribs.itemscope !== undefined;
      if (props.length) {
        const value = scoped && depth < 8 ? microdataItem($, child, depth + 1) : propValue($, child);
        for (const p of props) add(p, value);
      }
      if (!scoped) walk(child);
    }
  };
  walk(root);
  return obj;
}

/** Top-level microdata items (itemscope elements that are not a property of another item). */
export function microdataItems(html: string): Record<string, unknown>[] {
  const $ = cheerio.load(html);
  const items: Record<string, unknown>[] = [];
  $("[itemscope]").each((_, el) => {
    if (el.attribs.itemprop !== undefined) {
      // A property of an enclosing item; it is collected through its parent, unless orphaned.
      if ($(el).parents("[itemscope]").length) return;
    }
    items.push(microdataItem($, el));
  });
  return items;
}

export function extractMicrodata(page: Page, ctx: ExtractContext, extractor = "microdata"): ExtractedEvent[] {
  const events: ExtractedEvent[] = [];
  for (const obj of collectEventObjects(microdataItems(page.text))) {
    const ev = eventFromSchema(obj, page, ctx, extractor);
    if (ev) events.push(ev);
  }
  return dedupeEvents(events);
}

export const microdataExtractor: Extractor = {
  name: "microdata",
  canHandle: (page) => looksLikeHtml(page) && /itemtype\s*=\s*["']?https?:\/\/(www\.)?schema\.org\//i.test(page.text),
  extract: (page, ctx) => extractMicrodata(page, ctx),
};
