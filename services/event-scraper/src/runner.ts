/**
 * The scrape loop. Every enabled source has exactly one pending `fetch_source` job in the SQLite queue (dedupe key
 * `fetch_source:<sourceId>`); a worker leases it, runs fetch -> extract -> validate -> reconcile, then schedules the
 * next fetch with an adaptive delay:
 *   - events changed (new/updated/canceled/reappeared): `productiveIntervalMs` (default ~daily)
 *   - 304 / identical bytes / nothing changed / zero events: exponential backoff from the productive interval up to
 *     `maxIntervalMs` (default 7 days)
 *   - fetch failures: 1h, 2h, 4h ... capped at 24h (alert after 3 in a row)
 *   - robots.txt disallow: retry weekly (alert); ticketing / private-host URLs: source disabled (alert)
 * Reconcile runs only after a successful fetch whose body was parsed without extractor errors, so a broken fetch or
 * parser never cancels events.
 */

import {
  claimJob,
  consumeCounter,
  countJobs,
  type Db,
  enqueueJob,
  extendLease,
  finishJob,
  getFetchState,
  getSource,
  getVenue,
  listSources,
  putRawPage,
  raiseAlert,
  resolveAlerts,
  saveFetchState,
  setSourceEnabled,
  sha256Hex,
} from "./db.js";
import { isTicketingUrl } from "./denylist.js";
import { type ExtractionResult, extractEvents, pageFromFetch } from "./extract/index.js";
import { FetchBlockedError, FetchError } from "./fetch.js";
import { LlmError } from "./llm/openai.js";
import { extractEventsWithLlm, LLM_EXTRACTOR_NAME, type LlmExtractOptions } from "./llm/prompt.js";
import { looksLikeEventListing } from "./llm/text.js";
import { type PublishRunResult, publishOutbox } from "./publish/publisher.js";
import { type ReconcileResult, reconcileSource } from "./reconcile/reconcile.js";
import type {
  Clock,
  ExtractContext,
  Extractor,
  FetchResult,
  HttpClient,
  Job,
  LlmClient,
  Page,
  Publisher,
  Source,
  SourceKind,
} from "./types.js";
import { systemClock } from "./types.js";
import { validateEvents } from "./validate/validate.js";

export const FETCH_JOB = "fetch_source";
export const HOUR_MS = 60 * 60 * 1000;
export const DAY_MS = 24 * HOUR_MS;

export type Logger = (event: string, data?: Record<string, unknown>) => void;
export const silentLogger: Logger = () => {};

export interface FetchJobPayload {
  sourceId: string;
  /** Consecutive runs whose content or events did not change. Drives the backoff. */
  unchangedStreak?: number;
  /**
   * True when the previous extraction used only the source page's own bytes. Then identical bytes mean identical
   * events and extraction can be skipped; when endpoints were followed (or TEC paginated) we must re-extract.
   */
  selfContained?: boolean;
}

export interface RunnerDeps {
  db: Db;
  http: HttpClient;
  /** LLM fallback; null/undefined disables it. */
  llm?: LlmClient | null;
  clock?: Clock;
  log?: Logger;
}

export interface RunnerOptions {
  maxJobs?: number;
  concurrency?: number;
  /** Default 24h. */
  productiveIntervalMs?: number;
  /** Default 7 days. */
  maxIntervalMs?: number;
  /** Lease per fetch job. Default 15 min; renewed every third of it while the job runs (politeness waits). */
  leaseMs?: number;
  /**
   * LLM cost cap: pages sent to the LLM per UTC day, counted in SQLite so every run, loop tick and process on this
   * database shares it. Default 50.
   */
  llmMaxPages?: number;
  /** Queue reconcile changes in the publish outbox. Default true; false when publishing is off (standalone). */
  enqueueOutbox?: boolean;
  llmOptions?: LlmExtractOptions;
  /** Zero-event fetches before alerting on a never-productive source. Default 3. */
  failureAlertAfter?: number;
}

export type SourceOutcome =
  | "extracted"
  | "not_modified"
  | "unchanged_bytes"
  | "http_error"
  | "fetch_failed"
  | "robots_blocked"
  | "disabled"
  | "extract_failed"
  | "lease_lost";

