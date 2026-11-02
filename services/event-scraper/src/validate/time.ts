/**
 * Timezone-aware date helpers built only on Intl (no date libraries).
 *
 * Local values are venue wall-clock strings without an offset ("YYYY-MM-DD", "YYYY-MM-DDTHH:mm[:ss]").
 * Conversion to UTC follows the Temporal "compatible" disambiguation:
 * - a wall time that occurs twice (fall back) resolves to the EARLIER instant;
 * - a wall time that does not exist (spring forward gap) is pushed forward by the gap length (02:30 -> 03:30).
 */

const MINUTE_MS = 60_000;
const HOUR_MS = 60 * MINUTE_MS;
export const DAY_MS = 24 * HOUR_MS;

export interface LocalParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
}

const formatterCache = new Map<string, Intl.DateTimeFormat>();

function formatter(timeZone: string): Intl.DateTimeFormat {
  let cached = formatterCache.get(timeZone);
  if (!cached) {
    cached = new Intl.DateTimeFormat("en-US", {
      timeZone,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
    formatterCache.set(timeZone, cached);
  }
  return cached;
}

/** True for IANA zone names Intl accepts (e.g. "America/Chicago", "UTC"). */
export function isValidTimeZone(timeZone: string | null | undefined): timeZone is string {
  if (!timeZone || typeof timeZone !== "string") return false;
  try {
    formatter(timeZone);
    return true;
  } catch {
    return false;
  }
}

/** Wall-clock parts of `instant` in `timeZone`. */
export function zonedParts(instant: Date | number, timeZone: string): LocalParts {
  const parts = formatter(timeZone).formatToParts(typeof instant === "number" ? new Date(instant) : instant);
  const get = (type: Intl.DateTimeFormatPartTypes): number => Number(parts.find((p) => p.type === type)?.value ?? 0);
  return {
    year: get("year"),
    month: get("month"),
    day: get("day"),
    hour: get("hour") % 24,
    minute: get("minute"),
    second: get("second"),
  };
}

/** Offset (local - UTC) in ms of `timeZone` at `epochMs`. */
export function zoneOffsetMs(epochMs: number, timeZone: string): number {
  const p = zonedParts(epochMs, timeZone);
  const asUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  const wholeSecond = epochMs - (((epochMs % 1000) + 1000) % 1000);
  return asUtc - wholeSecond;
}

const pad = (n: number, width = 2): string => String(n).padStart(width, "0");

export function formatDate(year: number, month: number, day: number): string {
  return `${pad(year, 4)}-${pad(month)}-${pad(day)}`;
}

export function formatLocalParts(p: LocalParts, withSeconds = false): string {
  const base = `${formatDate(p.year, p.month, p.day)}T${pad(p.hour)}:${pad(p.minute)}`;
  return withSeconds ? `${base}:${pad(p.second)}` : base;
}

/** Local "YYYY-MM-DD" of `instant` in `timeZone`. */
export function localDate(instant: Date | number, timeZone: string): string {
  const p = zonedParts(instant, timeZone);
  return formatDate(p.year, p.month, p.day);
}

/** Local "YYYY-MM-DDTHH:mm" of `instant` in `timeZone`. */
export function instantToLocal(instant: Date | number | string, timeZone: string): string {
  const ms =
    typeof instant === "string" ? Date.parse(instant) : typeof instant === "number" ? instant : instant.getTime();
  return formatLocalParts(zonedParts(ms, timeZone));
}

/** Converts local wall-clock parts in `timeZone` to epoch ms (compatible disambiguation, see module doc). */
export function localPartsToEpoch(p: LocalParts, timeZone: string): number {
  const wall = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  const before = zoneOffsetMs(wall - 12 * HOUR_MS, timeZone);
  const after = zoneOffsetMs(wall + 12 * HOUR_MS, timeZone);
  const candidates = [...new Set([wall - before, wall - after])].sort((a, b) => a - b);
  for (const candidate of candidates) {
    const roundTrip = zonedParts(candidate, timeZone);
    if (
      roundTrip.year === p.year &&
      roundTrip.month === p.month &&
      roundTrip.day === p.day &&
      roundTrip.hour === p.hour &&
      roundTrip.minute === p.minute
    ) {
      return candidate;
    }
  }
  // Gap: interpret with the offset in force before the transition, which moves the time forward.
  return wall - before;
}

/** Converts a local "YYYY-MM-DDTHH:mm[:ss]" string to an ISO UTC instant. Null if unparseable. */
export function localToUtc(local: string, timeZone: string): string | null {
  const parsed = parseLocal(local);
  if (!parsed || parsed.kind !== "datetime") return null;
  return new Date(localPartsToEpoch(parsed.parts, timeZone)).toISOString();
}

export type ParsedLocal =
  | { kind: "datetime"; parts: LocalParts }
  | { kind: "date"; parts: LocalParts }
  | { kind: "yearless"; month: number; day: number; hour: number | null; minute: number | null; second: number | null }
  | { kind: "time"; hour: number; minute: number; second: number };

/** Parses the local shapes described in types.ts. Validates calendar dates (no Feb 30). */
export function parseLocal(value: string | null | undefined): ParsedLocal | null {
  if (!value) return null;
  const text = value.trim();
  let m = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?)?$/.exec(text);
  if (m) {
    const [year, month, day] = [Number(m[1]), Number(m[2]), Number(m[3])];
    if (!isValidCalendarDate(year, month, day)) return null;
    if (m[4] === undefined) return { kind: "date", parts: { year, month, day, hour: 0, minute: 0, second: 0 } };
    const [hour, minute, second] = [Number(m[4]), Number(m[5]), Number(m[6] ?? 0)];
    if (!isValidTime(hour, minute, second)) return null;
    return { kind: "datetime", parts: { year, month, day, hour, minute, second } };
  }
  m = /^--(\d{2})-?(\d{2})(?:[T ](\d{1,2}):(\d{2})(?::(\d{2}))?)?$/.exec(text);
  if (m) {
    const [month, day] = [Number(m[1]), Number(m[2])];
    // Feb 29 is valid in some year; check against a leap year.
    if (!isValidCalendarDate(2028, month, day)) return null;
    if (m[3] === undefined) return { kind: "yearless", month, day, hour: null, minute: null, second: null };
    const [hour, minute, second] = [Number(m[3]), Number(m[4]), Number(m[5] ?? 0)];
    if (!isValidTime(hour, minute, second)) return null;
    return { kind: "yearless", month, day, hour, minute, second };
  }
  m = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(text);
  if (m) {
    const [hour, minute, second] = [Number(m[1]), Number(m[2]), Number(m[3] ?? 0)];
    if (!isValidTime(hour, minute, second)) return null;
    return { kind: "time", hour, minute, second };
  }
  return null;
}

export function isValidCalendarDate(year: number, month: number, day: number): boolean {
  if (!Number.isInteger(year) || !Number.isInteger(month) || !Number.isInteger(day)) return false;
  if (month < 1 || month > 12 || day < 1) return false;
  return day <= daysInMonth(year, month);
}

function isValidTime(hour: number, minute: number, second: number): boolean {
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 && second >= 0 && second <= 59;
}

export function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/** Adds whole days to a "YYYY-MM-DD" date (calendar arithmetic, timezone independent). */
export function addDays(date: string, days: number): string {
  const [y, m, d] = date.split("-").map(Number);
  const t = new Date(Date.UTC(y as number, (m as number) - 1, (d as number) + days));
  return formatDate(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate());
}

/** Adds calendar months to a "YYYY-MM-DD" date, clamping the day (Jan 31 + 1 month = Feb 28/29). */
export function addMonths(date: string, months: number): string {
  const [y, m, d] = date.split("-").map(Number);
  const total = (y as number) * 12 + ((m as number) - 1) + months;
  const year = Math.floor(total / 12);
  const month = (total % 12) + 1;
  return formatDate(year, month, Math.min(d as number, daysInMonth(year, month)));
}

/** Whole days between two "YYYY-MM-DD" dates (b - a). */
export function daysBetween(a: string, b: string): number {
  return Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / DAY_MS);
}

/** 0 = Sunday ... 6 = Saturday for a "YYYY-MM-DD" date. */
export function weekdayOf(date: string): number {
  return new Date(`${date}T00:00:00Z`).getUTCDay();
}

/** "HH:mm" of a local datetime string, or null for date-only. */
export function timeOf(local: string): string | null {
  const m = /T(\d{2}:\d{2})/.exec(local);
  return m ? (m[1] as string) : null;
}

export function dateOf(local: string): string {
  return local.slice(0, 10);
}

/** Minutes since midnight for "HH:mm". */
export function minutesOf(time: string): number {
  const [h, m] = time.split(":").map(Number);
  return (h as number) * 60 + (m as number);
}

/** Parses an ISO instant WITH an explicit offset or Z. Returns epoch ms or null. */
export function parseInstant(value: string | null | undefined): number | null {
  if (!value) return null;
  const text = value.trim();
  if (!/^\d{4}-\d{2}-\d{2}T\d{1,2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$/i.test(text)) return null;
  const normalized = text.replace(/([+-]\d{2})(\d{2})$/, "$1:$2");
  const ms = Date.parse(normalized);
  return Number.isFinite(ms) ? ms : null;
}
