import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { gzipSync } from "node:zlib";
import {
  type ArchivedDocument,
  type ArchiveEntry,
  archiveTimestampIso,
  decodeFirestoreArchive,
  observationFromArchive,
  parseArchivedDocuments,
  parseArchiveManifest,
  recoverArchiveBytes,
  validateArchiveReference,
} from "../src/firestore-archive";
import { FIRESTORE_CRAWLER_PARSER, firestoreObservation } from "../src/firestore-crawler";
import { normalizeObservation } from "../src/observations";

const bucket = "private-crawler-archive";
const time = { $type: "timestamp" as const, seconds: 1577836800, nanoseconds: 123456000 };
const doc: ArchivedDocument = {
  path: "crawler/existing",
  createTime: time,
  updateTime: time,
  data: {
    title: "Show",
    startTime: { $type: "timestamp", seconds: 1893456000, nanoseconds: 999999999 },
    artists: [" Nova ", "Nova"],
    isMusicEvent: true,
    ticketPrice: 0,
    venue: { $type: "reference", path: "users/venue" },
    crawlerInfo: { runId: "legacy-run" },
  },
};
function encoded(value: unknown) {
  const raw = Buffer.from(`${JSON.stringify(value)}\n`);
  const compressed = gzipSync(raw);
  const sha256 = createHash("sha256").update(compressed).digest("hex");
  const ref = {
    bucket,
    key: `archive/${sha256.slice(0, 2)}/${sha256}.gz`,
    sha256,
    bytes: compressed.length,
    contentType: "application/x-ndjson",
    contentEncoding: "gzip" as const,
  };
  return { raw, compressed, ref };
}
const blob = encoded(doc);
const entry: ArchiveEntry = { group: "crawler", count: 1, firstPath: doc.path, lastPath: doc.path, evidence: blob.ref };
function manifest(patch: Record<string, unknown> = {}, footerPatch: Record<string, unknown> = {}) {
  return Buffer.from(
    `${[
      {
        format: "tapped-scrape-import-v1",
        project: "project",
        parser: FIRESTORE_CRAWLER_PARSER,
        database: "restore_check",
        limited: false,
        ...patch,
      },
      entry,
      {
        completedAt: "2026-01-01T00:00:00Z",
        limited: false,
        totals: {
          "rawScrapeData.scanned": 0,
          "scrapeRuns.scanned": 0,
          "crawler.scanned": 1,
          "scrapeResults.scanned": 0,
        },
        ...footerPatch,
      },
    ]
      .map((row) => JSON.stringify(row))
      .join("\n")}\n`,
  );
}

