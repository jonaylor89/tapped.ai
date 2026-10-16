import { createHash } from "node:crypto";
import type { Pool } from "pg";
import type { EvidenceRef, EvidenceStore } from "./evidence";

export type ScrapedInput = Record<string, unknown>;
export type ObservationInput = {
  source: string;
  sourceKey: string;
  deliveryKey: string;
  observedAt: string;
  parserVersion: string;
  venueId?: string | null;
  runId?: string | null;
  legacyRunId?: string | null;
  evidenceLine?: number;
  /** Historical run results can be retained without creating a second set of current events. */
  materialize?: boolean;
  data: ScrapedInput;
};
export type Price = {
  kind: "ticket" | "door" | "other";
  amountMin: number | null;
  amountMax: number | null;
  currency: string | null;
  description: string | null;
};
export type NormalizedFacts = {
  title: string | null;
  description: string | null;
  startTime: string | null;
  endTime: string | null;
  timezone: string | null;
  datePrecision: "instant" | "date" | "unknown";
  musicClassification: "music" | "non_music" | "unknown";
  status: "scheduled" | "canceled" | "postponed" | "unknown";
  url: string | null;
  flierUrl: string | null;
  performers: string[];
  prices: Price[];
};

export function record(value: unknown): ScrapedInput {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? (value as ScrapedInput) : {};
}
export function text(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}
export function timestamp(value: unknown): string | null {
  try {
    if (value && typeof value === "object" && "toDate" in value && typeof value.toDate === "function")
      return timestamp(value.toDate());
    if (value instanceof Date) return Number.isFinite(value.getTime()) ? value.toISOString() : null;
    // A date-only or timezone-less value is not an instant. Do not assume a worker's local timezone.
    if (typeof value !== "string") return null;
    const parts = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$/.exec(value);
    if (!parts) return null;
    const [year, month, day, hour, minute, second] = parts.slice(1, 7).map(Number);
    const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
    const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month < 1 || month > 12 || day < 1 || day > days[month - 1] || hour > 23 || minute > 59 || second > 59)
      return null;
    const date = new Date(value);
    return Number.isFinite(date.getTime()) ? date.toISOString() : null;
  } catch {
    return null;
  }
}

function databaseString(value: string): string {
  return value
    .split("\u0000")
    .join("\uFFFD")
    .replace(/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/g, "\uFFFD");
}
function cleanFactStrings(value: unknown, errors: string[]): unknown {
  if (typeof value === "string") {
    const cleaned = databaseString(value);
    if (cleaned !== value) errors.push("invalid_unicode");
    return cleaned;
  }
  if (Array.isArray(value)) return value.map((item) => cleanFactStrings(item, errors));
  if (value && typeof value === "object")
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, cleanFactStrings(item, errors)]));
  return value;
}

/** Whitelist only public event extraction fields. Original messy values belong in private evidence. */
export function normalizeFacts(data: ScrapedInput): { facts: NormalizedFacts; errors: string[] } {
  const errors: string[] = [];
  const startTime = timestamp(data.startTime);
  const endTime = timestamp(data.endTime);
  // Negative URL classifications are useful even when the page has no event/date at all.
  if (!startTime && data.isMusicEvent !== false) errors.push("missing_or_invalid_start_time");
  else if (data.startTime != null && !startTime) errors.push("invalid_start_time");
  if (data.endTime != null && !endTime) errors.push("invalid_end_time");
  if (startTime && endTime && startTime > endTime) errors.push("reversed_times");
  const lineup = data.performers ?? data.artists ?? [];
  const performers: string[] = [];
  if (!Array.isArray(lineup) || lineup.length > 100) errors.push("invalid_performers");
  else {
    for (const entry of lineup) {
      if (typeof entry !== "string" || !entry.trim() || entry.trim().length > 200) errors.push("invalid_performer");
      else performers.push(entry.trim());
    }
  }
  const url = (value: unknown, field: string): string | null => {
    if (value == null || value === "") return null;
    try {
      if (typeof value !== "string") throw new Error();
      const parsed = new URL(value);
      if (!["https:", "http:"].includes(parsed.protocol) || parsed.username || parsed.password) throw new Error();
      return value;
    } catch {
      errors.push(`invalid_${field}`);
      return null;
    }
  };
  const prices: Price[] = [];
  const amount = (value: unknown): number | null => {
    if (value == null) return null;
    if (typeof value === "number" && Number.isFinite(value) && value >= 0 && value < 10_000_000_000) return value;
    errors.push("invalid_price");
    return null;
  };
  let currency = text(data.currency);
  if (currency && !/^[A-Z]{3}$/.test(currency)) {
    errors.push("invalid_currency");
    currency = null;
  }
  // Legacy numbers have no currency information. Preserve that uncertainty, never assume USD.
  for (const [key, kind] of [
    ["ticketPrice", "ticket"],
    ["doorPrice", "door"],
  ] as const) {
    if (data[key] != null) {
      const value = amount(data[key]);
      prices.push({ kind, amountMin: value, amountMax: value, currency, description: null });
    }
  }
  if (data.prices != null) {
    if (!Array.isArray(data.prices) || data.prices.length > 100) errors.push("invalid_prices");
    else {
      prices.length = 0;
      for (const raw of data.prices) {
        const price = record(raw);
        const min = amount(price.amountMin);
        const max = amount(price.amountMax);
        const code = text(price.currency);
        if (code && !/^[A-Z]{3}$/.test(code)) errors.push("invalid_currency");
        if (min !== null && max !== null && min > max) errors.push("invalid_price_range");
        if (!["ticket", "door", "other"].includes(String(price.kind))) errors.push("invalid_price_kind");
        prices.push({
          kind: ["ticket", "door"].includes(String(price.kind)) ? (price.kind as "ticket" | "door") : "other",
          amountMin: min,
          amountMax: max,
          currency: code && /^[A-Z]{3}$/.test(code) ? code : null,
          description: text(price.description),
        });
      }
    }
  }
  return {
    facts: cleanFactStrings(
      {
        title: text(data.title),
        description: text(data.description),
        startTime,
        endTime,
        timezone: text(data.timezone),
        datePrecision: data.datePrecision === "date" ? "date" : startTime ? "instant" : "unknown",
        musicClassification:
          data.isMusicEvent === true ? "music" : data.isMusicEvent === false ? "non_music" : "unknown",
        status: ["scheduled", "canceled", "postponed"].includes(String(data.status))
          ? (data.status as "scheduled" | "canceled" | "postponed")
          : "unknown",
        url: url(data.url, "url"),
        flierUrl: url(data.flierUrl, "flier_url"),
        performers: [...new Set(performers)],
        prices,
      },
      errors,
    ) as NormalizedFacts,
    errors: [...new Set(errors)],
  };
}

