/**
 * The RHP events plugin's WordPress list (`.rhpSingleEvent` cards), used by venue groups whose one calendar covers many
 * rooms. Each card links to its venue (`/venue/<key>/`), kept as `venueKey` so a multi-venue source can route the event.
 * Dates are printed without a year ("Nov 08"); validation picks the year.
 */
import * as cheerio from "cheerio";
import type { ExtractContext, ExtractedEvent, Extractor, Page } from "../types.js";
import {
  applyTitleStatus,
  blankEvent,
  categoryHint,
  cleanText,
  dedupeEvents,
  pageBase,
  parsePriceText,
  resolveUrl,
} from "./util.js";

const CARD = ".rhpSingleEvent";
const MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];

/** "Nov 08" -> "--11-08". */
export function yearlessDate(text: string | null): string | null {
  const match = text?.match(/\b([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2})\b/);
  if (!match) return null;
  const month = MONTHS.indexOf((match[1] as string).toLowerCase());
  const day = Number(match[2]);
  if (month < 0 || day < 1 || day > 31) return null;
  return `--${String(month + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

/** The time after a label: ("Door: 7:30 pm", "door") -> "19:30". */
export function labelledTime(text: string, label: RegExp): string | null {
  const match = text.match(new RegExp(`${label.source}\\s*:?\\s*(\\d{1,2})(?::(\\d{2}))?\\s*([ap])\\.?m`, "i"));
  if (!match) return null;
  const hour = Number(match[1]);
  if (hour < 1 || hour > 12) return null;
  const isPm = (match[3] as string).toLowerCase() === "p";
  const hour24 = (hour % 12) + (isPm ? 12 : 0);
  return `${String(hour24).padStart(2, "0")}:${match[2] ?? "00"}`;
}

/** Last path segment of a `/venue/<key>/` link. */
function venueKeyOf(href: string | undefined, base: string): string | null {
  const url = resolveUrl(href, base);
  if (!url) return null;
  return new URL(url).pathname.match(/\/venue\/([^/]+)\/?$/)?.[1]?.toLowerCase() ?? null;
}

export function extractRhp(page: Page, _ctx: ExtractContext): ExtractedEvent[] {
  const $ = cheerio.load(page.text);
  const base = pageBase(page);
  const out: ExtractedEvent[] = [];
  $(CARD).each((_, element) => {
    const card = $(element);
    const ev = blankEvent("rhp");
    ev.title = cleanText(card.find(".rhp-event__title--list").first().text());
    const date = yearlessDate(cleanText(card.find(".singleEventDate").first().text()));
    if (!ev.title || !date) return;
    const times = cleanText(card.find(".rhp-event__time-text--list").text()) ?? "";
    const show = labelledTime(times, /show/);
    ev.rawDateText = cleanText(card.find(".singleEventDate").first().text());
    ev.start = show ? `${date}T${show}` : date;
    ev.doors = labelledTime(times, /doors?/);
    ev.eventUrl = resolveUrl(card.find("a#eventTitle, a.url").first().attr("href"), base);
    ev.imageUrl = resolveUrl(card.find("img.eventListImage").first().attr("src"), base);
    ev.ticketUrl = resolveUrl(card.find(".rhp-event-cta a").first().attr("href"), base);
    ev.venueKey = venueKeyOf(card.find("a.venueLink").first().attr("href"), base);
    ev.category = categoryHint([], [], ev.title);
    const priceText = cleanText(card.find(".rhp-event__cost-text--list, .eventCost").first().text());
    if (priceText) {
      const parsed = parsePriceText(priceText);
      ev.prices = parsed.prices;
      ev.isFree = parsed.isFree;
    }
    const cta = cleanText(card.find(".rhp-event-cta").first().text())?.toLowerCase() ?? "";
    if (/cancel/.test(cta)) ev.status = "canceled";
    else if (/postpone/.test(cta)) ev.status = "postponed";
    else if (/sold\s*out/.test(cta)) ev.status = "sold_out";
    applyTitleStatus(ev);
    ev.sourceEventId = ev.eventUrl ? `rhp:${new URL(ev.eventUrl).pathname}` : null;
    out.push(ev);
  });
  return dedupeEvents(out);
}

export const rhpExtractor: Extractor = {
  name: "rhp",
  canHandle: (page) => /rhpSingleEvent/.test(page.text),
  extract: (page, ctx) => extractRhp(page, ctx),
};
