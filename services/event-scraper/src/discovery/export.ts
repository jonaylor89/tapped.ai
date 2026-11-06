/**
 * Human review list: promoted candidates (proven event source) and needs_review candidates (identity doubts),
 * with the evidence a reviewer needs. Written as JSON (full detail) and CSV (spreadsheet triage).
 * Nothing here writes to production; creating venue profiles stays a human decision.
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { type Db, getVenue, listCandidates, listPlaceAliases } from "../db.js";
import type { Candidate, CandidateStatus } from "../types.js";

export interface ReviewEntry {
  candidateId: number;
  status: CandidateStatus;
  statusReason: string | null;
  name: string;
  address: string | null;
  city: string | null;
  lat: number | null;
  lng: number | null;
  website: string | null;
  timezone: string | null;
  discoveredFrom: string;
  feeds: string[];
  matchedVenueId: string | null;
  matchedVenueName: string | null;
  sourceUrl: string | null;
  sourceKind: string | null;
  provenEventCount: number;
  canonicalPlaceId: string | null;
  placeIds: string[];
  conflict: unknown;
  review: unknown;
  sampleEvents: { title: string; startLocal: string; eventUrl: string | null }[];
  sharedSourceWith: number[];
  evidenceSha256: string | null;
  updatedAt: string;
}

export const DEFAULT_REVIEW_STATUSES: readonly CandidateStatus[] = ["promoted", "needs_review"];

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
}

async function toEntry(db: Db, candidate: Candidate): Promise<ReviewEntry> {
  const aliases = await listPlaceAliases(db, { candidateId: candidate.id });
  const proof = record(candidate.evidence.proof);
  const sample = Array.isArray(proof.sample) ? (proof.sample as Record<string, unknown>[]) : [];
  return {
    candidateId: candidate.id,
    status: candidate.status,
    statusReason: candidate.statusReason,
    name: candidate.name,
    address: candidate.address,
    city: candidate.city,
    lat: candidate.lat,
    lng: candidate.lng,
    website: candidate.website,
    timezone: candidate.timezone,
    discoveredFrom: candidate.discoveredFrom,
    feeds: Array.isArray(candidate.evidence.feeds)
      ? (candidate.evidence.feeds as string[])
      : [candidate.discoveredFrom],
    matchedVenueId: candidate.matchedVenueId,
    matchedVenueName: candidate.matchedVenueId ? ((await getVenue(db, candidate.matchedVenueId))?.name ?? null) : null,
    sourceUrl: candidate.sourceUrl,
    sourceKind: candidate.sourceKind,
    provenEventCount: candidate.provenEventCount,
    canonicalPlaceId: aliases.find((alias) => alias.isCanonical)?.placeId ?? candidate.primaryPlaceId,
    placeIds: aliases.map((alias) => alias.placeId),
    conflict: candidate.evidence.conflict ?? null,
    review: candidate.evidence.review ?? null,
    sampleEvents: sample.map((event) => ({
      title: String(event.title ?? ""),
      startLocal: String(event.startLocal ?? ""),
      eventUrl: typeof event.eventUrl === "string" ? event.eventUrl : null,
    })),
    sharedSourceWith: Array.isArray(proof.sharedSourceWith) ? (proof.sharedSourceWith as number[]) : [],
    evidenceSha256: typeof proof.evidenceSha256 === "string" ? proof.evidenceSha256 : null,
    updatedAt: new Date(candidate.updatedAt).toISOString(),
  };
}

/** Review entries for the given statuses (default promoted + needs_review), promoted first. */
export async function buildReviewList(
  db: Db,
  options: { statuses?: readonly CandidateStatus[] } = {},
): Promise<ReviewEntry[]> {
  const statuses = [...(options.statuses ?? DEFAULT_REVIEW_STATUSES)];
  const order = new Map(statuses.map((status, i) => [status, i]));
  const entries: ReviewEntry[] = [];
  for (const candidate of await listCandidates(db, { status: statuses })) entries.push(await toEntry(db, candidate));
  return entries.sort(
    (a, b) => (order.get(a.status) ?? 0) - (order.get(b.status) ?? 0) || a.candidateId - b.candidateId,
  );
}

const CSV_COLUMNS: (keyof ReviewEntry | "sampleTitles")[] = [
  "candidateId",
  "status",
  "statusReason",
  "name",
  "address",
  "city",
  "lat",
  "lng",
  "website",
  "timezone",
  "feeds",
  "matchedVenueId",
  "matchedVenueName",
  "sourceUrl",
  "sourceKind",
  "provenEventCount",
  "canonicalPlaceId",
  "placeIds",
  "sharedSourceWith",
  "sampleTitles",
];

/** CSV cell: quoted when needed; formula-leading values are prefixed so spreadsheets do not execute them. */
export function csvCell(value: unknown): string {
  let text = value == null ? "" : Array.isArray(value) ? value.join("; ") : String(value);
  if (/^[=+\-@\t\r]/.test(text) && !/^-?\d+(\.\d+)?$/.test(text)) text = `'${text}`;
  return /[",\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

export function reviewListToCsv(entries: ReviewEntry[]): string {
  const lines = [CSV_COLUMNS.join(",")];
  for (const entry of entries) {
    lines.push(
      CSV_COLUMNS.map((column) =>
        csvCell(
          column === "sampleTitles"
            ? entry.sampleEvents.map((event) => `${event.startLocal} ${event.title}`)
            : entry[column as keyof ReviewEntry],
        ),
      ).join(","),
    );
  }
  return `${lines.join("\n")}\n`;
}

/** Writes `<prefix>.json` and `<prefix>.csv` into `dir` and returns their paths. */
export async function writeReviewList(
  db: Db,
  dir: string,
  options: { statuses?: readonly CandidateStatus[]; prefix?: string; now?: Date } = {},
): Promise<{ jsonPath: string; csvPath: string; count: number }> {
  const entries = await buildReviewList(db, options);
  mkdirSync(dir, { recursive: true });
  const prefix = options.prefix ?? `venue-review-${(options.now ?? new Date()).toISOString().slice(0, 10)}`;
  const jsonPath = join(dir, `${prefix}.json`);
  const csvPath = join(dir, `${prefix}.csv`);
  writeFileSync(jsonPath, `${JSON.stringify(entries, null, 2)}\n`);
  writeFileSync(csvPath, reviewListToCsv(entries));
  return { jsonPath, csvPath, count: entries.length };
}
