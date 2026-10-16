// Operator-only immutable snapshot import. Deliberately NO Firebase SDK, ADC or Firestore client.
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { Pool } from "pg";
import {
  FIRESTORE_CRAWLER_PARSER,
  firestoreRunId,
  normalizeObservation,
  record,
  recordObservations,
  registerEvidence,
  timestamp,
} from "../packages/postgres-ingestion/dist";
import {
  type ArchiveGroup,
  decodeFirestoreArchive,
  observationFromArchive,
  parseArchiveManifest,
  validateArchiveReference,
} from "../packages/postgres-ingestion/dist/firestore-archive";
import { R2ArchiveReader } from "../packages/postgres-ingestion/dist/r2-archive-reader";

process.umask(0o077);
type Options = {
  apply: boolean;
  manifestRef: string;
  expectDatabase: string;
  project: string;
  concurrency: number;
  receipt?: string;
};
function options(args: string[]): Options {
  const o: Options = {
    apply: false,
    manifestRef: "",
    expectDatabase: "",
    project: "in-the-loop-306520",
    concurrency: 4,
  };
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--apply") o.apply = true;
    else if (arg === "--dry-run") o.apply = false;
    else if (["--manifest-ref", "--expect-database", "--project", "--concurrency", "--receipt"].includes(arg)) {
      const value = args[++i];
      if (!value || value.startsWith("--")) throw new Error("Missing option value");
      if (arg === "--manifest-ref") o.manifestRef = value;
      if (arg === "--expect-database") o.expectDatabase = value;
      if (arg === "--project") o.project = value;
      if (arg === "--receipt") o.receipt = value;
      if (arg === "--concurrency") o.concurrency = Number(value);
    } else if (arg === "--help") {
      console.log(
        "Usage: npm run crawler:import-r2 -- --manifest-ref <complete-manifest.ndjson.r2.json> --expect-database <name> [--dry-run|--apply --receipt <new-file>] [--concurrency 1..8] [--project ID]\nReads the completed immutable R2 snapshot only. ZERO Firestore calls. Dry run is default; DATABASE_URL and dedicated SCRAPE_R2_ARCHIVE_* credentials are required. --concurrency only bounds object prefetch; database writes stay sequential in batches <=500.",
      );
      process.exit(0);
    } else throw new Error("Unknown option");
  }
  if (!o.manifestRef || !o.expectDatabase || (o.apply && !o.receipt))
    throw new Error("Manifest reference, explicit database and apply receipt are required");
  if (!Number.isInteger(o.concurrency) || o.concurrency < 1 || o.concurrency > 8)
    throw new Error("Concurrency must be 1..8");
  return o;
}
async function main(): Promise<void> {
  const opts = options(process.argv.slice(2));
  if (!process.env.DATABASE_URL) throw new Error("DATABASE_URL is required");
  const reader = new R2ArchiveReader();
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    max: 1,
    statement_timeout: 120_000,
    options: opts.apply ? undefined : "-c default_transaction_read_only=on",
  });
  const startedAt = new Date().toISOString();
  try {
    const database = String((await pool.query("SELECT current_database() AS name")).rows[0].name);
    if (database !== opts.expectDatabase) throw new Error("Database name does not match --expect-database");
    await pool.query("SELECT current_observation_id FROM scraped_events LIMIT 0");
    const sourceRef = validateArchiveReference(JSON.parse(await readFile(opts.manifestRef, "utf8")), reader.bucket);
    const manifest = parseArchiveManifest(await reader.read(sourceRef), reader.bucket, opts.project);
    if (opts.receipt)
      await writeFile(
        opts.receipt,
        JSON.stringify(
          {
            status: "running",
            source: "r2",
            sourceRef,
            project: opts.project,
            database,
            mode: opts.apply ? "apply" : "dry-run",
            firestoreReads: 0,
            startedAt,
          },
          null,
          2,
        ),
        { mode: 0o600, flag: "wx" },
      );
    // Manifest roots are intentional registry-only archive objects, not orphan candidates.
    if (opts.apply) await registerEvidence(pool, sourceRef);
    const totals: Record<string, number> = {};
    const seen = new Set<string>();
    const digests: Partial<Record<ArchiveGroup, ReturnType<typeof createHash>>> = {};
    for (const group of ["rawScrapeData", "scrapeRuns", "crawler", "scrapeResults"] as const) {
      digests[group] = createHash("sha256");
      let scanned = 0;
      for await (const { entry, documents } of reader.documents(
        manifest.entries.filter((e) => e.group === group),
        opts.concurrency,
      )) {
        for (const doc of documents) {
          // Store fixed-size hashes, not slices that could retain entire decoded snapshot buffers.
          const pathHash = createHash("sha256").update(doc.path).digest("hex");
          if (seen.has(pathHash)) throw new Error("Duplicate source document in snapshot");
          seen.add(pathHash);
          digests[group]?.update(`${JSON.stringify([doc.path, doc.updateTime.seconds, doc.updateTime.nanoseconds])}\n`);
        }
        if (group === "rawScrapeData") {
          if (opts.apply) await registerEvidence(pool, entry.evidence);
        } else if (group === "scrapeRuns") {
          const evidenceId = opts.apply ? await registerEvidence(pool, entry.evidence) : null;
          for (const [i, doc] of documents.entries()) {
            const data = record(decodeFirestoreArchive(doc.data));
            const start = timestamp(data.startTime) ?? timestamp(decodeFirestoreArchive(doc.createTime));
            const candidateEnd = timestamp(data.endTime);
            const end = start && candidateEnd && candidateEnd >= start ? candidateEnd : null;
            if (!start) throw new Error("Invalid archived run creation timestamp");
            if (data.endTime != null && !end) totals.invalidRunEnd = (totals.invalidRunEnd ?? 0) + 1;
            if (opts.apply)
              await pool.query(
                `INSERT INTO scrape_runs(id,scraper_id,source,legacy_id,parser_version,started_at,ended_at,error,status,evidence_id,evidence_line)
              VALUES($1,$2,'legacy-scrapers',$3,$4,$5,$6,$7,$8,$9,$10) ON CONFLICT(id) DO NOTHING`,
                [
                  firestoreRunId(opts.project, doc.path),
                  doc.path.split("/")[1],
                  doc.path.split("/").slice(-1)[0],
                  FIRESTORE_CRAWLER_PARSER,
                  start,
                  end,
                  data.error == null ? null : "Legacy error; see private evidence",
                  data.error != null ? "failed" : end ? "completed" : "interrupted",
                  evidenceId,
                  i + 1,
                ],
              );
          }
        } else {
          const inputs = documents.map((doc, i) => observationFromArchive(opts.project, doc, i + 1));
          const normalized = inputs.map(normalizeObservation);
          for (const item of normalized) {
            if (item.errors.length) totals.badFacts = (totals.badFacts ?? 0) + 1;
          }
          if (!opts.apply) {
            if (group === "crawler") {
              const keys = inputs.map((item) => item.sourceKey);
              const existing = new Set(
                (
                  await pool.query(
                    "SELECT e.source_key FROM unnest($1::text[]) AS keys(key) JOIN scraped_events e ON e.source='event-crawler' AND e.source_key_hash=scrape_key_hash(keys.key) AND e.source_key=keys.key",
                    [keys],
                  )
                ).rows.map((r) => r.source_key),
              );
              const venues = [...new Set(normalized.flatMap((item) => (item.venueId ? [item.venueId] : [])))];
              const users = new Set(
                (await pool.query("SELECT id FROM users WHERE id=ANY($1::text[])", [venues])).rows.map((r) => r.id),
              );
              for (const item of normalized) {
                if (!item.venueId || !users.has(item.venueId))
                  totals.unresolvedVenue = (totals.unresolvedVenue ?? 0) + 1;
                if (!item.errors.length) {
                  const action = existing.has(item.sourceKey) ? "wouldUpdate" : "wouldInsert";
                  totals[action] = (totals[action] ?? 0) + 1;
                }
              }
            }
          } else {
            if (group === "scrapeResults") {
              const runs = [
                ...new Map(
                  inputs.map((item) => [
                    item.runId,
                    {
                      id: item.runId,
                      scraper_id: item.venueId ?? "unknown",
                      legacy_id: item.legacyRunId,
                      started_at: item.observedAt,
                    },
                  ]),
                ).values(),
              ];
              await pool.query(
                `INSERT INTO scrape_runs(id,scraper_id,source,legacy_id,parser_version,started_at,status)
                SELECT r.id,r.scraper_id,'legacy-scrapers',r.legacy_id,$2,r.started_at,'interrupted'
                FROM jsonb_to_recordset($1::jsonb) AS r(id text,scraper_id text,legacy_id text,started_at timestamptz) ON CONFLICT DO NOTHING`,
                [JSON.stringify(runs), FIRESTORE_CRAWLER_PARSER],
              );
            }
            for (const result of await recordObservations(pool, inputs, entry.evidence))
              totals[result.action] = (totals[result.action] ?? 0) + 1;
          }
        }
        scanned += documents.length;
        if (scanned % 5000 === 0 || scanned === manifest.counts[group])
          console.log(
            JSON.stringify({ source: "r2", firestoreReads: 0, group, scanned, total: manifest.counts[group], totals }),
          );
      }
      if (scanned !== manifest.counts[group]) throw new Error("Snapshot count mismatch");
      totals[`${group}.scanned`] = scanned;
    }
    if (opts.apply) {
      const links = await pool.query(`INSERT INTO booking_imports(booking_id,event_id)
        SELECT b.id,e.event_id FROM bookings b JOIN scraped_events e ON e.source='event-crawler'
        AND e.source_key_hash=scrape_key_hash(b.profile#>>'{crawlerInfo,encodedLink}') AND e.source_key=b.profile#>>'{crawlerInfo,encodedLink}'
        AND e.venue_id=b.requester_id WHERE e.current_observation_id IS NOT NULL ON CONFLICT DO NOTHING`);
      totals.bookingLinksAdded = links.rowCount ?? 0;
    }
    const receipt = {
      status: "completed",
      source: "r2",
      firestoreReads: 0,
      sourceRef,
      project: opts.project,
      database,
      mode: opts.apply ? "apply" : "dry-run",
      startedAt,
      completedAt: new Date().toISOString(),
      totals,
      archiveRecovery: {
        allObjectsRecovered: true,
        rootManifestRecovered: true,
        sourceObjects: manifest.entries.length,
        documents: seen.size,
        groups: manifest.counts,
        compressedBytes: reader.compressedBytes,
        sourceVersionDigests: Object.fromEntries(
          Object.entries(digests).map(([key, hash]) => [key, hash?.digest("hex")]),
        ),
      },
    };
    if (opts.receipt) await writeFile(opts.receipt, JSON.stringify(receipt, null, 2), { mode: 0o600 });
    console.log(JSON.stringify(receipt, null, 2));
  } finally {
    reader.close();
    await pool.end();
  }
}
main().catch((error: unknown) => {
  const code = error && typeof error === "object" && "code" in error ? String(error.code) : "ARCHIVE_IMPORT_FAILED";
  console.error(
    JSON.stringify({
      error: /^[A-Z0-9_]{1,64}$/.test(code) ? code : "ARCHIVE_IMPORT_FAILED",
      providerErrorName: error instanceof Error && /^[A-Za-z0-9_-]{1,64}$/.test(error.name) ? error.name : "unknown",
      source: "r2",
      firestoreReads: 0,
      message:
        "Archive import failed; original R2 objects and Firestore were not modified. Review the private receipt/log and retry idempotently.",
    }),
  );
  process.exitCode = 1;
});
