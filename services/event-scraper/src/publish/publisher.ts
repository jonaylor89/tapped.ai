/**
 * Publishing: the only write path from the scraper to production.
 *
 * Validated event changes are queued in the scraper schema's `publish_outbox` by reconcile. `publishOutbox` drains it
 * through a `Publisher`:
 * - `NdjsonPublisher` (dry run / standalone): appends the exact envelopes that would be sent to a local NDJSON file.
 * - `PostgresIngestionPublisher`: sends envelopes through `captureObservations` from `@tapped/postgres-ingestion`
 *   (evidence bytes to the private R2 scrape bucket first, then `record_scrape_observations` via the restricted
 *   INGESTION_DATABASE_URL role).
 *
 * Publishing failures are recorded on the outbox row (attempts/last_error) and as a `publish_failed` alert. They never
 * throw out of `publishOutbox`, so scraping is never blocked by production being unavailable.
 */
import { appendFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import {
  captureObservations,
  database,
  deliveryKey,
  type EvidenceStore,
  normalizeObservation,
  type ObservationInput,
  type ObservationResult,
  r2EvidenceStore,
} from "@tapped/postgres-ingestion";
import type { Pool } from "pg";
import {
  type Db,
  getRawPage,
  markOutboxFailed,
  markOutboxPublished,
  pendingOutbox,
  raiseAlert,
  resolveAlerts,
  sha256Hex,
  stableStringify,
} from "../db.js";
import type { EventStatus, OutboxItem, Publisher, PublishOutcome, ValidatedEvent } from "../types.js";
import { findKnownEvent } from "./known-events.js";

/** Observation namespace in production (`scrape_results.source`). Distinct from the retired "event-crawler". */
export const OBSERVATION_SOURCE = "event-scraper";
/** Bump when the envelope mapping below changes meaning. */
export const ENVELOPE_VERSION = "event-scraper-v1";
/** captureObservations accepts 1-500 envelopes per evidence object. */
export const MAX_BATCH = 500;

export type EvidenceLookup = (sha256: string) => Promise<{ bytes: Uint8Array; contentType: string | null } | null>;

// ---------------------------------------------------------------------------------------------------------------------
// Envelope mapping
// ---------------------------------------------------------------------------------------------------------------------

/** Offset (ms) of `timeZone` at `instantMs`. */
function zoneOffsetMs(instantMs: number, timeZone: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(new Date(instantMs));
  const get = (type: string) => Number(parts.find((part) => part.type === type)?.value);
  const asUtc = Date.UTC(get("year"), get("month") - 1, get("day"), get("hour"), get("minute"), get("second"));
  return asUtc - Math.floor(instantMs / 1000) * 1000;
}

/** Converts a local wall-clock "YYYY-MM-DD[THH:mm[:ss]]" in `timeZone` to a UTC ISO instant, or null if malformed. */
export function localToUtc(local: string, timeZone: string): string | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2}))?)?$/.exec(local);
  if (!m) return null;
  const wall = Date.UTC(+m[1], +m[2] - 1, +m[3], +(m[4] ?? 0), +(m[5] ?? 0), +(m[6] ?? 0));
  if (!Number.isFinite(wall)) return null;
  try {
    // Two passes settle DST transitions (the offset at the guessed instant may differ from the final one).
    let guess = wall - zoneOffsetMs(wall, timeZone);
    guess = wall - zoneOffsetMs(guess, timeZone);
    return new Date(guess).toISOString();
  } catch {
    return null;
  }
}

/** Production statuses are scheduled|canceled|postponed|unknown. Rescheduled/sold-out events still take place. */
function productionStatus(status: EventStatus): "scheduled" | "canceled" | "postponed" {
  if (status === "canceled" || status === "postponed") return status;
  return "scheduled";
}

/** Stable, source-scoped production identity of an event: our source row + reconcile identity key. */
export function observationSourceKey(item: Pick<OutboxItem, "sourceId" | "identityKey">): string {
  return `${item.sourceId}#${item.identityKey}`;
}

