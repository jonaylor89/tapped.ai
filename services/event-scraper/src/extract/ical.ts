/**
 * iCalendar (RFC 5545) extractor: line unfolding, parameters (quoted values), text unescaping, TZID / UTC / floating /
 * all-day values, RRULE expansion (bounded window), EXDATE, RECURRENCE-ID overrides, STATUS and DURATION.
 */
import type { ExtractContext, ExtractedEvent, ExtractedLocation, Extractor, Page } from "../types.js";
import { addDays, instantToLocal, localToInstant, toIanaTimeZone } from "./time.js";
import {
  applyTitleStatus,
  blankEvent,
  categoryHint,
  cleanMultiline,
  cleanText,
  mapStatus,
  pageBase,
  parsePriceText,
  resolveUrl,
} from "./util.js";

export const ICAL_EXPANSION_DAYS = 180;
/** Occurrences/events starting before now minus this are dropped (feeds often carry years of history). */
const PAST_GRACE_MS = 24 * 3600_000;

export interface IcalProperty {
  name: string;
  params: Record<string, string>;
  value: string;
}

export interface IcalComponent {
  type: string;
  props: IcalProperty[];
  children: IcalComponent[];
}

/** Unfolds and tokenizes an ICS document into a component tree. */
export function parseIcs(text: string): IcalComponent[] {
  const lines = text
    .replace(/^﻿/, "")
    .replace(/\r\n?/g, "\n")
    .replace(/\n[ \t]/g, "")
    .split("\n");
  const root: IcalComponent = { type: "ROOT", props: [], children: [] };
  const stack: IcalComponent[] = [root];
  for (const line of lines) {
    if (!line.trim()) continue;
    const prop = parseLine(line);
    if (!prop) continue;
    const top = stack[stack.length - 1];
    if (prop.name === "BEGIN") {
      const comp: IcalComponent = { type: prop.value.trim().toUpperCase(), props: [], children: [] };
      top.children.push(comp);
      stack.push(comp);
    } else if (prop.name === "END") {
      if (stack.length > 1) stack.pop();
    } else {
      top.props.push(prop);
    }
  }
  return root.children;
}

function parseLine(line: string): IcalProperty | null {
  // name *(";" param) ":" value, where param values may be quoted and contain ":" or ";".
  let i = 0;
  let inQuote = false;
  let colon = -1;
  for (; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') inQuote = !inQuote;
    else if (ch === ":" && !inQuote) {
      colon = i;
      break;
    }
  }
  if (colon < 0) return null;
  const head = line.slice(0, colon);
  const value = line.slice(colon + 1);
  const parts: string[] = [];
  let buf = "";
  inQuote = false;
  for (const ch of head) {
    if (ch === '"') inQuote = !inQuote;
    if (ch === ";" && !inQuote) {
      parts.push(buf);
      buf = "";
    } else {
      buf += ch;
    }
  }
  parts.push(buf);
  const name = parts[0].trim().toUpperCase();
  if (!name) return null;
  const params: Record<string, string> = {};
  for (const p of parts.slice(1)) {
    const eq = p.indexOf("=");
    if (eq > 0) params[p.slice(0, eq).trim().toUpperCase()] = p.slice(eq + 1).replace(/^"|"$/g, "");
  }
  return { name, params, value };
}

export function unescapeText(value: string): string {
  return value.replace(/\\([\\;,nN])/g, (_, c: string) => (c === "n" || c === "N" ? "\n" : c));
}

// ---------------------------------------------------------------------------------------------------------------------
// Date values
// ---------------------------------------------------------------------------------------------------------------------

export interface IcalDate {
  /** Local wall-clock in `tz` ("YYYY-MM-DD" for all-day, else "YYYY-MM-DDTHH:mm"). */
  local: string;
  tz: string;
  allDay: boolean;
  /** UTC instant (null for all-day). */
  instant: Date | null;
  /** True when the source gave a TZID or UTC (not floating). */
  explicitTz: boolean;
}