export function normalizeObservation(input: ObservationInput) {
  if (!/^[a-z][a-z0-9_-]{0,99}$/.test(input.source)) throw new Error("Invalid source namespace");
  if (input.materialize !== undefined && typeof input.materialize !== "boolean")
    throw new Error("Invalid materialization flag");
  if (input.evidenceLine !== undefined && (!Number.isSafeInteger(input.evidenceLine) || input.evidenceLine < 1))
    throw new Error("Invalid evidence line");
  for (const [value, max] of [
    [input.source, 100],
    [input.sourceKey, 4096],
    [input.deliveryKey, 512],
    [input.parserVersion, 200],
  ] as const)
    if (typeof value !== "string" || !value.length || value.length > max || databaseString(value) !== value)
      throw new Error("Invalid observation identity");
  const observedAt = timestamp(input.observedAt);
  if (!observedAt || new Date(observedAt).getTime() > Date.now() + 300_000) throw new Error("Invalid observation time");
  const { data, ...envelope } = input;
  const normalized = normalizeFacts(data);
  for (const field of ["venueId", "runId", "legacyRunId"] as const) {
    const value = envelope[field];
    if (value != null && (typeof value !== "string" || databaseString(value) !== value)) {
      envelope[field] = null;
      normalized.errors.push(`invalid_${field}`);
    }
  }
  // Preserve source microseconds for Postgres ordering instead of rounding through JS Date.
  return { ...envelope, observedAt: input.observedAt, ...normalized };
}

export type ObservationResult = {
  observation_id: string;
  event_id: string | null;
  action: "inserted" | "updated" | "historical" | "duplicate" | "quarantined" | "archived";
  issues: string[];
};
export async function registerEvidence(pool: Pool, evidence: EvidenceRef): Promise<string> {
  const result = await pool.query("SELECT register_scrape_object($1::jsonb) AS id", [JSON.stringify(evidence)]);
  return String(result.rows[0].id);
}
export async function recordObservations(
  pool: Pool,
  inputs: ObservationInput[],
  evidence: EvidenceRef,
): Promise<ObservationResult[]> {
  if (!inputs.length || inputs.length > 500) throw new Error("Observation batch must contain 1–500 items");
  const normalized = inputs.map(normalizeObservation);
  const evidenceId = await registerEvidence(pool, evidence);
  const result = await pool.query("SELECT * FROM record_scrape_observations($1::jsonb)", [
    JSON.stringify(normalized.map((item) => ({ ...item, evidenceId }))),
  ]);
  return result.rows;
}

/** Evidence upload/verification completes before Postgres receives any reference. */
export async function captureObservations(
  pool: Pool,
  store: EvidenceStore,
  inputs: ObservationInput[],
  raw: Buffer,
  options = { retention: "evidence" as "archive" | "evidence", contentType: "application/x-ndjson" },
): Promise<ObservationResult[]> {
  if (!inputs.length || inputs.length > 500) throw new Error("Observation batch must contain 1–500 items");
  inputs.forEach(normalizeObservation);
  const evidence = await store.put(raw, options);
  return recordObservations(pool, inputs, evidence);
}
export function deliveryKey(...parts: string[]): string {
  return createHash("sha256").update(JSON.stringify(parts)).digest("hex");
}
