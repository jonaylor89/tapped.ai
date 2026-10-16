// Operator-only: read Firestore, archive original pages in private R2, import normalized observations.
// Never import helpers/firebase (legacy credentials). No production execution/deletion is automated.

import { appendFile, open, readFile, writeFile } from "node:fs/promises";
import { applicationDefault, initializeApp } from "firebase-admin/app";
import {
  DocumentReference,
  FieldPath,
  GeoPoint,
  getFirestore,
  type Query,
  type QueryDocumentSnapshot,
  Timestamp,
} from "firebase-admin/firestore";
import { Pool } from "pg";
import {
  type EvidenceRef,
  FIRESTORE_CRAWLER_PARSER,
  firestoreObservation,
  firestoreRunId,
  normalizeObservation,
  r2ArchiveStore,
  recordObservations,
  registerEvidence,
  timestamp,
} from "../packages/postgres-ingestion/dist";

process.umask(0o077);
const PARSER = FIRESTORE_CRAWLER_PARSER;
type Options = {
  apply: boolean;
  project: string;
  batchSize: number;
  limit?: number;
  expectDatabase?: string;
  manifest?: string;
};
function options(args: string[]): Options {
  const result: Options = { apply: false, project: "in-the-loop-306520", batchSize: 500 };
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--apply") result.apply = true;
    else if (arg === "--dry-run") result.apply = false;
    else if (["--project", "--batch-size", "--limit", "--expect-database", "--manifest"].includes(arg)) {
      const value = args[++i];
      if (!value || value.startsWith("--")) throw new Error(`Missing value for ${arg}`);
      if (arg === "--project") result.project = value;
      if (arg === "--expect-database") result.expectDatabase = value;
      if (arg === "--manifest") result.manifest = value;
      if (arg === "--batch-size" || arg === "--limit") {
        const n = Number(value);
        if (!Number.isInteger(n) || n < 1 || (arg === "--batch-size" && n > 500)) throw new Error(`Invalid ${arg}`);
        if (arg === "--batch-size") result.batchSize = n;
        else result.limit = n;
      }
    } else if (arg === "--help") {
      console.log(
        "Build @tapped/postgres-ingestion first. Usage: npx ts-node import_firestore_crawler.ts [--dry-run|--apply] [--project ID] [--batch-size 1..500] [--limit N-per-group] [--expect-database NAME] [--manifest NEW-FILE]\nDATABASE_URL is required even for read-only dry runs. --apply also requires --expect-database, --manifest, and dedicated SCRAPE_R2_ARCHIVE_* credentials plus SCRAPE_R2_ACCOUNT_ID. No Firestore writes/deletes or crawler execution.",
      );
      process.exit(0);
    } else throw new Error(`Unknown argument: ${arg}`);
  }
  if (result.apply && (!result.expectDatabase || !result.manifest))
    throw new Error("--apply requires --expect-database and a new --manifest file");
  return result;
}