/**
 * The extraction payload (`data`). Prices are integer cents, so the envelope declares normalization v2 with an explicit
 * `usd_cent` input unit (never re-scaled). Non-USD currencies are passed through and held by production, not relabeled.
 */
export function observationData(item: OutboxItem): Record<string, unknown> {
  const event: ValidatedEvent = item.event;
  const startTime = event.startUtc ?? localToUtc(event.startLocal.slice(0, 10), event.timezone);
  const endTime = event.endUtc ?? null;
  const prices = event.prices.map((price) => ({
    kind: price.kind === "advance" ? "ticket" : price.kind,
    amountMinCents: price.minCents,
    amountMaxCents: price.maxCents,
    currency: price.currency,
    description: price.text ?? (price.kind === "advance" ? "advance" : null),
  }));
  if (event.isFree === true && prices.length === 0)
    prices.push({ kind: "ticket", amountMinCents: 0, amountMaxCents: 0, currency: "USD", description: "free" });
  return {
    // Facts read by production normalization.
    title: event.title,
    description: event.description,
    startTime,
    endTime,
    timezone: event.timezone,
    datePrecision: event.datePrecision,
    isMusicEvent: event.isMusic,
    status: item.change === "canceled" ? "canceled" : productionStatus(event.status),
    url: event.eventUrl,
    flierUrl: event.imageUrl,
    performers: event.performers,
    priceUnit: "usd_cent",
    prices,
    // Provenance kept with the original extraction.
    category: event.category,
    change: item.change,
    sourceStatus: event.status,
    startLocal: event.startLocal,
    endLocal: event.endLocal,
    doorsLocal: event.doorsLocal,
    ticketUrl: event.ticketUrl,
    isFree: event.isFree,
    extractor: event.extractor,
    sourceEventId: event.sourceEventId,
    sourceId: item.sourceId,
    identityKey: item.identityKey,
    evidenceQuotes: event.evidence,
    warnings: event.warnings,
    evidenceSha256: item.evidenceSha256,
  };
}

/**
 * Builds the `captureObservations` envelope for one outbox row. The delivery key is derived from content (source key,
 * capture time, change and payload) rather than the local outbox id, so a retry - or a rebuilt scraper scheme file - re-sends
 * the same delivery and production deduplicates it.
 */
export function toObservationInput(item: OutboxItem, source: string = OBSERVATION_SOURCE): ObservationInput {
  const sourceKey = observationSourceKey(item);
  const observedAt = new Date(item.observedAt).toISOString();
  const data = observationData(item);
  return {
    source,
    sourceKey,
    deliveryKey: deliveryKey(ENVELOPE_VERSION, source, sourceKey, observedAt, sha256Hex(stableStringify(data))),
    observedAt,
    parserVersion: `${ENVELOPE_VERSION}:${item.event.extractor}`.slice(0, 200),
    normalizationVersion: 2,
    inputPriceUnit: "usd_cent",
    // The venue comes from the configured source row, never from the URL's domain.
    venueRoutingStatus: item.venueId ? "resolved" : "unmatched",
    venueId: item.venueId,
    data,
  };
}

/** Short, secret-free description of an error (never raw pg/S3 messages, which may carry payloads or hosts). */
export function safeError(error: unknown): string {
  if (error && typeof error === "object") {
    const code = (error as { code?: unknown }).code;
    const name = error instanceof Error ? error.name : "Error";
    const status = (error as { $metadata?: { httpStatusCode?: unknown } }).$metadata?.httpStatusCode;
    const parts = [name];
    if (typeof code === "string" && /^[A-Za-z0-9_]{1,40}$/.test(code)) parts.push(`code=${code}`);
    if (typeof status === "number") parts.push(`http=${status}`);
    return parts.join(" ");
  }
  return "Error";
}