export interface SourceRunResult {
  sourceId: string;
  url: string;
  outcome: SourceOutcome;
  status: number | null;
  extractor: string | null;
  extracted: number;
  valid: number;
  rejected: number;
  rejectedReasons: Record<string, number>;
  reconcile: ReconcileResult["counts"] | null;
  zeroResults: boolean;
  evidenceSha256: string | null;
  /** Delay until the next fetch (null when the source was disabled). */
  nextDelayMs: number | null;
  /** Scheduling state carried into the next job's payload (null keeps the previous one). */
  next: Omit<FetchJobPayload, "sourceId"> | null;
  message?: string;
}

export interface RunSummary {
  scheduled: number;
  processed: number;
  results: SourceRunResult[];
  totals: {
    extracted: number;
    valid: number;
    new: number;
    updated: number;
    canceled: number;
    failed: number;
  };
  llmPages: number;
}

// ---------------------------------------------------------------------------------------------------------------------
// LLM fallback extractor
// ---------------------------------------------------------------------------------------------------------------------

/** Page budget for the LLM fallback. `tryConsume` reserves one page; false means the cap is reached. */
export interface LlmBudget {
  tryConsume(): boolean;
}

export const LLM_PAGES_KEY_PREFIX = "llm_pages:";

/**
 * Daily LLM page cap shared through SQLite (`kv` counter per UTC day), so it holds across runOnce calls, `loop`
 * ticks, discovery proving and separate processes on the same database.
 */
export function dailyLlmBudget(db: Db, maxPerDay: number, clock: Clock = systemClock): LlmBudget {
  return {
    tryConsume() {
      const now = clock.now();
      return consumeCounter(db, `${LLM_PAGES_KEY_PREFIX}${now.toISOString().slice(0, 10)}`, maxPerDay, now.getTime());
    },
  };
}

/**
 * Wraps `extractEventsWithLlm` as the fallback Extractor. Pages are charged to `budget` (default: an in-memory cap of
 * `maxPages` for this extractor instance only; the runner and CLI pass the shared daily SQLite budget).
 */
export function createLlmExtractor(
  options: { maxPages?: number; llm?: LlmExtractOptions; budget?: LlmBudget } = {},
): Extractor & {
  pagesUsed(): number;
} {
  let used = 0;
  const max = options.maxPages ?? 50;
  let exhausted = false;
  const budget: LlmBudget = options.budget ?? { tryConsume: () => used < max };
  return {
    name: LLM_EXTRACTOR_NAME,
    pagesUsed: () => used,
    canHandle(page: Page, ctx: ExtractContext) {
      if (!ctx.llm || exhausted) return false;
      const type = (page.contentType ?? "").toLowerCase();
      if (/calendar|json|xml|pdf|image|octet-stream/.test(type)) return false;
      if (page.text.trim().length === 0) return false;
      // Only spend LLM pages on pages that look like an event listing (several distinct dates).
      return looksLikeEventListing(page.text, page.contentType);
    },
    async extract(page: Page, ctx: ExtractContext) {
      if (!budget.tryConsume()) {
        exhausted = true;
        return [];
      }
      used++;
      try {
        return (await extractEventsWithLlm(page, ctx, options.llm)).events;
      } catch (error) {
        // A bad key or quota problem fails every call: stop spending pages on it for the rest of this process.
        if (error instanceof LlmError && (error.status === 401 || error.status === 403 || error.status === 429))
          exhausted = true;
        throw error;
      }
    },
  };
}

// ---------------------------------------------------------------------------------------------------------------------
// Scheduling
// ---------------------------------------------------------------------------------------------------------------------

export function fetchJobKey(sourceId: string): string {
  return `${FETCH_JOB}:${sourceId}`;
}

const ACCEPT_BY_KIND: Partial<Record<SourceKind, string>> = {
  ical: "text/calendar, text/plain;q=0.8, */*;q=0.5",
  wp_tribe: "application/json",
  squarespace: "application/json",
};

/** Small deterministic spread (0..10%) so sources added together do not stay in lockstep. */
function jitter(sourceId: string, delayMs: number): number {
  const n = Number.parseInt(sha256Hex(sourceId).slice(0, 6), 16) / 0xffffff;
  return Math.round(delayMs * 0.1 * n);
}

