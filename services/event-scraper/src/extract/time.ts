/**
 * Timezone and date-string helpers for extractors. Pure Intl, no dependencies.
 *
 * Local values follow the conventions in ../types.ts: "YYYY-MM-DD", "YYYY-MM-DDTHH:mm", yearless "--MM-DD[THH:mm]",
 * time-only "HH:mm". Instants are ISO strings ending in "Z".
 */
import { localPartsToEpoch } from "../validate/time.js";

const formatterCache = new Map<string, Intl.DateTimeFormat>();

function formatter(timeZone: string): Intl.DateTimeFormat {
  let f = formatterCache.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", {
      timeZone,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
    formatterCache.set(timeZone, f);
  }
  return f;
}

export function isValidTimeZone(tz: string | null | undefined): tz is string {
  if (!tz || typeof tz !== "string") return false;
  try {
    formatter(tz);
    return true;
  } catch {
    return false;
  }
}

/** Windows zone names that show up in Outlook/Exchange ICS exports. */
const WINDOWS_ZONES: Record<string, string> = {
  "eastern standard time": "America/New_York",
  "central standard time": "America/Chicago",
  "mountain standard time": "America/Denver",
  "us mountain standard time": "America/Phoenix",
  "pacific standard time": "America/Los_Angeles",
  "alaskan standard time": "America/Anchorage",
  "hawaiian standard time": "Pacific/Honolulu",
  "atlantic standard time": "America/Halifax",
  "gmt standard time": "Europe/London",
  "w. europe standard time": "Europe/Berlin",
  "romance standard time": "Europe/Paris",
  "central europe standard time": "Europe/Budapest",
  "aus eastern standard time": "Australia/Sydney",
  utc: "UTC",
  gmt: "UTC",
};

/**
 * Maps a TZID / timezone label to an IANA name, or null if it can't be recognized. Handles plain IANA names,
 * vendor-prefixed ones ("/mozilla.org/20050126_1/America/New_York") and common Windows names.
 */
export function toIanaTimeZone(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const value = raw.trim().replace(/^"|"$/g, "");
  if (!value) return null;
  if (value.includes("/") && isValidTimeZone(value) && !value.startsWith("/")) return value;
  const windows = WINDOWS_ZONES[value.toLowerCase()];
  if (windows) return windows;
  const match = value.match(/([A-Za-z]+(?:\/[A-Za-z0-9_+-]+){1,2})$/);
  if (match && isValidTimeZone(match[1])) return match[1];
  if (value === "UTC" || value === "Etc/UTC" || value === "Z") return "UTC";
  return null;
}

interface WallParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
}

function wallParts(date: Date, timeZone: string): WallParts {
  const out: Record<string, number> = {};
  for (const part of formatter(timeZone).formatToParts(date)) {
    if (part.type !== "literal") out[part.type] = Number(part.value);
  }
  return {
    year: out.year,
    month: out.month,
    day: out.day,
    hour: out.hour === 24 ? 0 : out.hour,
    minute: out.minute,
    second: out.second,
  };
}

/** Offset of `timeZone` from UTC at `date`, in ms (e.g. -6h for America/Chicago in winter). */
export function timeZoneOffsetMs(date: Date, timeZone: string): number {
  const p = wallParts(date, timeZone);
  const asUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  return asUtc - Math.floor(date.getTime() / 1000) * 1000;
}

const pad = (n: number, width = 2) => String(n).padStart(width, "0");

/** Formats an instant as venue wall-clock "YYYY-MM-DDTHH:mm" in `timeZone`. */
export function instantToLocal(date: Date, timeZone: string): string {
  const p = wallParts(date, timeZone);
  return `${pad(p.year, 4)}-${pad(p.month)}-${pad(p.day)}T${pad(p.hour)}:${pad(p.minute)}`;
}

/** Calendar date "YYYY-MM-DD" of an instant in `timeZone`. */
export function instantToLocalDate(date: Date, timeZone: string): string {
  return instantToLocal(date, timeZone).slice(0, 10);
}

const LOCAL_RE = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2}))?)?$/;

/**
 * Converts a full local value ("YYYY-MM-DD[THH:mm[:ss]]") in `timeZone` to a UTC Date. Date-only values resolve to
 * local midnight. Nonexistent DST-gap times resolve forward, ambiguous times to the first occurrence.
 */