// ---------------------------------------------------------------------------------------------------------------------
// NDJSON (dry run)
// ---------------------------------------------------------------------------------------------------------------------

/** Writes one JSON line per outbox item: the exact envelope that would be published, plus evidence metadata. */
export class NdjsonPublisher implements Publisher {
  readonly name = "ndjson";

  constructor(
    private readonly path: string,
    private readonly source: string = OBSERVATION_SOURCE,
  ) {}

  async publish(items: OutboxItem[], evidence: EvidenceLookup): Promise<PublishOutcome[]> {
    const outcomes: PublishOutcome[] = [];
    const lines: string[] = [];
    for (const item of items) {
      try {
        const envelope = toObservationInput(item, this.source);
        normalizeObservation(envelope);
        const page = item.evidenceSha256 ? await evidence(item.evidenceSha256) : null;
        lines.push(
          JSON.stringify({
            outboxId: item.id,
            envelope,
            evidence: page
              ? { sha256: item.evidenceSha256, bytes: page.bytes.byteLength, contentType: page.contentType }
              : null,
          }),
        );
        outcomes.push({ outboxId: item.id, ok: true });
      } catch (error) {
        outcomes.push({ outboxId: item.id, ok: false, message: `invalid_envelope: ${safeError(error)}` });
      }
    }
    if (lines.length) {
      try {
        mkdirSync(dirname(this.path), { recursive: true });
        appendFileSync(this.path, `${lines.join("\n")}\n`);
      } catch (error) {
        const message = `write_failed: ${safeError(error)}`;
        return outcomes.map((outcome) => (outcome.ok ? { outboxId: outcome.outboxId, ok: false, message } : outcome));
      }
    }
    return outcomes;
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Postgres ingestion (production)
// ---------------------------------------------------------------------------------------------------------------------

export type CaptureFn = (
  pool: Pool,
  store: EvidenceStore,
  inputs: ObservationInput[],
  raw: Buffer,
  options: { retention: "archive" | "evidence"; contentType: string },
) => Promise<ObservationResult[]>;

export interface PostgresIngestionPublisherOptions {
  /** Restricted `tapped_ingestion` pool. Lazily `database()` (INGESTION_DATABASE_URL) when omitted. */
  pool?: Pool | (() => Pool);
  /** Private scrape evidence bucket. Lazily `r2EvidenceStore()` (SCRAPE_R2_*) when omitted. */
  store?: EvidenceStore | (() => EvidenceStore);
  /** Injectable for tests; defaults to `captureObservations`. */
  capture?: CaptureFn;
  source?: string;
  /**
   * Events without a venue (city listing sources) are not published: they only feed venue discovery. They are
   * reported ok with message "skipped_no_venue" so they leave the outbox.
   */
  publishVenueless?: boolean;
}

/**
 * Groups outbox items by their evidence page. Each group is one `captureObservations` call: the raw page bytes are the
 * evidence object (uploaded and verified in R2 before Postgres sees a reference). Items whose page is unavailable
 * (pruned, or none recorded) use an NDJSON evidence object of their envelopes, with `evidenceLine` set per item.
 */
export class PostgresIngestionPublisher implements Publisher {
  readonly name = "postgres-ingestion";
  private poolInstance: Pool | null = null;
  private storeInstance: EvidenceStore | null = null;

  constructor(private readonly options: PostgresIngestionPublisherOptions = {}) {}

  private pool(): Pool {
    const option = this.options.pool;
    this.poolInstance ??= typeof option === "function" ? option() : (option ?? database());
    return this.poolInstance;
  }

  private store(): EvidenceStore {
    const option = this.options.store;
    this.storeInstance ??= typeof option === "function" ? option() : (option ?? r2EvidenceStore());
    return this.storeInstance;
  }

  async publish(items: OutboxItem[], evidence: EvidenceLookup): Promise<PublishOutcome[]> {
    const capture = this.options.capture ?? (captureObservations as CaptureFn);
    const source = this.options.source ?? OBSERVATION_SOURCE;
    const outcomes = new Map<number, PublishOutcome>();
    const pageGroups = new Map<string, { item: OutboxItem; input: ObservationInput }[]>();
    const orphans: { item: OutboxItem; input: ObservationInput }[] = [];

    for (const item of items) {
      if (!item.venueId && !this.options.publishVenueless) {
        outcomes.set(item.id, { outboxId: item.id, ok: true, message: "skipped_no_venue" });
        continue;
      }
      let input: ObservationInput;
      try {
        input = toObservationInput(item, source);
        normalizeObservation(input);
      } catch (error) {
        outcomes.set(item.id, { outboxId: item.id, ok: false, message: `invalid_envelope: ${safeError(error)}` });
        continue;
      }
      const sha = item.evidenceSha256;
      if (sha && (await evidence(sha))) {
        const group = pageGroups.get(sha) ?? [];
        group.push({ item, input });
        pageGroups.set(sha, group);
      } else orphans.push({ item, input });
    }

    const send = async (
      entries: { item: OutboxItem; input: ObservationInput }[],
      raw: Buffer,
      contentType: string,
    ): Promise<void> => {
      try {
        const results = await capture(
          this.pool(),
          this.store(),
          entries.map((entry) => entry.input),
          raw,
          { retention: "evidence", contentType },
        );
        // Result rows come back in the database's processing order, not input order, so summarize per call.
        const counts = new Map<string, number>();
        for (const result of results) counts.set(result.action, (counts.get(result.action) ?? 0) + 1);
        const summary = [...counts].map(([action, count]) => `${action}=${count}`).join(",");
        for (const { item } of entries) outcomes.set(item.id, { outboxId: item.id, ok: true, message: summary });
      } catch (error) {
        const message = `capture_failed: ${safeError(error)}`;
        for (const { item } of entries) outcomes.set(item.id, { outboxId: item.id, ok: false, message });
      }
    };

    for (const [sha, entries] of pageGroups) {
      const page = await evidence(sha);
      if (!page) continue;
      for (let i = 0; i < entries.length; i += MAX_BATCH)
        await send(
          entries.slice(i, i + MAX_BATCH),
          Buffer.from(page.bytes),
          page.contentType ?? "application/octet-stream",
        );
    }
    for (let i = 0; i < orphans.length; i += MAX_BATCH) {
      const chunk = orphans.slice(i, i + MAX_BATCH).map((entry, index) => ({
        item: entry.item,
        input: { ...entry.input, evidenceLine: index + 1 },
      }));
      const raw = Buffer.from(`${chunk.map((entry) => JSON.stringify(entry.input.data)).join("\n")}\n`);
      await send(chunk, raw, "application/x-ndjson");
    }

    return items.map(
      (item) => outcomes.get(item.id) ?? { outboxId: item.id, ok: false, message: "evidence_unavailable" },
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Outbox driver
// ---------------------------------------------------------------------------------------------------------------------

export interface PublishRunOptions {
  /** Max outbox rows considered in this run. */
  limit?: number;
  /** Rows per publisher call. */
  batchSize?: number;
  /** Rows with this many failed attempts are left for a human (and alerted). */
  maxAttempts?: number;
  now?: () => number;
}

export interface PublishRunResult {
  publisher: string;
  considered: number;
  published: number;
  skipped: number;
  /** Rows dropped (marked done, never sent) because another crawler's event in production already covers them. */
  alreadyInProduction: number;
  failed: number;
  /** Failed rows that just hit maxAttempts and will no longer be retried automatically. */
  exhausted: number;
}

/**
 * Drains pending outbox rows through `publisher`. Never throws for publish problems: failures are recorded per row
 * (attempts/last_error, retried on later runs until maxAttempts) and raise one open `publish_failed` alert. A clean run
 * resolves that alert.
 */
export async function publishOutbox(
  db: Db,
  publisher: Publisher,
  options: PublishRunOptions = {},
): Promise<PublishRunResult> {
  const now = options.now ?? Date.now;
  const maxAttempts = options.maxAttempts ?? 10;
  const batchSize = Math.max(1, Math.min(options.batchSize ?? 200, 5000));
  const pending = await pendingOutbox(db, options.limit ?? 1000, maxAttempts);
  const result: PublishRunResult = {
    publisher: publisher.name,
    considered: pending.length,
    published: 0,
    skipped: 0,
    alreadyInProduction: 0,
    failed: 0,
    exhausted: 0,
  };
  // Pages may live in R2 and each is asked for more than once per run.
  const pages = new Map<string, ReturnType<EvidenceLookup>>();
  const evidence: EvidenceLookup = (sha256) => {
    let page = pages.get(sha256);
    if (!page) {
      page = getRawPage(db, sha256).then((row) => (row ? { bytes: row.bytes, contentType: row.contentType } : null));
      pages.set(sha256, page);
    }
    return page;
  };
  const failures: { outboxId: number; message: string }[] = [];

  // Queued before that event reached production: never send an event another crawler already put in production. Matches
  // of this scraper's own earlier deliveries are sent (idempotent updates of the same production event).
  const duplicates: number[] = [];
  const toSend: OutboxItem[] = [];
  for (const item of pending) {
    const known = await findKnownEvent(db, item.event);
    if (known && known.origin !== OBSERVATION_SOURCE) duplicates.push(item.id);
    else toSend.push(item);
  }
  if (duplicates.length) {
    await markOutboxPublished(db, duplicates, now());
    result.alreadyInProduction = duplicates.length;
  }

  for (let i = 0; i < toSend.length; i += batchSize) {
    const batch = toSend.slice(i, i + batchSize);
    let outcomes: PublishOutcome[];
    try {
      outcomes = await publisher.publish(batch, evidence);
    } catch (error) {
      const message = `publisher_threw: ${safeError(error)}`;
      outcomes = batch.map((item) => ({ outboxId: item.id, ok: false, message }));
    }
    const byId = new Map(outcomes.map((outcome) => [outcome.outboxId, outcome]));
    const ok: number[] = [];
    for (const item of batch) {
      const outcome = byId.get(item.id) ?? { outboxId: item.id, ok: false, message: "no_outcome" };
      if (outcome.ok) {
        ok.push(item.id);
        if (outcome.message?.startsWith("skipped")) result.skipped++;
        else result.published++;
      } else {
        const message = outcome.message ?? "publish_failed";
        await markOutboxFailed(db, item.id, message);
        result.failed++;
        if (item.attempts + 1 >= maxAttempts) result.exhausted++;
        failures.push({ outboxId: item.id, message });
      }
    }
    if (ok.length) await markOutboxPublished(db, ok, now());
  }

  if (failures.length) {
    await raiseAlert(
      db,
      {
        kind: "publish_failed",
        message: `${failures.length} outbox item(s) failed to publish via ${publisher.name}`,
        details: { publisher: publisher.name, exhausted: result.exhausted, sample: failures.slice(0, 10) },
      },
      now(),
    );
  } else if (result.considered > 0) {
    await resolveAlerts(db, { kind: "publish_failed" }, now());
  }
  return result;
}

/** Publisher selection from env. `EVENT_SCRAPER_PUBLISH=postgres` opts into production; anything else is a dry run. */
export function publisherFromEnv(env: NodeJS.ProcessEnv = process.env): Publisher {
  if (env.EVENT_SCRAPER_PUBLISH === "postgres") return new PostgresIngestionPublisher();
  const day = new Date().toISOString().slice(0, 10);
  return new NdjsonPublisher(env.EVENT_SCRAPER_DRY_RUN_PATH ?? `./data/publish/observations-${day}.ndjson`);
}