/** Parses a DATE / DATE-TIME property value. UTC values are expressed in `defaultTz` wall-clock. */
export function parseIcalDate(prop: IcalProperty, defaultTz: string): IcalDate | null {
  const raw = prop.value.trim().split(",")[0];
  const m = raw.match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$/i);
  if (!m) return null;
  const date = `${m[1]}-${m[2]}-${m[3]}`;
  if (!m[4] || prop.params.VALUE?.toUpperCase() === "DATE") {
    return { local: date, tz: defaultTz, allDay: true, instant: null, explicitTz: false };
  }
  const wall = `${date}T${m[4]}:${m[5]}`;
  if (m[7]) {
    const instant = new Date(`${wall}:${m[6] ?? "00"}Z`);
    return { local: instantToLocal(instant, defaultTz), tz: defaultTz, allDay: false, instant, explicitTz: true };
  }
  const tzid = toIanaTimeZone(prop.params.TZID);
  const tz = tzid ?? defaultTz;
  return { local: wall, tz, allDay: false, instant: localToInstant(wall, tz), explicitTz: Boolean(tzid) };
}

/** ISO 8601 duration ("PT2H30M", "P1D", "-PT15M") in ms; null if unparseable. */
export function parseDuration(value: string): number | null {
  const m = value.trim().match(/^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/i);
  if (!m) return null;
  const [, sign, w, d, h, mi, s] = m;
  const ms =
    ((Number(w ?? 0) * 7 + Number(d ?? 0)) * 86400 + Number(h ?? 0) * 3600 + Number(mi ?? 0) * 60 + Number(s ?? 0)) *
    1000;
  return sign === "-" ? -ms : ms;
}

// ---------------------------------------------------------------------------------------------------------------------
// RRULE
// ---------------------------------------------------------------------------------------------------------------------

export interface RRule {
  freq: "DAILY" | "WEEKLY" | "MONTHLY" | "YEARLY";
  interval: number;
  count: number | null;
  /** Inclusive bound: either a UTC instant or a date ("YYYY-MM-DD"). */
  until: { instant: Date | null; date: string | null } | null;
  byDay: { n: number; wd: number }[];
  byMonthDay: number[];
  byMonth: number[];
  bySetPos: number[];
}

const WEEKDAYS = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];

export function parseRRule(value: string): RRule | null {
  const parts: Record<string, string> = {};
  for (const kv of value.split(";")) {
    const eq = kv.indexOf("=");
    if (eq > 0)
      parts[kv.slice(0, eq).trim().toUpperCase()] = kv
        .slice(eq + 1)
        .trim()
        .toUpperCase();
  }
  const freq = parts.FREQ;
  if (freq !== "DAILY" && freq !== "WEEKLY" && freq !== "MONTHLY" && freq !== "YEARLY") return null;
  let until: RRule["until"] = null;
  if (parts.UNTIL) {
    const m = parts.UNTIL.match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$/);
    if (m) {
      const date = `${m[1]}-${m[2]}-${m[3]}`;
      until = m[4]
        ? // Floating UNTIL values are treated as UTC; the difference is at most a few hours at the very end of a series.
          { instant: new Date(`${date}T${m[4]}:${m[5]}:${m[6]}Z`), date: null }
        : { instant: null, date };
    }
  }
  const nums = (key: string) =>
    (parts[key] ?? "")
      .split(",")
      .map((s) => Number(s))
      .filter((n) => Number.isInteger(n) && n !== 0);
  const byDay: RRule["byDay"] = [];
  for (const token of (parts.BYDAY ?? "").split(",")) {
    const m = token.trim().match(/^([+-]?\d{1,2})?(SU|MO|TU|WE|TH|FR|SA)$/);
    if (m) byDay.push({ n: m[1] ? Number(m[1]) : 0, wd: WEEKDAYS.indexOf(m[2]) });
  }
  const interval = Number(parts.INTERVAL ?? 1);
  const count = parts.COUNT ? Number(parts.COUNT) : null;
  return {
    freq,
    interval: Number.isInteger(interval) && interval > 0 ? interval : 1,
    count: count && count > 0 ? count : null,
    until,
    byDay,
    byMonthDay: nums("BYMONTHDAY"),
    byMonth: nums("BYMONTH").filter((n) => n >= 1 && n <= 12),
    bySetPos: nums("BYSETPOS"),
  };
}