export function localToInstant(local: string, timeZone: string): Date | null {
  const m = local.match(LOCAL_RE);
  if (!m) return null;
  const parts = {
    year: Number(m[1]),
    month: Number(m[2]),
    day: Number(m[3]),
    hour: Number(m[4] ?? 0),
    minute: Number(m[5] ?? 0),
    second: Number(m[6] ?? 0),
  };
  // One implementation for extraction and validation (validate/time.ts): candidate offsets are round-tripped and
  // the earliest valid one wins, so ambiguous fall-back times resolve to the first occurrence in every zone.
  const epoch = localPartsToEpoch(parts, timeZone);
  return Number.isNaN(epoch) ? null : new Date(epoch);
}

/** Trims seconds: "2026-11-07T20:00:00" -> "2026-11-07T20:00". */
export function trimLocal(local: string): string {
  const m = local.match(/^(\d{4}-\d{2}-\d{2})(?:[T ](\d{2}:\d{2}))?/);
  if (!m) return local;
  return m[2] ? `${m[1]}T${m[2]}` : m[1];
}

/** Adds whole days to "YYYY-MM-DD". */
export function addDays(date: string, days: number): string {
  const [y, mo, d] = date.slice(0, 10).split("-").map(Number);
  const t = new Date(Date.UTC(y, mo - 1, d + days));
  return `${pad(t.getUTCFullYear(), 4)}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`;
}

export interface ParsedDate {
  /** Local value in the effective timezone (full, date-only or yearless). */
  local: string;
  /** UTC instant if the input carried an offset. */
  instant: string | null;
  /** Wall clock exactly as written before the offset ("YYYY-MM-DDTHH:mm"), when the input carried one. */
  wallClock?: string | null;
  /** The written offset: "Z" or a numeric one like "-05:00" (when present). */
  zone?: string | null;
  /** True when the input had no time of day. */
  dateOnly: boolean;
}

const MONTHS: Record<string, number> = {
  jan: 1,
  feb: 2,
  mar: 3,
  apr: 4,
  may: 5,
  jun: 6,
  jul: 7,
  aug: 8,
  sep: 9,
  sept: 9,
  oct: 10,
  nov: 11,
  dec: 12,
};

/** Parses "8pm", "8:30 PM", "20:00", "noon"; returns "HH:mm" or null. */
export function parseTimeOfDay(text: string): string | null {
  const t = text.trim().toLowerCase();
  if (/^noon\b/.test(t)) return "12:00";
  if (/^midnight\b/.test(t)) return "00:00";
  const m = t.match(/^(\d{1,2})(?:[:.](\d{2}))?(?::\d{2})?\s*(a\.?m\.?|p\.?m\.?|a|p)?\b/);
  if (!m) return null;
  let hour = Number(m[1]);
  const minute = Number(m[2] ?? 0);
  const ampm = m[3]?.[0];
  if (!ampm && m[2] === undefined) return null;
  if (minute > 59) return null;
  if (ampm) {
    if (hour < 1 || hour > 12) return null;
    if (ampm === "p" && hour !== 12) hour += 12;
    if (ampm === "a" && hour === 12) hour = 0;
  } else if (hour > 23) {
    return null;
  }
  return `${pad(hour)}:${pad(minute)}`;
}

/**
 * Parses a date/time value as found in structured data:
 * - ISO local ("2026-11-07", "2026-11-07T20:00", "2026-11-07 20:00:00") -> local, no instant
 * - ISO with offset/Z -> instant, local = wall clock in `timeZone`
 * - Basic ISO ("20261107T200000Z") the same way
 * - Human text ("Friday, November 7, 2026 at 8:00 PM", "Nov 7 8pm") -> local; yearless if no year is given.
 */
