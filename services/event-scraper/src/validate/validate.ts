import { isTicketingUrl } from "../denylist.js";
import { decodeEntities, stripTags } from "../llm/text.js";
import { computeIdentityKey, normalizeTitle } from "../reconcile/identity.js";
import type {
  EventCategory,
  EventStatus,
  ExtractedEvent,
  KeptCategory,
  Source,
  ValidatedEvent,
  ValidationOutcome,
  Venue,
} from "../types.js";
import { parseHttpUrl } from "../url.js";
import { classifyEvent } from "./classify.js";
import { normalizePrices, parsePriceText, SOLD_OUT_RE } from "./price.js";
import {
  buildQuoteIndex,
  nearestDateIs,
  type QuoteIndex,
  quoteContains,
  quoteMentionsDate,
  verifyQuotes,
} from "./quotes.js";
import {
  addDays,
  addMonths,
  dateOf,
  formatDate,
  instantToLocal,
  isValidCalendarDate,
  isValidTimeZone,
  localDate,
  localToUtc,
  minutesOf,
  type ParsedLocal,
  parseInstant,
  parseLocal,
  timeOf,
  weekdayOf,
} from "./time.js";

/**
 * Deterministic validation: ExtractedEvent -> ValidatedEvent (or a rejection with reasons).
 *
 * Rules:
 * - title and start are required; titles lose "SOLD OUT:"/"CANCELED -" prefixes, which become the status.
 * - timezone: the event's own IANA zone if valid, else the source/venue zone from the context.
 * - yearless dates get the earliest year whose date is not more than `pastGraceDays` in the past (a weekday in the
 *   raw date text breaks ties); every event must start within [today - pastGraceDays, today + maxMonthsAhead].
 * - local -> UTC is DST-safe via Intl (see time.ts); date-only events keep `startUtc = null`.
 * - end times earlier than the start roll over to the next day (overnight shows); doors after the show are swapped.
 * - prices become integer cents; "free"/"sold out" are detected in prices, titles and descriptions.
 * - LLM events (or any extractor listed in `evidenceRequiredFor`) must carry quotes that all appear in the page, the
 *   title must appear verbatim, and at least one verified quote must name the title (or a performer) together with
 *   the extracted month/day (word-boundary match: "Nov 1" never supports Nov 15). Their raw date text is used for
 *   weekday hints only when it appears in the page.
 * - categories: music/comedy/open_mic/theater/dance are kept; "other" and non-events are rejected.
 */

export interface ValidateContext {
  source: Pick<Source, "id" | "venueId" | "url" | "timezone">;
  venue?: Pick<Venue, "id" | "name"> | null;
  /** IANA zone used when the event has none. */
  timezone: string;
  /** Fetch time; "today" for year inference and the upcoming window. */
  now: Date;
  /** Page text (HTML or plain) for evidence verification. Required when any event needs evidence. */
  pageText?: string | null;
  pageContentType?: string | null;
  /** URL the page was fetched from (for resolving relative links). Defaults to the source URL. */
  pageUrl?: string | null;
  /** Prebuilt quote index (shared across events of one page). */
  quoteIndex?: QuoteIndex | null;
  /**
   * When written start times disagree with their UTC instants: true trusts the instants (the written times are UTC
   * wall times), false trusts the written times (the site's offset is wrong). validateEvents decides once per page.
   */
  trustInstants?: boolean;
  /** Default 1: events that started up to this many days ago are still accepted. */
  pastGraceDays?: number;
  /** Default 13. */
  maxMonthsAhead?: number;
  /** Extractor names whose evidence must be verified. Default: names starting with "llm". */
  evidenceRequiredFor?: (extractor: string) => boolean;
  /** Category when nothing signals one. Default "music". */
  defaultCategory?: EventCategory;
  /** Currency assumed for "$" etc. Default "USD". */
  defaultCurrency?: string;
}

const FREE_PHRASE = /\b(free (show|admission|entry|event|concert)|no cover|admission is free)\b/i;

/** Yearless dates inferred further out than this need a matching printed weekday. */
const YEARLESS_MAX_MONTHS = 9;