function ymd(date: string): [number, number, number] {
  const [y, m, d] = date.split("-").map(Number);
  return [y, m, d];
}

function fmtDate(y: number, m: number, d: number): string {
  const t = new Date(Date.UTC(y, m - 1, d));
  return `${String(t.getUTCFullYear()).padStart(4, "0")}-${String(t.getUTCMonth() + 1).padStart(2, "0")}-${String(t.getUTCDate()).padStart(2, "0")}`;
}

function weekday(date: string): number {
  const [y, m, d] = ymd(date);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}

function daysInMonth(y: number, m: number): number {
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

/** Candidate days of month (y, m) per BYDAY / BYMONTHDAY / BYSETPOS; `fallbackDay` when neither is given. */
function monthDays(rule: RRule, y: number, m: number, fallbackDay: number): string[] {
  const dim = daysInMonth(y, m);
  let days: number[] = [];
  if (rule.byMonthDay.length) {
    days = rule.byMonthDay.map((d) => (d > 0 ? d : dim + d + 1)).filter((d) => d >= 1 && d <= dim);
  }
  if (rule.byDay.length) {
    const fromByDay: number[] = [];
    for (const { n, wd } of rule.byDay) {
      const matches: number[] = [];
      for (let d = 1; d <= dim; d++) if (new Date(Date.UTC(y, m - 1, d)).getUTCDay() === wd) matches.push(d);
      if (n === 0) fromByDay.push(...matches);
      else {
        const pick = n > 0 ? matches[n - 1] : matches[matches.length + n];
        if (pick) fromByDay.push(pick);
      }
    }
    days = rule.byMonthDay.length ? days.filter((d) => fromByDay.includes(d)) : fromByDay;
  }
  if (!rule.byMonthDay.length && !rule.byDay.length) days = fallbackDay <= dim ? [fallbackDay] : [];
  days = [...new Set(days)].sort((a, b) => a - b);
  if (rule.bySetPos.length) {
    days = rule.bySetPos
      .map((p) => (p > 0 ? days[p - 1] : days[days.length + p]))
      .filter((d): d is number => d !== undefined)
      .sort((a, b) => a - b);
  }
  return days.map((d) => fmtDate(y, m, d));
}

/**
 * Expands a rule into local start dates ("YYYY-MM-DD"), in order, starting at `dtstartDate` (always included as the
 * first instance per RFC 5545), stopping after `windowEndDate`, COUNT or UNTIL (checked by `withinUntil`).
 */
export function expandRRule(
  rule: RRule,
  dtstartDate: string,
  windowEndDate: string,
  withinUntil: (date: string) => boolean,
): string[] {
  const out: string[] = [];
  const [sy, sm, sd] = ymd(dtstartDate);
  let emitted = 0;
  const emit = (date: string): boolean => {
    if (date < dtstartDate) return true;
    if (date > windowEndDate || !withinUntil(date)) return false;
    if (rule.count !== null && emitted >= rule.count) return false;
    emitted++;
    if (out[out.length - 1] !== date) out.push(date);
    return true;
  };
  if (!emit(dtstartDate)) return out;
  // Safety bound on periods iterated (e.g. a daily rule started a decade ago with COUNT).
  for (let k = 0; k < 20000; k++) {
    let periodDates: string[] = [];
    if (rule.freq === "DAILY") {
      const date = fmtDate(sy, sm, sd + k * rule.interval);
      const okDay = !rule.byDay.length || rule.byDay.some((b) => b.wd === weekday(date));
      const okMonth = !rule.byMonth.length || rule.byMonth.includes(ymd(date)[1]);
      periodDates = okDay && okMonth ? [date] : [];
      if (date > windowEndDate) break;
    } else if (rule.freq === "WEEKLY") {
      const offsetToMonday = (weekday(dtstartDate) + 6) % 7;
      const weekStart = fmtDate(sy, sm, sd - offsetToMonday + k * 7 * rule.interval);
      if (weekStart > windowEndDate) break;
      const days = rule.byDay.length ? rule.byDay.map((b) => b.wd) : [weekday(dtstartDate)];
      const [wy, wm, wdd] = ymd(weekStart);
      periodDates = [...new Set(days)]
        .map((wd) => fmtDate(wy, wm, wdd + ((wd + 6) % 7)))
        .filter((d) => !rule.byMonth.length || rule.byMonth.includes(ymd(d)[1]))
        .sort();
    } else if (rule.freq === "MONTHLY") {
      const monthIndex = sm - 1 + k * rule.interval;
      const y = sy + Math.floor(monthIndex / 12);
      const m = (monthIndex % 12) + 1;
      if (fmtDate(y, m, 1) > windowEndDate) break;
      if (rule.byMonth.length && !rule.byMonth.includes(m)) continue;
      periodDates = monthDays(rule, y, m, sd);
    } else {
      const y = sy + k * rule.interval;
      if (fmtDate(y, 1, 1) > windowEndDate) break;
      const months = rule.byMonth.length ? rule.byMonth : [sm];
      for (const m of months) periodDates.push(...monthDays(rule, y, m, sd));
    }
    for (const date of periodDates) {
      if (date === dtstartDate) continue;
      if (!emit(date)) return out;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------------
// Extractor
// ---------------------------------------------------------------------------------------------------------------------

function prop(comp: IcalComponent, name: string): IcalProperty | undefined {
  return comp.props.find((p) => p.name === name);
}

function propsNamed(comp: IcalComponent, name: string): IcalProperty[] {
  return comp.props.filter((p) => p.name === name);
}

function textProp(comp: IcalComponent, name: string): string | null {
  const p = prop(comp, name);
  return p ? unescapeText(p.value) : null;
}

function locationFrom(comp: IcalComponent): ExtractedLocation | null {
  const raw = textProp(comp, "LOCATION");
  const text = cleanText(raw);
  if (!text) return null;
  const geo = prop(comp, "GEO")?.value.split(/[;,]/).map(Number);
  const comma = text.indexOf(",");
  // "The Hi-Fi, 1043 Virginia Ave, Indianapolis, IN" -> name + address; "1043 Virginia Ave" alone is an address.
  const firstPart = comma > 0 ? text.slice(0, comma).trim() : text;
  const startsWithNumber = /^\d/.test(firstPart);
  return {
    name: startsWithNumber ? null : firstPart,
    address: startsWithNumber ? text : comma > 0 ? text.slice(comma + 1).trim() : null,
    lat: geo && Number.isFinite(geo[0]) ? geo[0] : null,
    lng: geo && Number.isFinite(geo[1]) ? geo[1] : null,
    url: null,
  };
}

interface Occurrence {
  start: IcalDate;
  /** Key used for EXDATE/RECURRENCE-ID matching: the date for all-day values, else the UTC instant. */
  key: string;
}

function occurrenceKey(d: IcalDate): string {
  if (d.allDay || !d.instant) return d.local;
  return d.instant.toISOString();
}

/** Readable per-occurrence id suffix in the series' own zone: "20261107T2000" or "20261107". */
function occurrenceIdSuffix(d: IcalDate): string {
  const local = d.instant && !d.allDay ? instantToLocal(d.instant, d.tz) : d.local;
  return local.replace(/[-:]/g, "");
}

function buildEvent(
  comp: IcalComponent,
  start: IcalDate,
  durationMs: number | null,
  allDayDays: number | null,
  ctx: ExtractContext,
  base: string,
  sourceEventId: string | null,
): ExtractedEvent {
  const ev = blankEvent("ical");
  ev.title = cleanText(textProp(comp, "SUMMARY"));
  const venueTz = ctx.timezone;
  if (start.allDay) {
    ev.start = start.local;
    if (allDayDays && allDayDays > 1) ev.end = addDays(start.local, allDayDays - 1);
  } else if (start.instant) {
    // Feeds often carry the calendar owner's TZID; the instant is what matters, expressed in venue wall-clock time.
    ev.startInstant = start.instant.toISOString();
    ev.start = instantToLocal(start.instant, venueTz);
    if (durationMs !== null && durationMs > 0) {
      ev.end = instantToLocal(new Date(start.instant.getTime() + durationMs), venueTz);
    }
  } else {
    ev.start = start.local;
  }
  ev.rawDateText = prop(comp, "DTSTART")?.value ?? null;
  ev.description = cleanMultiline(textProp(comp, "DESCRIPTION"));
  ev.eventUrl = resolveUrl(textProp(comp, "URL"), base);
  ev.location = locationFrom(comp);
  const status = textProp(comp, "STATUS");
  ev.status = status ? mapStatus(status) : null;
  applyTitleStatus(ev);
  const categories = propsNamed(comp, "CATEGORIES").flatMap((p) => unescapeText(p.value).split(","));
  ev.category = categoryHint([], categories, ev.title);
  const attach = propsNamed(comp, "ATTACH").find((p) => /^image\//i.test(p.params.FMTTYPE ?? ""));
  ev.imageUrl = attach ? resolveUrl(attach.value, base) : null;
  ev.sourceEventId = sourceEventId;
  if (ev.description) {
    const priceLine = ev.description.match(/(?:tickets?|cover|admission|price)[^\n]{0,60}/i)?.[0];
    if (priceLine) {
      const parsed = parsePriceText(priceLine);
      ev.prices = parsed.prices;
      ev.isFree = parsed.isFree;
    }
  }
  return ev;
}

export function extractIcal(page: Page, ctx: ExtractContext): ExtractedEvent[] {
  const base = pageBase(page);
  const calendars = parseIcs(page.text).filter((c) => c.type === "VCALENDAR");
  const now = ctx.now.getTime();
  const windowStart = new Date(now - PAST_GRACE_MS);
  const windowEnd = new Date(now + ICAL_EXPANSION_DAYS * 86400_000);
  const out: ExtractedEvent[] = [];

  for (const cal of calendars) {
    const calendarTz = toIanaTimeZone(textProp(cal, "X-WR-TIMEZONE"));
    const defaultTz = calendarTz ?? ctx.timezone;
    const vevents = cal.children.filter((c) => c.type === "VEVENT");
    // RECURRENCE-ID overrides, keyed by UID + occurrence key.
    const overrides = new Map<string, IcalComponent>();
    for (const ve of vevents) {
      const rid = prop(ve, "RECURRENCE-ID");
      const uid = textProp(ve, "UID");
      if (!rid || !uid) continue;
      const d = parseIcalDate(rid, defaultTz);
      if (d) overrides.set(`${uid}|${occurrenceKey(d)}`, ve);
    }

    for (const ve of vevents) {
      if (prop(ve, "RECURRENCE-ID")) continue; // emitted through its master (or standalone below)
      const dtstartProp = prop(ve, "DTSTART");
      if (!dtstartProp) continue;
      const start = parseIcalDate(dtstartProp, defaultTz);
      if (!start) continue;
      const uid = textProp(ve, "UID");

      let durationMs: number | null = null;
      let allDayDays: number | null = null;
      const dtendProp = prop(ve, "DTEND");
      const end = dtendProp ? parseIcalDate(dtendProp, defaultTz) : null;
      const durationProp = prop(ve, "DURATION");
      if (start.allDay) {
        if (end?.allDay) allDayDays = Math.round((Date.parse(end.local) - Date.parse(start.local)) / 86400_000);
        else if (durationProp) allDayDays = Math.round((parseDuration(durationProp.value) ?? 86400_000) / 86400_000);
      } else if (end?.instant && start.instant) {
        durationMs = end.instant.getTime() - start.instant.getTime();
      } else if (durationProp) {
        durationMs = parseDuration(durationProp.value);
      }

      const rruleProp = prop(ve, "RRULE");
      const rule = rruleProp ? parseRRule(rruleProp.value) : null;
      const occurrences: Occurrence[] = [];
      if (!rule) {
        occurrences.push({ start, key: occurrenceKey(start) });
      } else {
        const exdates = new Set<string>();
        for (const ex of propsNamed(ve, "EXDATE")) {
          for (const v of ex.value.split(",")) {
            const d = parseIcalDate({ ...ex, value: v }, start.tz);
            if (d) exdates.add(d.allDay ? d.local : occurrenceKey(d));
          }
        }
        const startDate = start.local.slice(0, 10);
        const time = start.allDay ? null : start.local.slice(11, 16);
        const withinUntil = (date: string) => {
          if (!rule.until) return true;
          if (rule.until.date) return date <= rule.until.date;
          if (!time) return date <= instantToLocal(rule.until.instant as Date, start.tz).slice(0, 10);
          const inst = localToInstant(`${date}T${time}`, start.tz);
          return inst !== null && inst.getTime() <= (rule.until.instant as Date).getTime();
        };
        const windowEndDate = instantToLocal(windowEnd, start.tz).slice(0, 10);
        for (const date of expandRRule(rule, startDate, windowEndDate, withinUntil)) {
          const local = time ? `${date}T${time}` : date;
          const occ: IcalDate = {
            ...start,
            local,
            instant: time ? localToInstant(local, start.tz) : null,
          };
          const key = occurrenceKey(occ);
          if (exdates.has(key) || exdates.has(date)) continue;
          occurrences.push({ start: occ, key });
        }
      }

      for (const occ of occurrences) {
        const override = uid && rule ? overrides.get(`${uid}|${occ.key}`) : undefined;
        let comp = ve;
        let occStart = occ.start;
        let occDuration = durationMs;
        if (override) {
          comp = { ...override, props: [...override.props, ...ve.props.filter((p) => !prop(override, p.name))] };
          const os = prop(override, "DTSTART");
          const parsed = os ? parseIcalDate(os, defaultTz) : null;
          if (parsed) occStart = parsed;
          const oe = prop(override, "DTEND");
          const parsedEnd = oe ? parseIcalDate(oe, defaultTz) : null;
          if (parsedEnd?.instant && occStart.instant)
            occDuration = parsedEnd.instant.getTime() - occStart.instant.getTime();
        }
        const startMs = occStart.instant?.getTime() ?? localToInstant(occStart.local, ctx.timezone)?.getTime() ?? 0;
        const endMs = startMs + Math.max(occDuration ?? 0, (allDayDays ?? 1) * (occStart.allDay ? 86400_000 : 0));
        if (endMs < windowStart.getTime()) continue;
        if (rule && startMs > windowEnd.getTime()) continue;
        const id = uid ? (rule ? `${uid}#${occurrenceIdSuffix(occ.start)}` : uid) : null;
        out.push(buildEvent(comp, occStart, occDuration, allDayDays, ctx, base, id));
      }
    }

    // Orphan overrides whose master is missing from the feed are still events.
    const masters = new Set(vevents.filter((v) => !prop(v, "RECURRENCE-ID")).map((v) => textProp(v, "UID")));
    for (const ve of vevents) {
      const uid = textProp(ve, "UID");
      const rid = prop(ve, "RECURRENCE-ID");
      if (!rid || masters.has(uid)) continue;
      const dt = prop(ve, "DTSTART") ?? rid;
      const start = parseIcalDate(dt, defaultTz);
      if (!start) continue;
      const startMs = start.instant?.getTime() ?? Date.parse(start.local);
      if (startMs < windowStart.getTime()) continue;
      const ridDate = parseIcalDate(rid, defaultTz);
      const suffix = ridDate ? occurrenceIdSuffix(ridDate) : rid.value;
      out.push(buildEvent(ve, start, null, null, ctx, base, uid ? `${uid}#${suffix}` : null));
    }
  }
  return out;
}

export function looksLikeIcs(page: Page): boolean {
  const ct = (page.contentType ?? "").toLowerCase();
  if (ct.includes("text/calendar")) return true;
  return /^\s*BEGIN:VCALENDAR/i.test(page.text.replace(/^﻿/, "").slice(0, 200));
}

export const icalExtractor: Extractor = {
  name: "ical",
  canHandle: (page) => looksLikeIcs(page),
  extract: (page, ctx) => extractIcal(page, ctx),
};
