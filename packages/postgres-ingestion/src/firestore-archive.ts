import { createHash } from "node:crypto";
import { promisify } from "node:util";
import { gunzip } from "node:zlib";
import type { EvidenceRef } from "./evidence";
import { FIRESTORE_CRAWLER_PARSER, firestoreObservation } from "./firestore-crawler";

const decompress = promisify(gunzip);
const GROUPS = ["rawScrapeData", "scrapeRuns", "crawler", "scrapeResults"] as const;
export type ArchiveGroup = (typeof GROUPS)[number];
type ObjectMap = Record<string, unknown>;
export type ArchiveTimestamp = { $type: "timestamp"; seconds: number; nanoseconds: number };
export type ArchivedDocument = {
  path: string;
  createTime: ArchiveTimestamp;
  updateTime: ArchiveTimestamp;
  data: ObjectMap;
};
export type ArchiveEntry = {
  group: ArchiveGroup;
  count: number;
  firstPath: string;
  lastPath: string;
  evidence: EvidenceRef;
};
export type ArchiveManifest = {
  header: { format: string; project: string; parser: string; database: string; limited: false };
  entries: ArchiveEntry[];
  counts: Record<ArchiveGroup, number>;
  totals: Record<string, number>;
};
function object(value: unknown): ObjectMap {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid archive object");
  return value as ObjectMap;
}
function integer(value: unknown, max = Number.MAX_SAFE_INTEGER): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0 || value > max)
    throw new Error("Invalid archive integer");
  return value;
}
function timestamp(value: unknown): ArchiveTimestamp {
  const input = object(value);
  if (input.$type !== "timestamp" || typeof input.seconds !== "number" || !Number.isSafeInteger(input.seconds))
    throw new Error("Invalid archive timestamp");
  const nanoseconds = integer(input.nanoseconds, 999_999_999);
  if (!Number.isFinite(new Date(input.seconds * 1000).getTime())) throw new Error("Invalid archive timestamp");
  return { $type: "timestamp", seconds: input.seconds, nanoseconds };
}
export function validateArchiveReference(value: unknown, bucket: string): EvidenceRef {
  const ref = object(value);
  if (ref.bucket !== bucket || typeof ref.sha256 !== "string" || !/^[a-f0-9]{64}$/.test(ref.sha256))
    throw new Error("Invalid archive reference");
  if (
    ref.key !== `archive/${ref.sha256.slice(0, 2)}/${ref.sha256}.gz` ||
    ref.contentEncoding !== "gzip" ||
    ref.contentType !== "application/x-ndjson"
  )
    throw new Error("Invalid archive reference");
  const bytes = integer(ref.bytes, 40 * 1024 * 1024);
  if (!bytes) throw new Error("Invalid archive size");
  return {
    bucket,
    key: ref.key as string,
    sha256: ref.sha256,
    bytes,
    contentType: "application/x-ndjson",
    contentEncoding: "gzip",
  };
}
/** Transport adapters must also reject mismatched headers before buffering a body. */
export async function recoverArchiveBytes(bytes: Buffer, ref: EvidenceRef): Promise<Buffer> {
  if (bytes.length !== ref.bytes || createHash("sha256").update(bytes).digest("hex") !== ref.sha256)
    throw new Error("Archive checksum mismatch");
  return decompress(bytes, { maxOutputLength: 32 * 1024 * 1024 });
}
export function parseArchiveManifest(raw: Buffer, bucket: string, project: string): ArchiveManifest {
  const lines: unknown[] = raw
    .toString("utf8")
    .trimEnd()
    .split("\n")
    .map((line) => JSON.parse(line));
  if (lines.length < 2) throw new Error("Incomplete archive manifest");
  const header = object(lines[0]);
  const footer = object(lines[lines.length - 1]);
  if (
    header.format !== "tapped-scrape-import-v1" ||
    header.project !== project ||
    header.parser !== FIRESTORE_CRAWLER_PARSER ||
    header.limited !== false
  )
    throw new Error("Wrong, incompatible or limited source manifest");
  if (
    typeof header.database !== "string" ||
    typeof footer.completedAt !== "string" ||
    !Number.isFinite(Date.parse(footer.completedAt)) ||
    footer.limited !== false
  )
    throw new Error("Incomplete archive manifest");
  const totals = object(footer.totals);
  const counts: Record<ArchiveGroup, number> = { rawScrapeData: 0, scrapeRuns: 0, crawler: 0, scrapeResults: 0 };
  const entries: ArchiveEntry[] = lines.slice(1, -1).map((value) => {
    const entry = object(value);
    if (
      !GROUPS.includes(entry.group as ArchiveGroup) ||
      typeof entry.firstPath !== "string" ||
      typeof entry.lastPath !== "string"
    )
      throw new Error("Invalid archive entry");
    const count = integer(entry.count, 500);
    if (!count) throw new Error("Empty archive entry");
    const group = entry.group as ArchiveGroup;
    counts[group] += count;
    return {
      group,
      count,
      firstPath: entry.firstPath,
      lastPath: entry.lastPath,
      evidence: validateArchiveReference(entry.evidence, bucket),
    };
  });
  for (const group of GROUPS)
    if (counts[group] !== integer(totals[`${group}.scanned`])) throw new Error("Incomplete archive coverage");
  return {
    header: {
      format: String(header.format),
      project,
      parser: FIRESTORE_CRAWLER_PARSER,
      database: header.database,
      limited: false,
    },
    entries,
    counts,
    totals: totals as Record<string, number>,
  };
}
export function parseArchivedDocuments(raw: Buffer, entry: ArchiveEntry): ArchivedDocument[] {
  const docs = raw
    .toString("utf8")
    .trimEnd()
    .split("\n")
    .map((line): ArchivedDocument => {
      const doc = object(JSON.parse(line));
      if (typeof doc.path !== "string") throw new Error("Invalid document path");
      const parts = doc.path.split("/");
      const valid =
        entry.group === "crawler"
          ? parts.length === 2 && parts[0] === "crawler"
          : entry.group === "rawScrapeData"
            ? parts.length === 2 && parts[0] === "rawScrapeData"
            : entry.group === "scrapeRuns"
              ? parts.length === 4 && parts[0] === "rawScrapeData" && parts[2] === "scrapeRuns"
              : parts.length === 6 &&
                parts[0] === "rawScrapeData" &&
                parts[2] === "scrapeRuns" &&
                parts[4] === "scrapeResults";
      if (!valid || parts.some((part) => !part)) throw new Error("Invalid document path");
      return {
        path: doc.path,
        createTime: timestamp(doc.createTime),
        updateTime: timestamp(doc.updateTime),
        data: object(doc.data),
      };
    });
  if (
    docs.length !== entry.count ||
    docs[0]?.path !== entry.firstPath ||
    docs[docs.length - 1]?.path !== entry.lastPath
  )
    throw new Error("Archive document coverage mismatch");
  return docs;
}
/** Decode only tagged values. No Firebase client, credentials, network calls or SDK are needed. */
export function decodeFirestoreArchive(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(decodeFirestoreArchive);
  if (!value || typeof value !== "object") return value;
  const data = object(value);
  if (data.$type === "timestamp" && Object.keys(data).length === 3) {
    const t = timestamp(data);
    return {
      seconds: t.seconds,
      nanoseconds: t.nanoseconds,
      // Match the pinned Google Cloud Firestore SDK's toDate(): it rounds sub-milliseconds.
      toDate: () => new Date(t.seconds * 1000 + Math.round(t.nanoseconds / 1_000_000)),
      toMillis: () => t.seconds * 1000 + Math.floor(t.nanoseconds / 1_000_000),
    };
  }
  if (data.$type === "reference" && Object.keys(data).length === 2) {
    if (typeof data.path !== "string") throw new Error("Invalid archive reference value");
    return { path: data.path, id: data.path.split("/").slice(-1)[0] };
  }
  if (data.$type === "geopoint" && Object.keys(data).length === 3)
    return { latitude: data.latitude, longitude: data.longitude };
  if (data.$type === "bytes" && Object.keys(data).length === 2) {
    if (typeof data.base64 !== "string") throw new Error("Invalid archived bytes");
    const bytes = Buffer.from(data.base64, "base64");
    if (bytes.toString("base64") !== data.base64) throw new Error("Invalid archived bytes");
    return bytes;
  }
  if (data.$type === "date" && Object.keys(data).length === 2) {
    if (typeof data.iso !== "string" || !Number.isFinite(Date.parse(data.iso)))
      throw new Error("Invalid archived date");
    return new Date(data.iso);
  }
  if (data.$type === "number" && Object.keys(data).length === 2) {
    if (!["NaN", "Infinity", "-Infinity", "-0"].includes(String(data.value)))
      throw new Error("Invalid archived number");
    return Number(data.value);
  }
  return Object.fromEntries(Object.entries(data).map(([key, item]) => [key, decodeFirestoreArchive(item)]));
}
export function archiveTimestampIso(value: ArchiveTimestamp): string {
  const t = timestamp(value);
  return new Date(t.seconds * 1000)
    .toISOString()
    .replace(".000Z", `.${String(t.nanoseconds).padStart(9, "0").slice(0, 6)}Z`);
}
export function observationFromArchive(project: string, doc: ArchivedDocument, evidenceLine: number) {
  return firestoreObservation(
    project,
    {
      path: doc.path,
      version: `${doc.updateTime.seconds}:${doc.updateTime.nanoseconds}`,
      updatedAt: archiveTimestampIso(doc.updateTime),
      data: object(decodeFirestoreArchive(doc.data)),
    },
    evidenceLine,
  );
}