export function parseDateValue(raw: string | null | undefined, timeZone: string): ParsedDate | null {
  if (raw === null || raw === undefined) return null;
  const value = String(raw).trim();
  if (!value) return null;

  const iso = value.match(
    /^(\d{4})-?(\d{2})-?(\d{2})(?:[T ](\d{2}):?(\d{2})(?::?(\d{2})(?:[.,]\d+)?)?)?\s*(Z|[+-]\d{2}(?::?\d{2})?)?$/i,
  );
  if (iso) {
    const [, y, mo, d, h, mi, , zone] = iso;
    const date = `${y}-${mo}-${d}`;
    if (Number(mo) < 1 || Number(mo) > 12 || Number(d) < 1 || Number(d) > 31) return null;
    if (h === undefined) return { local: date, instant: null, dateOnly: true };
    if (Number(h) > 24 || Number(mi) > 59) return null;
    const local = `${date}T${h === "24" ? "00" : h}:${mi}`;
    if (!zone) return { local: h === "24" ? `${addDays(date, 1)}T00:${mi}` : local, instant: null, dateOnly: false };
    let offsetMin = 0;
    if (zone.toUpperCase() !== "Z") {
      const zm = zone.match(/^([+-])(\d{2}):?(\d{2})?$/);
      if (!zm) return null;
      offsetMin = (zm[1] === "-" ? -1 : 1) * (Number(zm[2]) * 60 + Number(zm[3] ?? 0));
    }
    const sec = iso[6] ? Number(iso[6]) : 0;
    const ms = Date.UTC(Number(y), Number(mo) - 1, Number(d), Number(h), Number(mi), sec) - offsetMin * 60_000;
    const instant = new Date(ms);
    if (Number.isNaN(instant.getTime())) return null;
    return {
      local: instantToLocal(instant, timeZone),
      instant: instant.toISOString(),
      dateOnly: false,
      wallClock: h === "24" ? `${addDays(date, 1)}T00:${mi}` : local,
      zone,
    };
  }

  return parseHumanDate(value);
}

/** Lenient human-readable date parse (English month names). Yearless results use "--MM-DD[THH:mm]". */
export function parseHumanDate(value: string): ParsedDate | null {
  const text = value
    .toLowerCase()
    .replace(/(\d)(st|nd|rd|th)\b/g, "$1")
    .replace(/,/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  let month: number | undefined;
  let day: number | undefined;
  let year: number | undefined;
  let rest = "";

  const monthFirst = text.match(
    /\b(jan|feb|mar|apr|may|jun|jul|aug|sept?|oct|nov|dec)[a-z]*\.? (\d{1,2})\b(?: (\d{4})\b)?(.*)$/,
  );
  const dayFirst = text.match(
    /\b(\d{1,2}) (jan|feb|mar|apr|may|jun|jul|aug|sept?|oct|nov|dec)[a-z]*\.?(?: (\d{4})\b)?(.*)$/,
  );
  const numeric = text.match(/\b(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\b(.*)$/);
  if (monthFirst) {
    month = MONTHS[monthFirst[1]];
    day = Number(monthFirst[2]);
    year = monthFirst[3] ? Number(monthFirst[3]) : undefined;
    rest = monthFirst[4];
  } else if (dayFirst) {
    day = Number(dayFirst[1]);
    month = MONTHS[dayFirst[2]];
    year = dayFirst[3] ? Number(dayFirst[3]) : undefined;
    rest = dayFirst[4];
  } else if (numeric) {
    // US-style M/D[/Y]: these are US venues first.
    month = Number(numeric[1]);
    day = Number(numeric[2]);
    if (numeric[3]) year = numeric[3].length === 2 ? 2000 + Number(numeric[3]) : Number(numeric[3]);
    rest = numeric[4];
  } else {
    return null;
  }
  if (!month || !day || month > 12 || day > 31) return null;
  const timeMatch = rest.match(/\b(\d{1,2}(?:[:.]\d{2})?\s*(?:a\.?m\.?|p\.?m\.?|a|p)\b|\d{1,2}:\d{2}|noon|midnight)/);
  const time = timeMatch ? parseTimeOfDay(timeMatch[1]) : null;
  const md = `${pad(month)}-${pad(day)}`;
  const date = year ? `${pad(year, 4)}-${md}` : `--${md}`;
  return { local: time ? `${date}T${time}` : date, instant: null, dateOnly: !time };
}

/**
 * Normalizes a door/end time that may be time-only ("19:00:00", "7pm") or a full date/time.
 * Returns a local value (full or "HH:mm").
 */
export function parseClockOrDate(raw: string | null | undefined, timeZone: string): string | null {
  if (raw === null || raw === undefined) return null;
  const value = String(raw).trim();
  if (!value) return null;
  const timeOnly = value.match(/^T?(\d{1,2}):(\d{2})(?::\d{2}(?:\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?$/i);
  if (timeOnly && !timeOnly[3]) {
    const h = Number(timeOnly[1]);
    return h < 24 ? `${pad(h)}:${timeOnly[2]}` : null;
  }
  const clock = parseTimeOfDay(value);
  if (clock && /^\d{1,2}(?:[:.]\d{2})?\s*[ap]/i.test(value)) return clock;
  const parsed = parseDateValue(value, timeZone);
  return parsed ? parsed.local : null;
}
