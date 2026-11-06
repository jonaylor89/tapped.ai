/**
 * Webflow CMS show lists. Each site names its own classes, so each layout has its own reader:
 * - `.date-sticker` cards (The Camel): yearless dates ("Nov" / "06"), which validation completes. Webflow keeps hidden
 *   variants in the markup under `.w-condition-invisible`, so those never count.
 * - `.listed-show-card` cards (Révéler): full dates ("NOVEMBER 8, 2026").
 */
import * as cheerio from "cheerio";
import type { ExtractContext, ExtractedEvent, Extractor, Page } from "../types.js";
import { labelledTime, yearlessDate } from "./rhp.js";
import { applyTitleStatus, blankEvent, categoryHint, cleanText, dedupeEvents, pageBase, resolveUrl } from "./util.js";

const CARD = ".w-dyn-item:has(.date-sticker)";
const HIDDEN = ".w-condition-invisible";
const LISTED_CARD = ".w-dyn-item:has(.listed-show-card)";
const ANY_LABEL = /(?:)/;
const MONTHS = [
  "january",
  "february",
  "march",
  "april",
  "may",
  "june",
  "july",
  "august",
  "september",
  "october",
  "november",
  "december",
];

/** "NOVEMBER 8, 2026" -> "2026-11-08". */
function fullDate(text: string | null): string | null {
  const match = text?.match(/^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})$/);
  if (!match) return null;
  const month = MONTHS.indexOf((match[1] as string).toLowerCase());
  if (month < 0) return null;
  return `${match[3]}-${String(month + 1).padStart(2, "0")}-${(match[2] as string).padStart(2, "0")}`;
}

/** Each set's start: "6 + 8:30PM" -> ["18:00", "20:30"]. The meridiem can be printed only once, at the end. */
export function setTimes(text: string | null): string[] {
  const last = text?.match(/([ap])\.?m\b/gi)?.at(-1)?.[0];
  const times: string[] = [];
  for (const part of text?.split("+") ?? []) {
    const match = part.trim().match(/^(\d{1,2})(?::(\d{2}))?\s*(?:([ap])\.?m)?$/i);
    const meridiem = match?.[3] ?? last;
    if (!match || !meridiem) return [];
    const hour = Number(match[1]);
    if (hour < 1 || hour > 12) return [];
    const hour24 = (hour % 12) + (meridiem.toLowerCase() === "p" ? 12 : 0);
    times.push(`${String(hour24).padStart(2, "0")}:${match[2] ?? "00"}`);
  }
  return times;
}

function extractListedCards($: cheerio.CheerioAPI, base: string): ExtractedEvent[] {
  const out: ExtractedEvent[] = [];
  $(LISTED_CARD).each((_, element) => {
    const card = $(element);
    const ev = blankEvent("webflow_shows");
    ev.title = cleanText(card.find(".event-name-listed").first().text());
    const rawDate = cleanText(card.find(".full-date").first().text());
    const date = fullDate(rawDate);
    if (!ev.title || !date) return;
    const genre = cleanText(card.find(".genre-label-2").first().text());
    if (genre?.toUpperCase() === "CLOSED") return;
    const times = setTimes(cleanText(card.find(".time").first().text()));
    ev.rawDateText = rawDate;
    ev.eventUrl = resolveUrl(card.find("a").first().attr("href"), base);
    ev.imageUrl = resolveUrl(card.find("img").first().attr("src"), base);
    const support = cleanText(card.find(".support-small-card").first().text());
    if (support) ev.description = support;
    ev.category = categoryHint([], genre ? [genre] : [], ev.title);
    applyTitleStatus(ev);
    const id = ev.eventUrl ? `webflow:${new URL(ev.eventUrl).pathname}` : null;
    // Two sets on one night are separately ticketed shows, so each is its own event.
    for (const time of times.length ? times : [null]) {
      out.push({
        ...ev,
        start: time ? `${date}T${time}` : date,
        sourceEventId: id && times.length > 1 ? `${id}#${time}` : id,
      });
    }
  });
  return out;
}

export function extractWebflowShows(page: Page, _ctx: ExtractContext): ExtractedEvent[] {
  const $ = cheerio.load(page.text);
  const base = pageBase(page);
  const out = extractListedCards($, base);
  $(CARD).each((_, element) => {
    const card = $(element);
    const ev = blankEvent("webflow_shows");
    ev.title = cleanText(card.find("h3").first().text());
    const multiDay = card.find(`.date-sticker-multi-day:not(${HIDDEN})`).first();
    const sticker = card.find(`.date-sticker:not(${HIDDEN})`).first();
    const rawDate = multiDay.length
      ? cleanText(multiDay.find(".event-month-multi").first().text())
      : cleanText(`${sticker.find(".event-month").first().text()} ${sticker.find(".event-day").first().text()}`);
    const date = yearlessDate(rawDate);
    if (!ev.title || !date) return;
    const show = labelledTime(cleanText(sticker.find(".event-time-new").first().text()) ?? "", ANY_LABEL);
    ev.rawDateText = rawDate;
    ev.start = show ? `${date}T${show}` : date;
    ev.doors = labelledTime(cleanText(card.find(".div-block-9").first().text()) ?? "", /doors?/);
    ev.eventUrl = resolveUrl(card.find("a").first().attr("href"), base);
    ev.imageUrl = resolveUrl(card.find(".show-image-wrapper img").first().attr("src"), base);
    ev.category = categoryHint([], [], ev.title);
    const tag = decodeURIComponent(card.find(`img.event-tag:not(${HIDDEN})`).first().attr("src") ?? "").toLowerCase();
    if (tag.includes("cancel")) ev.status = "canceled";
    else if (tag.includes("postpone")) ev.status = "postponed";
    else if (tag.includes("sold out")) ev.status = "sold_out";
    applyTitleStatus(ev);
    ev.sourceEventId = ev.eventUrl ? `webflow:${new URL(ev.eventUrl).pathname}` : null;
    out.push(ev);
  });
  return dedupeEvents(out);
}

export const webflowShowsExtractor: Extractor = {
  name: "webflow_shows",
  canHandle: (page) =>
    /w-dyn-item/.test(page.text) &&
    (/listed-show-card/.test(page.text) || (/date-sticker/.test(page.text) && /event-time-new/.test(page.text))),
  extract: (page, ctx) => extractWebflowShows(page, ctx),
};
