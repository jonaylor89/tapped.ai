/**
 * A Webflow CMS show list (`.w-dyn-item` cards with a `.date-sticker`), used by venue sites like The Camel's. Webflow keeps
 * hidden variants in the markup under `.w-condition-invisible`, so those never count. Dates are printed without a year
 * ("Nov" / "06"); validation picks the year.
 */
import * as cheerio from "cheerio";
import type { ExtractContext, ExtractedEvent, Extractor, Page } from "../types.js";
import { labelledTime, yearlessDate } from "./rhp.js";
import { applyTitleStatus, blankEvent, categoryHint, cleanText, dedupeEvents, pageBase, resolveUrl } from "./util.js";

const CARD = ".w-dyn-item:has(.date-sticker)";
const HIDDEN = ".w-condition-invisible";
const ANY_LABEL = /(?:)/;

export function extractWebflowShows(page: Page, _ctx: ExtractContext): ExtractedEvent[] {
  const $ = cheerio.load(page.text);
  const base = pageBase(page);
  const out: ExtractedEvent[] = [];
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
    /w-dyn-item/.test(page.text) && /date-sticker/.test(page.text) && /event-time-new/.test(page.text),
  extract: (page, ctx) => extractWebflowShows(page, ctx),
};