/**
 * Makes sure every enabled source has a pending fetch job. Sources fetched before start at
 * `lastFetchAt + fetchIntervalMs`; new sources start now. Existing pending jobs (and their backoff) are kept.
 */
export function scheduleSources(db: Db, now: number): number {
  const before = countJobs(db, { kind: FETCH_JOB });
  for (const source of listSources(db, { enabled: true })) {
    const state = getFetchState(db, source.id);
    const runAfter = state.lastFetchAt == null ? now : Math.max(now, state.lastFetchAt + source.fetchIntervalMs);
    enqueueJob<FetchJobPayload>(
      db,
      FETCH_JOB,
      { sourceId: source.id },
      { dedupeKey: fetchJobKey(source.id), runAfter, now, maxAttempts: 1_000_000 },
    );
  }
  return countJobs(db, { kind: FETCH_JOB }) - before;
}

/** Next delay from the outcome. Exported for tests. */
export function nextDelay(
  kind: "productive" | "unchanged" | "failure" | "robots",
  streakOrFailures: number,
  options: { productiveIntervalMs: number; maxIntervalMs: number },
): number {
  switch (kind) {
    case "productive":
      return Math.min(options.productiveIntervalMs, options.maxIntervalMs);
    case "unchanged":
      return Math.min(
        options.productiveIntervalMs * 2 ** Math.max(0, Math.min(streakOrFailures, 16)),
        options.maxIntervalMs,
      );
    case "failure":
      return Math.min(HOUR_MS * 2 ** Math.max(0, Math.min(streakOrFailures - 1, 16)), DAY_MS);
    case "robots":
      return 7 * DAY_MS;
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// One source
// ---------------------------------------------------------------------------------------------------------------------

function errorText(error: unknown): string {
  if (error instanceof FetchBlockedError) return `blocked_${error.reason}`;
  if (error instanceof FetchError) return `fetch_error_${error.code}`;
  return (error instanceof Error ? error.message : String(error)).slice(0, 300);
}

function emptyResult(source: Source, outcome: SourceOutcome): SourceRunResult {
  return {
    sourceId: source.id,
    url: source.url,
    outcome,
    status: null,
    extractor: null,
    extracted: 0,
    valid: 0,
    rejected: 0,
    rejectedReasons: {},
    reconcile: null,
    zeroResults: false,
    evidenceSha256: null,
    nextDelayMs: null,
    next: null,
  };
}

export interface ProcessContext {
  deps: RunnerDeps;
  options: Required<Pick<RunnerOptions, "productiveIntervalMs" | "maxIntervalMs" | "failureAlertAfter">> &
    Pick<RunnerOptions, "enqueueOutbox">;
  fallback: Extractor | null;
  payload: FetchJobPayload;
  /**
   * Renews the job's lease and reports whether this worker still holds it. Checked right before reconcile: if
   * another worker reclaimed the job, this result must not touch the snapshot (one fetch, one observation).
   */
  holdsLease?: () => boolean;
}

/** Fetches, extracts, validates and reconciles one source. Returns the outcome and the next delay. */
export async function processSource(source: Source, pc: ProcessContext): Promise<SourceRunResult> {
  const { db, http } = pc.deps;
  const clock = pc.deps.clock ?? systemClock;
  const log = pc.deps.log ?? silentLogger;
  const opts = pc.options;
  const startedAt = clock.now().getTime();
  const result = emptyResult(source, "extracted");

  const disable = (kind: "ticketing_blocked" | "other", message: string): SourceRunResult => {
    setSourceEnabled(db, source.id, false, startedAt);
    raiseAlert(db, { kind, sourceId: source.id, message, details: { url: source.url } }, startedAt);
    saveFetchState(db, source.id, { lastFetchAt: startedAt, lastError: message });
    log("source_disabled", { sourceId: source.id, reason: message });
    return { ...result, outcome: "disabled", message, nextDelayMs: null };
  };

  const failure = (outcome: SourceOutcome, message: string, status: number | null): SourceRunResult => {
    const state = getFetchState(db, source.id);
    const failures = state.consecutiveFailures + 1;
    saveFetchState(db, source.id, {
      lastFetchAt: startedAt,
      lastStatus: status,
      lastError: message,
      consecutiveFailures: failures,
    });
    if (failures >= opts.failureAlertAfter) {
      raiseAlert(
        db,
        { kind: "fetch_failed", sourceId: source.id, message, details: { url: source.url, failures, status } },
        startedAt,
      );
    }
    return { ...result, outcome, status, message, nextDelayMs: nextDelay("failure", failures, opts) };
  };

  if (isTicketingUrl(source.url)) return disable("ticketing_blocked", "ticketing platform URL; never fetched");

  const state = getFetchState(db, source.id);
  let fetched: FetchResult;
  try {
    fetched = await http.get({
      url: source.url,
      etag: state.etag,
      lastModified: state.lastModified,
      accept: ACCEPT_BY_KIND[source.kind],
    });
  } catch (error) {
    if (error instanceof FetchBlockedError) {
      if (error.reason === "ticketing") return disable("ticketing_blocked", `redirected to ticketing platform`);
      if (error.reason === "scheme" || error.reason === "private_host")
        return disable("other", `blocked_${error.reason}`);
      // robots.txt disallows us: respect it, tell a human, and look again in a week.
      saveFetchState(db, source.id, { lastFetchAt: startedAt, lastError: "robots_disallowed" });
      raiseAlert(
        db,
        { kind: "robots_blocked", sourceId: source.id, message: "robots.txt disallows this URL", details: {} },
        startedAt,
      );
      return {
        ...result,
        outcome: "robots_blocked",
        message: "robots_disallowed",
        nextDelayMs: nextDelay("robots", 0, opts),
      };
    }
    return failure("fetch_failed", errorText(error), null);
  }
  result.status = fetched.status;

  const success = {
    lastFetchAt: startedAt,
    lastSuccessAt: startedAt,
    lastStatus: fetched.status,
    lastError: null,
    consecutiveFailures: 0,
    successfulFetches: state.successfulFetches + 1,
  };
  resolveAlerts(db, { kind: "fetch_failed", sourceId: source.id }, startedAt);
  resolveAlerts(db, { kind: "robots_blocked", sourceId: source.id }, startedAt);

  const streak = pc.payload.unchangedStreak ?? 0;
  if (fetched.notModified) {
    saveFetchState(db, source.id, success);
    return {
      ...result,
      outcome: "not_modified",
      nextDelayMs: nextDelay("unchanged", streak + 1, opts),
      next: { ...pc.payload, unchangedStreak: streak + 1 },
    };
  }
  if (fetched.status < 200 || fetched.status >= 300) {
    return failure("http_error", `HTTP ${fetched.status}`, fetched.status);
  }

  const sourceSha = putRawPage(
    db,
    { sha256: fetched.sha256, url: fetched.finalUrl, contentType: fetched.contentType, bytes: fetched.body },
    startedAt,
  );
  const validators = { etag: fetched.etag, lastModified: fetched.lastModified, contentHash: sourceSha };
  if (state.contentHash === sourceSha && pc.payload.selfContained) {
    saveFetchState(db, source.id, { ...success, ...validators });
    return {
      ...result,
      outcome: "unchanged_bytes",
      evidenceSha256: sourceSha,
      nextDelayMs: nextDelay("unchanged", streak + 1, opts),
      next: { ...pc.payload, unchangedStreak: streak + 1 },
    };
  }

  const now = clock.now();
  const venue = source.venueId ? getVenue(db, source.venueId) : null;
  const ctx: ExtractContext = {
    source,
    venue,
    timezone: source.timezone,
    now,
    llm: pc.deps.llm ?? undefined,
    http,
  };
  const page = pageFromFetch(fetched);
  let extraction: ExtractionResult;
  try {
    extraction = await extractEvents(page, ctx, { fallback: pc.fallback });
  } catch (error) {
    saveFetchState(db, source.id, { ...success, ...validators, lastError: `extract: ${errorText(error)}` });
    raiseAlert(db, { kind: "extract_failed", sourceId: source.id, message: errorText(error) }, startedAt);
    return {
      ...result,
      outcome: "extract_failed",
      message: errorText(error),
      nextDelayMs: nextDelay("failure", 1, opts),
    };
  }
  result.extractor = extraction.extractor;
  result.extracted = extraction.events.length;
  const selfContained = !extraction.followed.length && extraction.extractor !== "wp_tribe";

  // An extractor crashed and nothing else produced events: do not let a parser bug look like "all events removed".
  if (!extraction.events.length && extraction.errors.length) {
    const message = extraction.errors
      .map((e) => `${e.extractor}: ${e.message}`)
      .join("; ")
      .slice(0, 500);
    saveFetchState(db, source.id, { ...success, ...validators, contentHash: null, lastError: `extract: ${message}` });
    raiseAlert(
      db,
      { kind: "extract_failed", sourceId: source.id, message, details: { errors: extraction.errors } },
      startedAt,
    );
    return { ...result, outcome: "extract_failed", message, nextDelayMs: nextDelay("failure", 1, opts) };
  }
  resolveAlerts(db, { kind: "extract_failed", sourceId: source.id }, startedAt);

  const evidencePage = extraction.page;
  const evidenceSha =
    evidencePage === page
      ? sourceSha
      : putRawPage(
          db,
          {
            url: evidencePage.finalUrl || evidencePage.url,
            contentType: evidencePage.contentType,
            bytes: evidencePage.body,
          },
          startedAt,
        );
  result.evidenceSha256 = evidenceSha;

  const validated = validateEvents(extraction.events, {
    source,
    venue,
    timezone: source.timezone,
    now,
    pageText: evidencePage.text,
    pageContentType: evidencePage.contentType,
    pageUrl: evidencePage.finalUrl || evidencePage.url,
  });
  result.valid = validated.valid.length;
  result.rejected = validated.rejected.length;
  for (const rejection of validated.rejected) {
    for (const reason of rejection.reasons) {
      const key = reason.split(":")[0] ?? reason;
      result.rejectedReasons[key] = (result.rejectedReasons[key] ?? 0) + 1;
    }
  }

  if (pc.holdsLease && !pc.holdsLease()) {
    log("lease_lost", { sourceId: source.id });
    return { ...result, outcome: "lease_lost", message: "lease lost before reconcile", nextDelayMs: null };
  }
  const reconciled = reconcileSource(db, {
    source,
    events: validated.valid,
    now,
    evidenceSha256: evidenceSha,
    enqueue: opts.enqueueOutbox ?? true,
  });
  result.reconcile = reconciled.counts;
  result.zeroResults = reconciled.zeroResults;
  saveFetchState(db, source.id, {
    ...success,
    ...validators,
    lastExtractor: extraction.extractor ?? state.lastExtractor,
  });

  const c = reconciled.counts;
  const changed = c.new + c.updated + c.canceled + c.reappeared > 0;
  const productive = validated.valid.length > 0 && changed;
  const nextStreak = productive ? 0 : streak + 1;
  log("source_done", {
    sourceId: source.id,
    extractor: extraction.extractor,
    extracted: result.extracted,
    valid: result.valid,
    new: c.new,
    updated: c.updated,
    canceled: c.canceled,
  });
  return {
    ...result,
    outcome: "extracted",
    nextDelayMs: productive ? nextDelay("productive", 0, opts) : nextDelay("unchanged", nextStreak, opts),
    next: { unchangedStreak: nextStreak, selfContained },
  };
}

// ---------------------------------------------------------------------------------------------------------------------
// run-once / loop
// ---------------------------------------------------------------------------------------------------------------------

function nextPayload(previous: FetchJobPayload, result: SourceRunResult): FetchJobPayload {
  return { ...previous, ...(result.next ?? {}), sourceId: previous.sourceId };
}

/**
 * Leases due fetch jobs (after making sure every enabled source has one) and processes them with `concurrency`
 * workers. Each processed source gets its next job scheduled with the adaptive delay.
 */
export async function runOnce(deps: RunnerDeps, options: RunnerOptions = {}): Promise<RunSummary> {
  const { db } = deps;
  const clock = deps.clock ?? systemClock;
  const log = deps.log ?? silentLogger;
  const maxJobs = options.maxJobs ?? 200;
  const leaseMs = options.leaseMs ?? 15 * 60 * 1000;
  const fallback = deps.llm
    ? createLlmExtractor({
        llm: options.llmOptions,
        budget: dailyLlmBudget(db, options.llmMaxPages ?? 300, clock),
      })
    : null;
  const pcOptions = {
    productiveIntervalMs: options.productiveIntervalMs ?? DAY_MS,
    maxIntervalMs: options.maxIntervalMs ?? 7 * DAY_MS,
    failureAlertAfter: options.failureAlertAfter ?? 3,
    enqueueOutbox: options.enqueueOutbox ?? true,
  };
  const summary: RunSummary = {
    scheduled: scheduleSources(db, clock.now().getTime()),
    processed: 0,
    results: [],
    totals: { extracted: 0, valid: 0, new: 0, updated: 0, canceled: 0, failed: 0 },
    llmPages: 0,
  };

  let claimed = 0;
  const worker = async () => {
    while (claimed < maxJobs) {
      const job = claimJob<FetchJobPayload>(db, { kinds: [FETCH_JOB], leaseMs, now: clock.now().getTime() });
      if (!job) return;
      claimed++;
      await runJob(job);
    }
  };

  const runJob = async (job: Job<FetchJobPayload>) => {
    const token = job.leaseToken as string;
    const source = getSource(db, job.payload.sourceId);
    if (!source || !source.enabled) {
      finishJob(db, job.id, token, clock.now().getTime());
      return;
    }
    // Keep the lease alive while the job runs: politeness waits (Crawl-delay, Retry-After) can exceed the lease.
    let leaseLost = false;
    const renew = () => {
      if (!leaseLost && !extendLease(db, job.id, token, leaseMs, clock.now().getTime())) leaseLost = true;
      return !leaseLost;
    };
    const heartbeat = setInterval(renew, Math.max(1_000, Math.floor(leaseMs / 3)));
    heartbeat.unref?.();
    let result: SourceRunResult;
    try {
      result = await processSource(source, {
        deps,
        options: pcOptions,
        fallback,
        payload: job.payload,
        holdsLease: renew,
      });
    } catch (error) {
      // Unexpected bug: record it, keep the source on a failure backoff instead of losing its schedule.
      log("source_error", { sourceId: source.id, error: errorText(error) });
      result = { ...emptyResult(source, "fetch_failed"), message: errorText(error), nextDelayMs: 6 * HOUR_MS };
      raiseAlert(
        db,
        { kind: "other", sourceId: source.id, message: `runner: ${errorText(error)}` },
        clock.now().getTime(),
      );
    }
    clearInterval(heartbeat);
    const at = clock.now().getTime();
    // Lease lost: another worker owns this source's job now and schedules it; do not enqueue a second one.
    const finished = finishJob(db, job.id, token, at);
    if (finished && result.nextDelayMs != null) {
      enqueueJob<FetchJobPayload>(db, FETCH_JOB, nextPayload(job.payload, result), {
        dedupeKey: fetchJobKey(source.id),
        runAfter: at + result.nextDelayMs + jitter(source.id, result.nextDelayMs),
        maxAttempts: 1_000_000,
        now: at,
      });
    }
    summary.processed++;
    summary.results.push(result);
    summary.totals.extracted += result.extracted;
    summary.totals.valid += result.valid;
    summary.totals.new += result.reconcile?.new ?? 0;
    summary.totals.updated += result.reconcile?.updated ?? 0;
    summary.totals.canceled += result.reconcile?.canceled ?? 0;
    if (["fetch_failed", "http_error", "extract_failed"].includes(result.outcome)) summary.totals.failed++;
  };

  const workers = Math.max(1, options.concurrency ?? 4);
  await Promise.all(Array.from({ length: workers }, () => worker()));
  summary.llmPages = fallback?.pagesUsed() ?? 0;
  summary.results.sort((a, b) => a.sourceId.localeCompare(b.sourceId));
  return summary;
}

/** Drains the outbox through `publisher` (no-op summary when publishing is off). */
export async function runPublish(
  db: Db,
  publisher: Publisher | null,
  clock: Clock = systemClock,
): Promise<PublishRunResult | null> {
  if (!publisher) return null;
  return publishOutbox(db, publisher, { now: () => clock.now().getTime() });
}