test("immutable R2 object recovery validates byte count, SHA-256 and compressed content", async () => {
  assert.deepEqual(await recoverArchiveBytes(blob.compressed, blob.ref), blob.raw);
  assert.deepEqual(validateArchiveReference(blob.ref, bucket), blob.ref);
  await assert.rejects(recoverArchiveBytes(Buffer.from("tampered"), blob.ref), /checksum/);
  await assert.rejects(recoverArchiveBytes(blob.compressed, { ...blob.ref, sha256: "0".repeat(64) }), /checksum/);
  assert.throws(() => validateArchiveReference({ ...blob.ref, bucket: "other" }, bucket));
  assert.throws(() => validateArchiveReference({ ...blob.ref, key: "archive/not-content-addressed.gz" }, bucket));
  assert.throws(() => validateArchiveReference({ ...blob.ref, bytes: 41 * 1024 * 1024 }, bucket));
});
test("only complete, compatible, non-limited manifests can become import inputs", () => {
  const parsed = parseArchiveManifest(manifest(), bucket, "project");
  assert.deepEqual(parsed.counts, { rawScrapeData: 0, scrapeRuns: 0, crawler: 1, scrapeResults: 0 });
  assert.throws(() => parseArchiveManifest(manifest({ limited: true }), bucket, "project"));
  assert.throws(() => parseArchiveManifest(manifest({ project: "different" }), bucket, "project"));
  assert.throws(() => parseArchiveManifest(manifest({ parser: "unreviewed-parser" }), bucket, "project"));
  assert.throws(() => parseArchiveManifest(manifest({}, { completedAt: null }), bucket, "project"));
  assert.throws(() => parseArchiveManifest(manifest({}, { totals: { "crawler.scanned": 2 } }), bucket, "project"));
  const lines = manifest().toString().trim().split("\n");
  lines[1] = JSON.stringify({ ...entry, count: 501 });
  assert.throws(() => parseArchiveManifest(Buffer.from(lines.join("\n")), bucket, "project"));
});
test("document recovery checks collection scope, path bounds and source versions", () => {
  assert.deepEqual(parseArchivedDocuments(blob.raw, entry), [doc]);
  assert.throws(() => parseArchivedDocuments(blob.raw, { ...entry, count: 2 }));
  assert.throws(() => parseArchivedDocuments(blob.raw, { ...entry, group: "scrapeRuns" }));
  assert.throws(() => parseArchivedDocuments(blob.raw, { ...entry, lastPath: "crawler/other" }));
  assert.throws(() =>
    parseArchivedDocuments(encoded({ ...doc, updateTime: { ...time, nanoseconds: 1e9 } }).raw, entry),
  );
  assert.equal(archiveTimestampIso(time), "2020-01-01T00:00:00.123456Z");
});
test("R2 replay yields exactly the original delivery identity and normalized public facts", () => {
  const live = firestoreObservation(
    "project",
    {
      path: doc.path,
      version: `${time.seconds}:${time.nanoseconds}`,
      updatedAt: archiveTimestampIso(time),
      data: {
        title: "Show",
        startTime: { toDate: () => new Date(1893456000 * 1000 + 1000) },
        artists: [" Nova ", "Nova"],
        isMusicEvent: true,
        ticketPrice: 0,
        venue: { id: "venue", path: "users/venue" },
        crawlerInfo: { runId: "legacy-run" },
      },
    },
    1,
  );
  const replay = observationFromArchive("project", doc, 1);
  assert.deepEqual(normalizeObservation(replay), normalizeObservation(live));
  const data = decodeFirestoreArchive(doc.data) as { startTime: { toDate(): Date; toMillis(): number } };
  assert.equal(data.startTime.toDate().toISOString(), "2030-01-01T00:00:01.000Z");
  assert.equal(data.startTime.toMillis(), 1893456000999);
});
test("legacy history remains non-materializing and special values preserve quarantine semantics", () => {
  const input = observationFromArchive(
    "project",
    { ...doc, path: "rawScrapeData/missing/scrapeRuns/run/scrapeResults/result" },
    1,
  );
  assert.equal(input.materialize, false);
  assert.equal(input.venueId, "missing");
  assert.ok(input.runId?.startsWith("firestore-run-"));
  const data = decodeFirestoreArchive({
    nan: { $type: "number", value: "NaN" },
    zero: { $type: "number", value: "-0" },
    bytes: { $type: "bytes", base64: "YWJj" },
    point: { $type: "geopoint", latitude: 1, longitude: 2 },
    date: { $type: "date", iso: "2020-01-01T00:00:00Z" },
    ordinary: { $type: "custom", value: "untouched" },
  }) as Record<string, unknown>;
  assert.ok(Number.isNaN(data.nan));
  assert.ok(Object.is(data.zero, -0));
  assert.deepEqual(data.bytes, Buffer.from("abc"));
  assert.deepEqual(data.point, { latitude: 1, longitude: 2 });
  assert.deepEqual(data.date, new Date("2020-01-01T00:00:00Z"));
  assert.deepEqual(data.ordinary, { $type: "custom", value: "untouched" });
  assert.throws(() => decodeFirestoreArchive({ $type: "bytes", base64: "not valid" }));
});
