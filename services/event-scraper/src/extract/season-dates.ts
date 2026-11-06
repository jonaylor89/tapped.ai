/**
 * A theater season list: `.show-date` blocks each followed by a `.show-info` block (Richmond Triangle Players). A run is
 * one event from its first to its last date, because the page gives no individual performances.
 */
import * as cheerio from "cheerio";
import type { ExtractContext, ExtractedEvent, Extractor, Page } from "../types.js";
import { applyTitleStatus, blankEvent, categoryHint, cleanText, dedupeEvents } from "./util.js";

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
const MONTH = `(${MONTHS.join("|")})`;
const DAY = "(\\d{1,2})(?:st|nd|rd|th)?";
const YEAR = "[,.]?\\s*(\\d{4})";
const SEPARATOR = "\\s*(?:-|–|—|&|and)\\s*";
const RUN = new RegExp(`^${MONTH}\\s+${DAY}${SEPARATOR}(?:${MONTH}\\s+)?${DAY}${YEAR}$`, "i");
const SINGLE = new RegExp(`^${MONTH}\\s+${DAY}${YEAR}$`, "i");

function iso(year: number, month: number, day: string): string {
  return `${year}-${String(month + 1).padStart(2, "0")}-${day.padStart(2, "0")}`;
}

/** "September 16th – October 10th, 2026" -> first and last date. A run across New Year starts the year before. */
export function parseRun(text: string): { start: string; end: string | null } | null {
  const single = text.match(SINGLE);
  if (single) {
    return {
      start: iso(Number(single[3]), MONTHS.indexOf((single[1] as string).toLowerCase()), single[2] as string),
      end: null,
    };
  }
  const run = text.match(RUN);
  if (!run) return null;
  const startMonth = MONTHS.indexOf((run[1] as string).toLowerCase());
  const endMonth = run[3] ? MONTHS.indexOf(run[3].toLowerCase()) : startMonth;
  const endYear = Number(run[5]);
  const startYear = startMonth > endMonth ? endYear - 1 : endYear;
  return { start: iso(startYear, startMonth, run[2] as string), end: iso(endYear, endMonth, run[4] as string) };
}

export function extractSeasonDates(page: Page, _ctx: ExtractContext): ExtractedEvent[] {
  const $ = cheerio.load(page.text);
  const out: ExtractedEvent[] = [];
  $(".show-date").each((_, element) => {
    const block = $(element);
    const rawDate = cleanText(block.text());
    const dates = rawDate ? parseRun(rawDate) : null;
    const info = block.next(".show-info");
    const heading = cleanText(info.find("h4").first().text());
    const line = cleanText(info.find("p").first().text());
    const title = heading ?? line;
    if (!dates || !title) return;
    const ev = blankEvent("season_dates");
    ev.title = title;
    ev.rawDateText = rawDate;
    ev.start = dates.start;
    ev.end = dates.end;
    ev.description = heading ? line : null;
    ev.category = block.hasClass("main-stage") ? "theater" : categoryHint([], [], title);
    applyTitleStatus(ev);
    ev.sourceEventId = `season:${dates.start}:${title.toLowerCase()}`;
    out.push(ev);
  });
  return dedupeEvents(out);
}

export const seasonDatesExtractor: Extractor = {
  name: "season_dates",
  canHandle: (page) => /\bshow-date\b/.test(page.text) && /\bshow-info\b/.test(page.text),
  extract: (page, ctx) => extractSeasonDates(page, ctx),
};
