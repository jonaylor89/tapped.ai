// Operator-only event/capture-scoped review. No Firestore client, global aliases or profile merges.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { Pool } from "pg";
import {
  type EvidenceRef,
  normalizeObservation,
  type ObservationInput,
  recordObservations,
  withFormattingV2,
  withVenueResolution,
} from "../packages/postgres-ingestion/dist";
import {
  observationFromArchive,
  parseArchiveManifest,
  validateArchiveReference,
} from "../packages/postgres-ingestion/dist/firestore-archive";
import { R2ArchiveReader } from "../packages/postgres-ingestion/dist/r2-archive-reader";

process.umask(0o077);
type Decision = {
  source: string;
  deliveryKey: string;
  eventId: string;
  preservedVenueId: string;
  sourceVenueId: string;
  proof: Record<string, unknown>;
};
type Plan = { format: string; project: string; sourceRef: EvidenceRef; policyVersion: string; decisions: Decision[] };
async function main() {
  const args = process.argv.slice(2);
  if (args.includes("--help")) {
    console.log(
      "Usage: npm run crawler:resolve-venues -- --plan <private-plan.json> --expect-database <name> [--apply] --receipt <new-file>\nDry run is default. Requires operator DATABASE_URL and private archive credentials. Only exact approved captures may materialize against preserved event venues; no profile/booking rewrites or Firestore calls.",
    );
    return;
  }
  let apply = false,
    planPath = "",
    expected = "",
    receiptPath = "";
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--apply") apply = true;
    else if (arg === "--dry-run") apply = false;
    else {
      if (!["--plan", "--expect-database", "--receipt"].includes(arg)) throw new Error("Unknown option");
      const value = args[++i];
      if (!value || value.startsWith("--")) throw new Error("Missing option value");
      if (arg === "--plan") planPath = value;
      if (arg === "--expect-database") expected = value;
      if (arg === "--receipt") receiptPath = value;
    }
  }
  if (!planPath || !expected || !receiptPath || !process.env.DATABASE_URL)
    throw new Error("Explicit plan, database, new receipt and DATABASE_URL are required");
  const rawPlan = await readFile(planPath);
  if (rawPlan.length > 10 * 1024 * 1024) throw new Error("Review plan too large");
  const plan: Plan = JSON.parse(rawPlan.toString("utf8"));
  if (
    plan.format !== "tapped-reviewed-venues-v1" ||
    plan.project !== "in-the-loop-306520" ||
    !plan.policyVersion ||
    plan.policyVersion.length > 100 ||
    !Array.isArray(plan.decisions) ||
    !plan.decisions.length ||
    plan.decisions.length > 10000
  )
    throw new Error("Invalid review plan");
  const unique = new Set<string>();
  for (const d of plan.decisions) {
    if (
      d.source !== "event-crawler" ||
      !d.deliveryKey ||
      !d.eventId ||
      !d.preservedVenueId ||
      !d.sourceVenueId ||
      d.preservedVenueId === d.sourceVenueId ||
      !d.proof ||
      typeof d.proof !== "object"
    )
      throw new Error("Invalid review decision");
    const key = JSON.stringify([d.source, d.deliveryKey]);
    if (unique.has(key)) throw new Error("Duplicate review decision");
    unique.add(key);
  }
  const reader = new R2ArchiveReader();
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    max: 1,
    options: "-c default_transaction_read_only=on",
    statement_timeout: 120000,
  });
  let inTransaction = false;
  try {
    const db = String((await pool.query("SELECT current_database() AS name")).rows[0].name);
    if (db !== expected) throw new Error("Database does not match --expect-database");
    await pool.query("SELECT venue_resolution_id FROM scrape_results LIMIT 0");
    const sourceRef = validateArchiveReference(plan.sourceRef, reader.bucket);
    const manifest = parseArchiveManifest(await reader.read(sourceRef), reader.bucket, plan.project);
    const rows = (
      await pool.query(
        `SELECT r.*,to_char(r.observed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS captured_at,
      e.venue_id AS preserved_venue_id,e.event_id AS preserved_event_id,o.bucket,o.object_key,o.sha256,o.byte_size::integer AS bytes,o.content_type,o.content_encoding,
      scrape_venue_identity_hash(r.original_venue_id) AS source_profile_hash,scrape_venue_identity_hash(e.venue_id) AS preserved_profile_hash,
      (p.venue_enabled AND NOT p.deleted AND NOT p.shadow_banned AND p.unclaimed AND s.venue_enabled AND NOT s.deleted AND NOT s.shadow_banned AND s.unclaimed
      AND NOT EXISTS(SELECT 1 FROM profile_owners x WHERE x.profile_id IN(p.id,s.id))) AS profiles_eligible
      FROM jsonb_to_recordset($1::jsonb) d(source text,"deliveryKey" text)
      JOIN scrape_results r ON r.source=d.source AND r.delivery_key=d."deliveryKey"
      JOIN scraped_events e ON e.event_id=r.event_id JOIN scrape_objects o ON o.id=r.evidence_id
      JOIN users p ON p.id=e.venue_id JOIN users s ON s.id=r.original_venue_id`,
        [JSON.stringify(plan.decisions)],
      )
    ).rows;
    if (rows.length !== plan.decisions.length) throw new Error("Review target missing");
    const byDelivery = new Map(rows.map((r) => [r.delivery_key, r]));
    const decisions = new Map(plan.decisions.map((d) => [d.deliveryKey, d]));
    const entries = new Map(manifest.entries.map((e) => [e.evidence.key, e]));
    const selected = new Map<string, (typeof manifest.entries)[number]>();
    for (const d of plan.decisions) {
      const r = byDelivery.get(d.deliveryKey);
      if (
        !r ||
        r.normalization_version !== 2 ||
        !r.materialize ||
        r.venue_resolution_id ||
        r.processing_state !== "quarantined" ||
        JSON.stringify(r.validation_errors) !== '["venue_conflict"]' ||
        r.preserved_event_id !== d.eventId ||
        r.preserved_venue_id !== d.preservedVenueId ||
        r.original_venue_id !== d.sourceVenueId ||
        !r.profiles_eligible ||
        r.source_profile_hash !== d.proof.sourceProfileSha256 ||
        r.preserved_profile_hash !== d.proof.preservedProfileSha256 ||
        d.proof.sourceRootSha256 !== sourceRef.sha256
      )
        throw new Error("Review scope/profile evidence changed");
      const entry = entries.get(r.object_key);
      if (!entry || entry.group !== "crawler" || entry.evidence.sha256 !== r.sha256)
        throw new Error("Review evidence is not in the approved snapshot");
      selected.set(r.object_key, entry);
    }
    const prepared: { input: ObservationInput; evidence: EvidenceRef; decision: Decision }[] = [];
    const targets = new Map<string, typeof rows>();
    for (const r of rows) {
      if (!targets.has(r.object_key)) targets.set(r.object_key, []);
      targets.get(r.object_key)?.push(r);
    }
    for await (const { entry, documents } of reader.documents([...selected.values()], 8)) {
      for (const row of targets.get(entry.evidence.key) ?? []) {
        const doc = documents[row.evidence_line - 1];
        if (!doc || doc.path !== `crawler/${row.source_key}`) throw new Error("Review evidence line mismatch");
        const input = withFormattingV2(observationFromArchive(plan.project, doc, row.evidence_line), "usd_major");
        const normalized = normalizeObservation(input);
        if (
          input.deliveryKey !== row.delivery_key ||
          input.sourceKey !== row.source_key ||
          input.venueId !== row.original_venue_id ||
          input.observedAt !== row.captured_at ||
          normalized.errors.length
        )
          throw new Error("Captured review identity changed");
        assert.deepEqual(
          JSON.parse(JSON.stringify(normalized.facts)),
          row.payload,
          "Captured facts do not match reviewed facts",
        );
        prepared.push({ input, evidence: entry.evidence, decision: decisions.get(row.delivery_key) as Decision });
      }
    }
    if (prepared.length !== plan.decisions.length) throw new Error("Incomplete review recovery");
    const startedAt = new Date().toISOString(),
      planSha256 = createHash("sha256").update(rawPlan).digest("hex");
    await writeFile(
      receiptPath,
      JSON.stringify(
        {
          status: "running",
          mode: apply ? "apply" : "dry-run",
          database: db,
          planSha256,
          decisions: prepared.length,
          firestoreReads: 0,
          startedAt,
        },
        null,
        2,
      ),
      { mode: 0o600, flag: "wx" },
    );
    const totals: Record<string, number> = {};
    if (apply) {
      await pool.query("BEGIN READ WRITE ISOLATION LEVEL SERIALIZABLE");
      inTransaction = true;
      const resolved: { input: ObservationInput; evidence: EvidenceRef }[] = [];
      for (const p of prepared.sort((a, b) => a.input.sourceKey.localeCompare(b.input.sourceKey))) {
        const d = p.decision;
        const id = String(
          (
            await pool.query("SELECT approve_scrape_venue_resolution($1,$2,$3,$4,$5,$6,$7::jsonb) AS id", [
              d.source,
              d.deliveryKey,
              d.eventId,
              d.preservedVenueId,
              d.sourceVenueId,
              plan.policyVersion,
              JSON.stringify(d.proof),
            ])
          ).rows[0].id,
        );
        resolved.push({ input: withVenueResolution(p.input, id), evidence: p.evidence });
      }
      const groups = new Map<string, typeof resolved>();
      for (const r of resolved) {
        if (!groups.has(r.evidence.key)) groups.set(r.evidence.key, []);
        groups.get(r.evidence.key)?.push(r);
      }
      for (const batch of groups.values())
        for (let i = 0; i < batch.length; i += 500) {
          const chunk = batch.slice(i, i + 500);
          for (const r of await recordObservations(
            pool,
            chunk.map((x) => x.input),
            chunk[0].evidence,
          )) {
            if (r.action !== "updated" && r.action !== "duplicate")
              throw new Error("Reviewed capture did not preserve/materialize its anchored event");
            totals[r.action] = (totals[r.action] ?? 0) + 1;
          }
        }
      const links = await pool.query(
        `INSERT INTO booking_imports(booking_id,event_id)
        SELECT b.id,e.event_id FROM bookings b JOIN scraped_events e ON e.source='event-crawler'
        AND e.source_key_hash=scrape_key_hash(b.profile#>>'{crawlerInfo,encodedLink}') AND e.source_key=b.profile#>>'{crawlerInfo,encodedLink}'
        AND e.venue_id=b.requester_id WHERE e.event_id=ANY($1::text[]) AND e.current_observation_id IS NOT NULL ON CONFLICT DO NOTHING`,
        [plan.decisions.map((d) => d.eventId)],
      );
      totals.bookingLinksAdded = links.rowCount ?? 0;
      await pool.query("COMMIT");
      inTransaction = false;
    } else totals.wouldResolve = prepared.length;
    const receipt = {
      status: "completed",
      mode: apply ? "apply" : "dry-run",
      database: db,
      planSha256,
      policyVersion: plan.policyVersion,
      sourceRef,
      decisions: prepared.length,
      totals,
      evidenceObjectsRecovered: selected.size,
      archiveBytes: reader.compressedBytes,
      originalSourceVenuesRetained: true,
      profilesMerged: 0,
      nativeBookingsRewritten: 0,
      firestoreReads: 0,
      startedAt,
      completedAt: new Date().toISOString(),
    };
    await writeFile(receiptPath, JSON.stringify(receipt, null, 2), { mode: 0o600 });
    console.log(JSON.stringify(receipt, null, 2));
  } finally {
    if (inTransaction) await pool.query("ROLLBACK");
    reader.close();
    await pool.end();
  }
}
main().catch((e: unknown) => {
  const code = e && typeof e === "object" && "code" in e ? String(e.code) : "VENUE_REVIEW_FAILED";
  console.error(
    JSON.stringify({
      error: /^[A-Z0-9_]{1,64}$/.test(code) ? code : "VENUE_REVIEW_FAILED",
      providerErrorName: e instanceof Error ? e.name : "unknown",
      inspectPrivateReceipt: true,
      firestoreReads: 0,
    }),
  );
  process.exitCode = 1;
});