// Tagged, lossless Firestore values, including nanosecond timestamps and original document paths.
function archive(value: unknown): unknown {
  if (value instanceof Timestamp) return { $type: "timestamp", seconds: value.seconds, nanoseconds: value.nanoseconds };
  if (value instanceof DocumentReference) return { $type: "reference", path: value.path };
  if (value instanceof GeoPoint) return { $type: "geopoint", latitude: value.latitude, longitude: value.longitude };
  if (Buffer.isBuffer(value)) return { $type: "bytes", base64: value.toString("base64") };
  if (value instanceof Date) return { $type: "date", iso: value.toISOString() };
  if (typeof value === "number" && !Number.isFinite(value)) return { $type: "number", value: String(value) };
  if (Object.is(value, -0)) return { $type: "number", value: "-0" };
  // This pinned Firestore SDK decodes int64 as JS numbers. Refuse an unverifiable archive rather
  // than silently rounding a large source integer; obtain a native export if this guard fires.
  if (typeof value === "number" && Number.isInteger(value) && !Number.isSafeInteger(value))
    throw Object.assign(new Error("Unsafe Firestore integer requires native archival"), {
      code: "UNSAFE_FIRESTORE_INTEGER",
    });
  if (Array.isArray(value)) return value.map(archive);
  if (value && typeof value === "object")
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, archive(v)]));
  return value;
}
function line(document: QueryDocumentSnapshot): string {
  return `${JSON.stringify({
    path: document.ref.path,
    createTime: archive(document.createTime),
    updateTime: archive(document.updateTime),
    data: archive(document.data()),
  })}\n`;
}
async function main(): Promise<void> {
  const opts = options(process.argv.slice(2));
  if (!process.env.DATABASE_URL) throw new Error("DATABASE_URL is required for database-aware validation");
  const manifestPath = opts.manifest ?? "";
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    max: 1,
    statement_timeout: 120_000,
    options: opts.apply ? undefined : "-c default_transaction_read_only=on",
  });
  const db = getFirestore(initializeApp({ projectId: opts.project, credential: applicationDefault() }));
  try {
    const database = String((await pool.query("SELECT current_database() AS name")).rows[0].name);
    if (opts.expectDatabase && database !== opts.expectDatabase)
      throw new Error("Database name does not match --expect-database");
    await pool.query("SELECT current_observation_id FROM scraped_events LIMIT 0");
    const store = opts.apply ? r2ArchiveStore() : null;
    if (opts.manifest && opts.apply) {
      const handle = await open(opts.manifest, "wx", 0o600);
      await handle.writeFile(
        `${JSON.stringify({
          format: "tapped-scrape-import-v1",
          project: opts.project,
          database,
          parser: PARSER,
          startedAt: new Date().toISOString(),
          limited: opts.limit !== undefined,
        })}\n`,
      );
      await handle.close();
    }
    const totals: Record<string, number> = {};
    async function evidence(docs: QueryDocumentSnapshot[], group: string): Promise<EvidenceRef | null> {
      if (!store) return null;
      const ref = await store.put(Buffer.from(docs.map(line).join("")), {
        retention: "archive",
        contentType: "application/x-ndjson",
      });
      // Record the verified object before writes, so a failed batch remains recoverable and auditable.
      await appendFile(
        manifestPath,
        `${JSON.stringify({
          group,
          count: docs.length,
          firstPath: docs[0].ref.path,
          lastPath: docs[docs.length - 1].ref.path,
          evidence: ref,
        })}\n`,
        { mode: 0o600 },
      );
      return ref;
    }
    async function scan(
      group: string,
      source: Query,
      visit: (docs: QueryDocumentSnapshot[]) => Promise<void>,
    ): Promise<void> {
      let cursor: QueryDocumentSnapshot | undefined;
      let scanned = 0;
      while (opts.limit === undefined || scanned < opts.limit) {
        const size = Math.min(opts.batchSize, opts.limit === undefined ? opts.batchSize : opts.limit - scanned);
        let query = source.orderBy(FieldPath.documentId()).limit(size);
        if (cursor) query = query.startAfter(cursor);
        const page = await query.get();
        if (page.empty) break;
        // Collection-group queries also find descendants of deleted parent documents.
        const docs = page.docs.filter(
          (d) => d.ref.path.split("/")[0] === (group === "crawler" ? "crawler" : "rawScrapeData"),
        );
        let chunk: QueryDocumentSnapshot[] = [];
        let bytes = 0;
        for (const doc of docs) {
          const size = Buffer.byteLength(line(doc));
          // The SDK can over-deliver a page after a streaming retry; enforce our own SQL batch cap.
          if (chunk.length && (chunk.length >= opts.batchSize || bytes + size > 16 * 1024 * 1024)) {
            await visit(chunk);
            chunk = [];
            bytes = 0;
          }
          chunk.push(doc);
          bytes += size;
        }
        if (chunk.length) await visit(chunk);
        scanned += page.size;
        cursor = page.docs[page.docs.length - 1];
        console.log(JSON.stringify({ group, scanned, mode: opts.apply ? "apply" : "dry-run", totals }));
        if (page.size < size) break;
      }
      totals[`${group}.scanned`] = scanned;
    }

    await scan("rawScrapeData", db.collection("rawScrapeData"), async (docs) => {
      const ref = await evidence(docs, "rawScrapeData");
      if (ref) await registerEvidence(pool, ref);
      // Metadata parents are archived, not copied into public venue profiles or crawler configuration.
    });
    await scan("scrapeRuns", db.collectionGroup("scrapeRuns"), async (docs) => {
      const ref = await evidence(docs, "scrapeRuns");
      const evidenceId = ref ? await registerEvidence(pool, ref) : null;
      for (const [i, doc] of docs.entries()) {
        const data = doc.data();
        const start = timestamp(data.startTime) ?? doc.createTime.toDate().toISOString();
        const candidateEnd = timestamp(data.endTime);
        const end = candidateEnd && candidateEnd >= start ? candidateEnd : null;
        if (data.endTime != null && !end) totals.invalidRunEnd = (totals.invalidRunEnd ?? 0) + 1;
        if (!opts.apply) continue;
        await pool.query(
          `INSERT INTO scrape_runs(id,scraper_id,source,legacy_id,parser_version,started_at,ended_at,error,status,evidence_id,evidence_line)
          VALUES($1,$2,'legacy-scrapers',$3,$4,$5,$6,$7,$8,$9,$10) ON CONFLICT(id) DO NOTHING`,
          [
            firestoreRunId(opts.project, doc.ref.path),
            doc.ref.path.split("/")[1],
            doc.id,
            PARSER,
            start,
            end,
            data.error == null ? null : "Legacy error; see private evidence",
            data.error != null ? "failed" : end ? "completed" : "interrupted",
            evidenceId,
            i + 1,
          ],
        );
      }
    });
    for (const group of ["crawler", "scrapeResults"]) {
      const history = group === "scrapeResults";
      await scan(group, history ? db.collectionGroup(group) : db.collection(group), async (docs) => {
        const inputs = docs.map((doc, i) =>
          firestoreObservation(
            opts.project,
            {
              path: doc.ref.path,
              version: `${doc.updateTime.seconds}:${doc.updateTime.nanoseconds}`,
              updatedAt: new Date(doc.updateTime.seconds * 1000)
                .toISOString()
                .replace(".000Z", `.${String(doc.updateTime.nanoseconds).padStart(9, "0").slice(0, 6)}Z`),
              data: doc.data(),
            },
            i + 1,
          ),
        );
        const normalized = inputs.map(normalizeObservation);
        const venues = [...new Set(inputs.flatMap((v) => (v.venueId ? [v.venueId] : [])))];
        const users = new Set(
          (await pool.query("SELECT id FROM users WHERE id=ANY($1::text[])", [venues])).rows.map((u) => u.id),
        );
        for (const item of normalized) {
          if (item.errors.length) totals.badFacts = (totals.badFacts ?? 0) + 1;
          if (!history && (!item.venueId || !users.has(item.venueId)))
            totals.unresolvedVenue = (totals.unresolvedVenue ?? 0) + 1;
        }
        if (!opts.apply) {
          if (!history) {
            const existing = new Set(
              (
                await pool.query(
                  "SELECT e.source_key FROM unnest($1::text[]) AS keys(key) JOIN scraped_events e ON e.source='event-crawler' AND e.source_key_hash=scrape_key_hash(keys.key) AND e.source_key=keys.key",
                  [inputs.map((i) => i.sourceKey)],
                )
              ).rows.map((r) => r.source_key),
            );
            for (const item of normalized.filter((i) => !i.errors.length)) {
              const key = existing.has(item.sourceKey) ? "wouldUpdate" : "wouldInsert";
              totals[key] = (totals[key] ?? 0) + 1;
            }
          }
          return;
        }
        if (history) {
          // Preserve orphaned run-result groups too, without inventing an application user.
          for (const input of inputs) {
            await pool.query(
              "INSERT INTO scrape_runs(id,scraper_id,source,legacy_id,parser_version,started_at,status) VALUES($1,$2,$3,$4,$5,$6,'interrupted') ON CONFLICT DO NOTHING",
              [input.runId, input.venueId ?? "unknown", input.source, input.legacyRunId, PARSER, input.observedAt],
            );
          }
        }
        const ref = await evidence(docs, group);
        if (!ref) throw new Error("Verified evidence is required");
        const results = await recordObservations(pool, inputs, ref);
        for (const result of results) totals[result.action] = (totals[result.action] ?? 0) + 1;
      });
    }
    const links = `SELECT b.id AS booking_id,e.event_id FROM bookings b JOIN scraped_events e ON e.source='event-crawler' AND e.source_key_hash=scrape_key_hash(b.profile#>>'{crawlerInfo,encodedLink}') AND e.source_key=b.profile#>>'{crawlerInfo,encodedLink}' AND e.venue_id=b.requester_id WHERE e.current_observation_id IS NOT NULL`;
    if (opts.apply) {
      const added = await pool.query(
        `INSERT INTO booking_imports(booking_id,event_id) ${links} ON CONFLICT DO NOTHING`,
      );
      totals.bookingLinksAdded = added.rowCount ?? 0;
      await appendFile(
        manifestPath,
        `${JSON.stringify({ completedAt: new Date().toISOString(), totals, limited: opts.limit !== undefined })}\n`,
      );
    } else {
      totals.linksCurrentlyPossible = Number(
        (
          await pool.query(
            `SELECT count(*) FROM (${links}) l LEFT JOIN booking_imports i USING(booking_id) WHERE i.booking_id IS NULL`,
          )
        ).rows[0].count,
      );
      totals.bookingsWithoutEncodedKey = Number(
        (
          await pool.query(
            "SELECT count(*) FROM bookings WHERE profile ? 'crawlerInfo' AND nullif(profile#>>'{crawlerInfo,encodedLink}','') IS NULL",
          )
        ).rows[0].count,
      );
    }
    if (store) {
      const manifestEvidence = await store.put(await readFile(manifestPath), {
        retention: "archive",
        contentType: "application/x-ndjson",
      });
      await registerEvidence(pool, manifestEvidence);
      await writeFile(`${manifestPath}.r2.json`, JSON.stringify(manifestEvidence, null, 2), {
        mode: 0o600,
        flag: "wx",
      });
      console.log(JSON.stringify({ manifestEvidence }));
    }
    console.log(JSON.stringify({ mode: opts.apply ? "apply" : "dry-run", totals }, null, 2));
  } finally {
    await pool.end();
    await db.terminate();
  }
}
main().catch((error: unknown) => {
  const code = error && typeof error === "object" && "code" in error ? String(error.code) : "IMPORT_FAILED";
  console.error(
    JSON.stringify({
      error: /^[A-Z0-9_]{1,64}$/.test(code) ? code : "IMPORT_FAILED",
      providerErrorName: error instanceof Error && /^[A-Za-z0-9_-]{1,64}$/.test(error.name) ? error.name : "unknown",
      message:
        "Crawler import failed; source data was not changed. Review configuration/private diagnostics and rerun idempotently.",
    }),
  );
  process.exitCode = 1;
});