const DEFAULT_EVIDENCE_REQUIRED = (extractor: string): boolean => extractor.toLowerCase().startsWith("llm");

const STATUS_PREFIX: Array<[RegExp, EventStatus]> = [
  [/^\s*\(?\s*sold[\s-]*out\s*\)?\s*[:!\-–—|]*\s*/i, "sold_out"],
  [/^\s*\(?\s*cancel+ed\s*\)?\s*[:!\-–—|]*\s*/i, "canceled"],
  [/^\s*\(?\s*postponed\s*\)?\s*[:!\-–—|]*\s*/i, "postponed"],
  [/^\s*\(?\s*(rescheduled|new date)\s*\)?\s*[:!\-–—|]*\s*/i, "rescheduled"],
];
const STATUS_SUFFIX: Array<[RegExp, EventStatus]> = [
  [/\s*[-–—|:]?\s*[([]?\s*sold[\s-]*out\s*[)\]]?\s*!*$/i, "sold_out"],
  [/\s*[-–—|:]?\s*[([]?\s*cancel+ed\s*[)\]]?\s*!*$/i, "canceled"],
  [/\s*[-–—|:]?\s*[([]?\s*postponed\s*[)\]]?\s*!*$/i, "postponed"],
];

function cleanText(value: string | null | undefined, max: number): string | null {
  if (!value) return null;
  const text = stripTags(String(value))
    .replace(/[ \t ]+/g, " ")
    .replace(/\s*\n\s*/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  if (!text) return null;
  return text.length > max ? `${text.slice(0, max - 1).trimEnd()}…` : text;
}

function cleanTitle(raw: string | null): { title: string | null; status: EventStatus | null } {
  let title = cleanText(raw, 300)?.replace(/\s+/g, " ") ?? null;
  let status: EventStatus | null = null;
  if (!title) return { title, status };
  for (const [re, s] of STATUS_PREFIX) {
    if (re.test(title)) {
      const stripped = title.replace(re, "").trim();
      if (stripped) {
        title = stripped;
        status ??= s;
      }
    }
  }
  for (const [re, s] of STATUS_SUFFIX) {
    if (re.test(title)) {
      const stripped = title.replace(re, "").trim();
      if (stripped) {
        title = stripped;
        status ??= s;
      }
    }
  }
  return { title, status };
}

function absoluteUrl(value: string | null | undefined, base: string): string | null {
  if (!value || typeof value !== "string") return null;
  const raw = decodeEntities(value.trim());
  if (!raw || /^(javascript|mailto|tel|data):/i.test(raw)) return null;
  try {
    const url = new URL(raw, base);
    return parseHttpUrl(url)?.href ?? null;
  } catch {
    return null;
  }
}

const WEEKDAYS: Array<[RegExp, number]> = [
  [/\bsun(day)?\b/i, 0],
  [/\bmon(day)?\b/i, 1],
  [/\btue(s|sday)?\b/i, 2],
  [/\bwed(nesday)?\b/i, 3],
  [/\bthu(r|rs|rsday)?\b/i, 4],
  [/\bfri(day)?\b/i, 5],
  [/\bsat(urday)?\b/i, 6],
];

function weekdayHint(text: string | null | undefined): number | null {
  if (!text) return null;
  const hits = WEEKDAYS.filter(([re]) => re.test(text));
  return hits.length === 1 ? (hits[0]?.[1] ?? null) : null;
}

/**
 * Picks the year for a yearless month/day relative to `today` ("YYYY-MM-DD" in the venue zone): the earliest of
 * (year-1, year, year+1) that is valid and not before `today - graceDays`. If `weekday` is given and one candidate
 * within the window matches it, that candidate wins.
 */
export function inferYear(
  month: number,
  day: number,
  today: string,
  options: { graceDays?: number; weekday?: number | null; maxMonthsAhead?: number } = {},
): number | null {
  const year = Number(today.slice(0, 4));
  const floor = addDays(today, -(options.graceDays ?? 1));
  const ceiling = addMonths(today, options.maxMonthsAhead ?? 13);
  const candidates = [year - 1, year, year + 1]
    .filter((y) => isValidCalendarDate(y, month, day))
    .map((y) => ({ y, date: formatDate(y, month, day) }))
    .filter((c) => c.date >= floor);
  if (!candidates.length) return null;
  if (options.weekday !== null && options.weekday !== undefined) {
    const matching = candidates.filter((c) => c.date <= ceiling && weekdayOf(c.date) === options.weekday);
    if (matching.length) return (matching[0] as { y: number }).y;
  }
  return (candidates[0] as { y: number }).y;
}

function withTime(date: string, time: string): string {
  return `${date}T${time}`;
}

function hhmm(parsed: { hour: number; minute: number }): string {
  return `${String(parsed.hour).padStart(2, "0")}:${String(parsed.minute).padStart(2, "0")}`;
}

/** Resolves an end/doors value relative to the start. Returns local "YYYY-MM-DD[THH:mm]" or null. */
function resolveRelative(
  parsed: ParsedLocal | null,
  startDate: string,
  startYear: number,
): { local: string; kind: "time" | "datetime" | "date" } | null {
  if (!parsed) return null;
  switch (parsed.kind) {
    case "time":
      return { local: withTime(startDate, hhmm(parsed)), kind: "time" };
    case "datetime":
      return {
        local: withTime(formatDate(parsed.parts.year, parsed.parts.month, parsed.parts.day), hhmm(parsed.parts)),
        kind: "datetime",
      };
    case "date":
      return { local: formatDate(parsed.parts.year, parsed.parts.month, parsed.parts.day), kind: "date" };
    case "yearless": {
      let date = formatDate(startYear, parsed.month, parsed.day);
      if (!isValidCalendarDate(startYear, parsed.month, parsed.day)) return null;
      if (date < startDate) date = formatDate(startYear + 1, parsed.month, parsed.day);
      if (parsed.hour === null || parsed.minute === null) return { local: date, kind: "date" };
      return { local: withTime(date, hhmm({ hour: parsed.hour, minute: parsed.minute })), kind: "datetime" };
    }
  }
}

function minutesBetween(aLocal: string, bLocal: string): number {
  const a = Date.parse(`${aLocal.length === 10 ? `${aLocal}T00:00` : aLocal}:00Z`);
  const b = Date.parse(`${bLocal.length === 10 ? `${bLocal}T00:00` : bLocal}:00Z`);
  return Math.round((b - a) / 60_000);
}

export function validateEvent(extracted: ExtractedEvent, ctx: ValidateContext): ValidationOutcome {
  const reasons: string[] = [];
  const warnings: string[] = [];
  const reject = (...why: string[]): ValidationOutcome => ({ ok: false, reasons: [...reasons, ...why], extracted });

  // --- Title & status -------------------------------------------------------------------------------------------
  const { title, status: titleStatus } = cleanTitle(extracted.title);
  if (!title || title.length < 2 || !/[\p{L}\p{N}]/u.test(title)) return reject("missing_title");

  // --- Evidence setup (LLM events): unverified raw date text must not drive year/weekday inference --------------
  const needsEvidence = (ctx.evidenceRequiredFor ?? DEFAULT_EVIDENCE_REQUIRED)(extracted.extractor);
  const quoteIndex = needsEvidence
    ? (ctx.quoteIndex ?? (ctx.pageText ? buildQuoteIndex(ctx.pageText, ctx.pageContentType) : null))
    : null;
  let rawDateText = extracted.rawDateText ?? null;
  if (needsEvidence && rawDateText && !quoteIndex?.has(rawDateText)) {
    warnings.push("raw_date_text_not_found");
    rawDateText = null;
  }

  // --- Timezone -------------------------------------------------------------------------------------------------
  let timezone = ctx.timezone;
  if (extracted.timezone && extracted.timezone !== ctx.timezone) {
    if (isValidTimeZone(extracted.timezone)) timezone = extracted.timezone;
    else warnings.push("invalid_event_timezone");
  }
  if (!isValidTimeZone(timezone)) return reject("invalid_timezone");

  const today = localDate(ctx.now, timezone);
  const graceDays = ctx.pastGraceDays ?? 1;
  const maxMonths = ctx.maxMonthsAhead ?? 13;

  // --- Start ----------------------------------------------------------------------------------------------------
  let startLocal: string | null = null;
  let startUtc: string | null = null;
  /** Set when the written times are UTC wall times: written + shift = the real instant (applied to the end too). */
  let instantShiftMs: number | null = null;
  const instantMs = parseInstant(extracted.startInstant);
  if (instantMs !== null) {
    startLocal = instantToLocal(instantMs, timezone);
    startUtc = new Date(instantMs).toISOString();
    // A local start that disagrees with the instant usually means the site's offset is wrong; trust the local value.
    const parsedLocal = parseLocal(extracted.start);
    if (parsedLocal?.kind === "datetime") {
      const local = withTime(
        formatDate(parsedLocal.parts.year, parsedLocal.parts.month, parsedLocal.parts.day),
        hhmm(parsedLocal.parts),
      );
      if (local !== startLocal) {
        warnings.push("instant_local_mismatch");
        // Usually the site wrote venue wall time with a wrong offset (WordPress "+00:00"), so trust the written time,
        // unless the page as a whole shows the written times are UTC (see pageTrustsInstants).
        if (ctx.trustInstants === true) {
          warnings.push("instant_trusted");
          instantShiftMs = instantMs - wallAsUtcMs(local);
        } else {
          startLocal = local;
          startUtc = localToUtc(local, timezone);
        }
      }
    }
  } else if (extracted.startInstant) {
    warnings.push("invalid_start_instant");
  }

  if (!startLocal) {
    const parsed = parseLocal(extracted.start);
    if (!parsed) return reject(extracted.start ? "invalid_start" : "missing_start");
    if (parsed.kind === "time") return reject("start_without_date");
    if (parsed.kind === "yearless") {
      const year = inferYear(parsed.month, parsed.day, today, {
        graceDays,
        maxMonthsAhead: maxMonths,
        weekday: weekdayHint(rawDateText),
      });
      if (year === null) return reject("year_inference_failed");
      warnings.push("year_inferred");
      const date = formatDate(year, parsed.month, parsed.day);
      // A yearless date that only fits ~a year out is far more likely a stale past listing ("Oct 30" seen on
      // Nov 2) than a show 12 months away; accept it only when a printed weekday confirms the year.
      const weekday = weekdayHint(rawDateText);
      if (date > addMonths(today, YEARLESS_MAX_MONTHS) && (weekday === null || weekdayOf(date) !== weekday)) {
        return reject("year_ambiguous");
      }
      startLocal =
        parsed.hour !== null && parsed.minute !== null
          ? withTime(date, hhmm({ hour: parsed.hour, minute: parsed.minute }))
          : date;
    } else if (parsed.kind === "date") {
      startLocal = formatDate(parsed.parts.year, parsed.parts.month, parsed.parts.day);
    } else {
      startLocal = withTime(formatDate(parsed.parts.year, parsed.parts.month, parsed.parts.day), hhmm(parsed.parts));
    }
    startUtc = startLocal.length > 10 ? localToUtc(startLocal, timezone) : null;
    if (startUtc && instantToLocal(startUtc, timezone) !== startLocal) warnings.push("start_in_dst_gap");
  }

  const startDate = dateOf(startLocal);
  if (startDate < addDays(today, -graceDays)) return reject("past_event");
  if (startDate > addMonths(today, maxMonths)) return reject("too_far_future");
  const hint = weekdayHint(rawDateText);
  if (hint !== null && !warnings.includes("year_inferred") && weekdayOf(startDate) !== hint)
    warnings.push("weekday_mismatch");

  // --- End & doors ----------------------------------------------------------------------------------------------
  const startYear = Number(startDate.slice(0, 4));
  const startTime = timeOf(startLocal);
  let doorsLocal: string | null = null;
  const doors = resolveRelative(parseLocal(extracted.doors), startDate, startYear);
  if (extracted.doors && !doors) warnings.push("invalid_doors");
  if (doors && doors.local.length > 10) {
    doorsLocal = doors.local;
    if (startTime) {
      const delta = minutesBetween(doorsLocal, startLocal);
      if (delta < 0 && doors.kind === "time") {
        if (-delta >= 12 * 60) {
          // Doors 23:30, show 00:30: the doors are the evening before.
          doorsLocal = withTime(addDays(startDate, -1), timeOf(doorsLocal) as string);
        } else {
          // Doors after the show on the same evening: the two were swapped by the extractor.
          const showTime = timeOf(doorsLocal) as string;
          doorsLocal = withTime(startDate, startTime);
          startLocal = withTime(startDate, showTime);
          startUtc = localToUtc(startLocal, timezone);
          warnings.push("doors_show_swapped");
        }
      } else if (delta < 0 || delta > 6 * 60) {
        warnings.push("doors_implausible");
        doorsLocal = null;
      }
    } else if (dateOf(doorsLocal) !== startDate) {
      warnings.push("doors_other_day");
      doorsLocal = null;
    }
  }
  if (doorsLocal && startTime && minutesOf(timeOf(doorsLocal) as string) === minutesOf(timeOf(startLocal) as string)) {
    if (dateOf(doorsLocal) === dateOf(startLocal)) doorsLocal = null;
  }

  let endLocal: string | null = null;
  const end = resolveRelative(parseLocal(extracted.end), startDate, startYear);
  if (extracted.end && !end) warnings.push("invalid_end");
  if (end) {
    endLocal = end.local;
    if (instantShiftMs !== null && endLocal.length > 10)
      endLocal = instantToLocal(wallAsUtcMs(endLocal) + instantShiftMs, timezone);
    if (startTime && endLocal.length > 10) {
      let delta = minutesBetween(startLocal, endLocal);
      if (delta <= 0 && dateOf(endLocal) === startDate) {
        // "9pm - 2am": the end is after midnight.
        endLocal = withTime(addDays(startDate, 1), timeOf(endLocal) as string);
        delta = minutesBetween(startLocal, endLocal);
        warnings.push("end_rolled_over");
      }
      if (delta <= 0) {
        warnings.push("end_before_start");
        endLocal = null;
      }
    } else if (dateOf(endLocal) < startDate) {
      warnings.push("end_before_start");
      endLocal = null;
    }
    if (endLocal && minutesBetween(startDate, dateOf(endLocal)) > 31 * 24 * 60) {
      warnings.push("end_too_far");
      endLocal = null;
    }
    if (endLocal && endLocal === startLocal) endLocal = null;
  }
  const endUtc = endLocal && endLocal.length > 10 ? localToUtc(endLocal, timezone) : null;

  // --- Text fields ----------------------------------------------------------------------------------------------
  const description = cleanText(extracted.description, 5000);
  const pageUrl = ctx.pageUrl ?? ctx.source.url;
  let eventUrl = absoluteUrl(extracted.eventUrl, pageUrl);
  let ticketUrl = absoluteUrl(extracted.ticketUrl, pageUrl);
  if (eventUrl && isTicketingUrl(eventUrl)) {
    // Ticketing links are recorded, never treated as the event's page (and never fetched).
    ticketUrl ??= eventUrl;
    eventUrl = null;
  }
  const imageUrl = absoluteUrl(extracted.imageUrl, pageUrl);

  const venueName = ctx.venue?.name ? normalizeTitle(ctx.venue.name) : null;
  const performers: string[] = [];
  const seenPerformers = new Set<string>();
  for (const raw of extracted.performers ?? []) {
    const name = cleanText(raw, 200)?.replace(/\s+/g, " ");
    if (!name) continue;
    const key = normalizeTitle(name);
    if (!key || seenPerformers.has(key) || key === venueName) continue;
    seenPerformers.add(key);
    performers.push(name);
    if (performers.length >= 40) break;
  }

  // --- Prices, free, status -------------------------------------------------------------------------------------
  const currency = ctx.defaultCurrency ?? "USD";
  let prices = normalizePrices(extracted.prices ?? [], currency);
  let isFree = extracted.isFree ?? null;
  let soldOut = false;
  if (!prices.length) {
    const parsed = parsePriceText(
      extracted.prices
        ?.map((p) => p.text)
        .filter(Boolean)
        .join(" / ") || null,
      currency,
    );
    prices = parsed.prices;
    if (isFree === null) isFree = parsed.isFree;
    soldOut ||= parsed.soldOut;
  }
  if (isFree === null && prices.length) {
    const paid = prices.some((p) => (p.maxCents ?? p.minCents ?? 0) > 0);
    isFree = !paid;
  }
  if (isFree === null && FREE_PHRASE.test(`${title}\n${description ?? ""}`)) isFree = true;
  if (isFree === true && prices.some((p) => (p.minCents ?? 0) > 0)) {
    warnings.push("free_with_price");
    isFree = false;
  }
  soldOut ||= SOLD_OUT_RE.test(title);

  let status: EventStatus = extracted.status ?? titleStatus ?? "scheduled";
  if (status === "scheduled" && titleStatus) status = titleStatus;
  if (status === "scheduled" && soldOut) status = "sold_out";

  // --- Evidence -------------------------------------------------------------------------------------------------
  const evidence = (extracted.evidence ?? []).filter((q): q is string => typeof q === "string" && q.trim().length > 0);
  if (needsEvidence) {
    if (!evidence.length) return reject("evidence_missing");
    if (!quoteIndex) return reject("evidence_unverifiable");
    const check = verifyQuotes(evidence, quoteIndex);
    if (check.missing.length) return reject(`evidence_not_found:${check.missing.length}`);
    if (!check.verified.length) return reject("evidence_too_short");
    if (!quoteIndex.has(title)) return reject("title_not_verbatim");
    // One verified quote must tie the event (title or a performer) to its date. Late shows listed under the
    // previous evening's date ("Fri Nov 6 ... 12:30am") may cite that date.
    const [, month, day] = startDate.split("-").map(Number) as [number, number, number];
    const shownTime = timeOf(startLocal);
    const early = shownTime !== null && minutesOf(shownTime) < 6 * 60;
    const [, pm, pd] = addDays(startDate, -1).split("-").map(Number) as [number, number, number];
    const names = [title, ...performers];
    const mentionsDate = (quote: string) =>
      quoteMentionsDate(quote, month, day) || (early && quoteMentionsDate(quote, pm, pd));
    const namesEvent = (quote: string) => names.some((name) => quoteContains(quote, name));
    // Either one quote has both, or the date printed nearest to a verified title quote on the page is the event's date
    // (title and date in separate elements). The page decides, not the model's choice of quotes, so a title paired with
    // a neighbouring listing's date is rejected.
    const supported =
      check.verified.some((quote) => namesEvent(quote) && mentionsDate(quote)) ||
      check.verified.some(
        (nameQuote) =>
          namesEvent(nameQuote) &&
          nearestDateIs(
            quoteIndex,
            nameQuote,
            early
              ? [
                  [month, day],
                  [pm, pd],
                ]
              : [[month, day]],
          ),
      );
    if (!supported) return reject("evidence_date_unsupported");
  }

  // --- Category -------------------------------------------------------------------------------------------------
  const classification = classifyEvent({
    title,
    description,
    performers,
    hint: extracted.category,
    defaultCategory: ctx.defaultCategory,
    venueName: ctx.venue?.name ?? null,
  });
  if (classification.category === "other") return reject(`category_other:${classification.reason}`);
  // No positive category signal: the category came from the default. Discovery proof does not count these.
  if (classification.reason === "default") warnings.push("category_default");

  const venueId = ctx.source.venueId ?? null;
  const identityKey = computeIdentityKey({
    venueId,
    sourceId: ctx.source.id,
    startLocal,
    title,
    sourceEventId: extracted.sourceEventId,
    eventUrl,
    pageUrls: [ctx.source.url, ctx.pageUrl],
  });

  const event: ValidatedEvent = {
    identityKey,
    sourceId: ctx.source.id,
    venueId,
    title,
    startLocal,
    startUtc,
    datePrecision: startUtc ? "instant" : "date",
    endLocal,
    endUtc,
    doorsLocal,
    timezone,
    description,
    imageUrl,
    eventUrl,
    ticketUrl,
    performers,
    prices,
    isFree,
    status,
    category: classification.category as KeptCategory,
    isMusic: classification.isMusic,
    evidence,
    extractor: extracted.extractor,
    sourceEventId: extracted.sourceEventId?.trim() || null,
    warnings,
  };
  return { ok: true, event };
}

export interface ValidateManyResult {
  valid: ValidatedEvent[];
  rejected: Array<{ reasons: string[]; extracted: ExtractedEvent }>;
  /** Count of events dropped as duplicates of an earlier event with the same identity key. */
  duplicates: number;
}

/** Validates a page's events, sharing one quote index, and drops duplicate identities (first one wins). */
export function validateEvents(events: ExtractedEvent[], ctx: ValidateContext): ValidateManyResult {
  const shared: ValidateContext = {
    ...ctx,
    trustInstants: ctx.trustInstants ?? pageTrustsInstants(events, ctx.timezone),
    quoteIndex:
      ctx.quoteIndex ??
      (ctx.pageText && events.some((e) => (ctx.evidenceRequiredFor ?? DEFAULT_EVIDENCE_REQUIRED)(e.extractor))
        ? buildQuoteIndex(ctx.pageText, ctx.pageContentType)
        : null),
  };
  const out: ValidateManyResult = { valid: [], rejected: [], duplicates: 0 };
  const seen = new Set<string>();
  for (const extracted of events) {
    const outcome = validateEvent(extracted, shared);
    if (!outcome.ok) {
      out.rejected.push({ reasons: outcome.reasons, extracted: outcome.extracted });
      continue;
    }
    if (seen.has(outcome.event.identityKey)) {
      out.duplicates++;
      continue;
    }
    seen.add(outcome.event.identityKey);
    out.valid.push(outcome.event);
  }
  // A page can show one event in two views, only one of them with a time. The timed copy is the event.
  const dayKey = (event: ValidatedEvent) => `${normalizeTitle(event.title)}|${event.startLocal.slice(0, 10)}`;
  const timed = new Set(out.valid.filter((event) => event.datePrecision === "instant").map(dayKey));
  const kept = out.valid.filter((event) => event.datePrecision === "instant" || !timed.has(dayKey(event)));
  out.duplicates += out.valid.length - kept.length;
  out.valid = kept;
  return out;
}

/** Epoch ms of a local "YYYY-MM-DDTHH:mm[:ss]" value read as if it were UTC (used to carry an offset across fields). */
function wallAsUtcMs(local: string): number {
  return Date.parse(`${local.length === 16 ? `${local}:00` : local}Z`);
}

/**
 * Page-level call for start times whose written wall time disagrees with their UTC instant. If most such events would
 * start in the middle of the night (00:00-05:59) as written but at a normal show hour (10:00 or later) in the venue's
 * timezone, the offsets are right and the written times are UTC ("2026-11-04T00:00:00+00:00" = 7pm Eastern). Otherwise
 * the site wrote local time with a wrong offset, and a single late show ("00:30") keeps its written time.
 */
export function pageTrustsInstants(events: ExtractedEvent[], timezone: string): boolean {
  let mismatched = 0;
  let utcLooking = 0;
  for (const event of events) {
    const instantMs = parseInstant(event.startInstant);
    const written = parseLocal(event.start);
    if (instantMs === null || written?.kind !== "datetime" || !isValidTimeZone(event.timezone ?? timezone)) continue;
    const local = withTime(formatDate(written.parts.year, written.parts.month, written.parts.day), hhmm(written.parts));
    const fromInstant = instantToLocal(instantMs, event.timezone ?? timezone);
    if (local === fromInstant) continue;
    mismatched++;
    const writtenHour = Math.floor(minutesOf(timeOf(local) as string) / 60);
    const instantHour = Math.floor(minutesOf(timeOf(fromInstant) as string) / 60);
    if (writtenHour < 6 && instantHour >= 10) utcLooking++;
  }
  return mismatched > 0 && utcLooking * 2 > mismatched;
}
