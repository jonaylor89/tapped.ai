import {
  type Db,
  enqueueOutbox,
  eventContentHash,
  getEventByIdentity,
  getFetchState,
  listSourceEvents,
  raiseAlert,
  recordEventChange,
  resolveAlerts,
  saveFetchState,
  setEventMissCount,
  setEventStatus,
  transaction,
  upsertEvent,
} from "../db.js";
import { findKnownEvent } from "../publish/known-events.js";
import type { Alert, ChangeKind, Source, StoredEvent, ValidatedEvent } from "../types.js";
import { addDays, dateOf, localDate } from "../validate/time.js";
import { identityBase } from "./identity.js";

/**
 * Reconciles one successful fetch of a source against its stored snapshot (SQLite).
 *
 * - new identity                         -> "new"
 * - known identity, content changed      -> "updated"
 * - known identity, same content         -> "unchanged" (miss counter reset, last_seen bumped)
 * - previously canceled identity is back -> "reappeared"
 * - the site itself says canceled        -> "canceled" immediately
 * - id/URL event moved to another time on the same day -> "updated" under its stored identity
 * - stored upcoming event missing        -> miss_count + 1; "canceled" once it reaches `cancelAfterMisses` (default 2)
 *   consecutive SUCCESSFUL fetches. Events later than the last event seen in this fetch are not counted as missing
 *   (the page may only show a window, e.g. "this month"). Past events are never canceled; they become "past".
 * - zero events from a source that produced events before -> a "zero_results" alert and NO misses/cancellations.
 *
 * Only call this after a successful fetch with a parsed body. 304 Not Modified / failed fetches must not reconcile.
 * Changes other than "unchanged" are recorded in event_changes and queued in the publish outbox (unless disabled).
 */

export interface ReconcileOptions {
  source: Pick<Source, "id" | "timezone" | "venueId">;
  events: ValidatedEvent[];
  /** Fetch time. */
  now: Date;
  /** sha256 of the raw page stored in raw_pages, used as publish evidence. */
  evidenceSha256?: string | null;
  /** Default 2. */
  cancelAfterMisses?: number;
  /** Events that started up to this many days ago are still "upcoming" (matches validation). Default 1. */
  pastGraceDays?: number;
  /** Queue observations in publish_outbox. Default true. */
  enqueue?: boolean;
  /**
   * Drop new events that production Postgres already has (`known_events`, see publish/known-events.ts): they are not
   * stored, reconciled or published. Default true.
   */
  skipKnown?: boolean;
  /** Update consecutiveZeroResults / lastEventCount / maxEventCount in fetch_state. Default true. */
  updateFetchState?: boolean;
}

export interface ReconcileChange {
  kind: ChangeKind;
  eventId: number;
  identityKey: string;
  outboxId: number | null;
}

export interface ReconcileResult {
  changes: ReconcileChange[];
  counts: Record<ChangeKind, number> & {
    missed: number;
    expired: number;
    outsideWindow: number;
    /** New events dropped because production already has them. */
    alreadyInProduction: number;
  };
  zeroResults: boolean;
  alert: Alert | null;
}

function emptyCounts(): ReconcileResult["counts"] {
  return {
    new: 0,
    updated: 0,
    unchanged: 0,
    canceled: 0,
    reappeared: 0,
    missed: 0,
    expired: 0,
    outsideWindow: 0,
    alreadyInProduction: 0,
  };
}

/** True when the stored event's local date is before `today - graceDays` in its timezone. */
function isPast(event: StoredEvent, today: string, graceDays: number): boolean {
  return dateOf(event.startLocal) < addDays(today, -graceDays);
}

/**
 * Has the event already started? Instant precision when known. Date-only events count as started from the start of
 * their local date: venues often drop today's show from the listing during the day, which is not a cancellation.
 */
export function hasStarted(event: Pick<StoredEvent, "startUtc" | "startLocal">, now: Date, today: string): boolean {
  if (event.startUtc) return Date.parse(event.startUtc) <= now.getTime();
  return dateOf(event.startLocal) <= today;
}

/**
 * Same-day time change of an id/URL event (identity keys carry the start time): when exactly one unmatched stored
 * event and exactly one unmatched incoming event share the key without its time, the incoming event keeps the stored
 * key, so the change is an "updated" (same production identity) instead of a new event plus a later cancellation.
 */
function adoptMovedTimes(db: Db, sourceId: string, incoming: Map<string, ValidatedEvent>): Map<string, ValidatedEvent> {
  const unmatchedIncoming = new Map<string, string[]>();
  for (const [key, event] of incoming) {
    const base = identityBase(key);
    if (!base || getEventByIdentity(db, sourceId, key)) continue;
    unmatchedIncoming.set(base, [...(unmatchedIncoming.get(base) ?? []), event.identityKey]);
  }
  if (!unmatchedIncoming.size) return incoming;
  const unmatchedStored = new Map<string, StoredEvent[]>();
  for (const stored of listSourceEvents(db, sourceId, ["active", "canceled"])) {
    const base = identityBase(stored.identityKey);
    if (!base || !unmatchedIncoming.has(base) || incoming.has(stored.identityKey)) continue;
    unmatchedStored.set(base, [...(unmatchedStored.get(base) ?? []), stored]);
  }
  const renames = new Map<string, string>();
  for (const [base, keys] of unmatchedIncoming) {
    const stored = unmatchedStored.get(base);
    if (keys.length === 1 && stored?.length === 1)
      renames.set(keys[0] as string, (stored[0] as StoredEvent).identityKey);
  }
  if (!renames.size) return incoming;
  const out = new Map<string, ValidatedEvent>();
  for (const [key, event] of incoming) {
    const renamed = renames.get(key);
    out.set(renamed ?? key, renamed ? { ...event, identityKey: renamed } : event);
  }
  return out;
}

export function reconcileSource(db: Db, options: ReconcileOptions): ReconcileResult {
  const { source, now } = options;
  const nowMs = now.getTime();
  const cancelAfter = Math.max(1, options.cancelAfterMisses ?? 2);
  const grace = options.pastGraceDays ?? 1;
  const enqueue = options.enqueue ?? true;
  const skipKnown = options.skipKnown ?? true;
  const today = localDate(now, source.timezone);
  const result: ReconcileResult = { changes: [], counts: emptyCounts(), zeroResults: false, alert: null };

  return transaction(db, () => {
    // 1. Age out past events first so they are never treated as missing.
    for (const stored of listSourceEvents(db, source.id, ["active", "canceled"])) {
      const tz = stored.data?.timezone || source.timezone;
      if (isPast(stored, localDate(now, tz), grace)) {
        setEventStatus(db, stored.id, "past", nowMs);
        result.counts.expired++;
      }
    }

    // 2. Incoming, de-duplicated by identity (first wins).
    let incoming = new Map<string, ValidatedEvent>();
    for (const event of options.events) if (!incoming.has(event.identityKey)) incoming.set(event.identityKey, event);
    incoming = adoptMovedTimes(db, source.id, incoming);

    const state = getFetchState(db, source.id);
    const active = listSourceEvents(db, source.id, ["active"]);
    const productiveBefore = state.maxEventCount > 0 || (state.lastEventCount ?? 0) > 0 || active.length > 0;

    // 3. Zero results on a productive source: alert, never cancel.
    if (incoming.size === 0) {
      result.zeroResults = true;
      if (options.updateFetchState ?? true) {
        saveFetchState(db, source.id, { consecutiveZeroResults: state.consecutiveZeroResults + 1, lastEventCount: 0 });
      }
      if (productiveBefore) {
        result.alert = raiseAlert(
          db,
          {
            kind: "zero_results",
            sourceId: source.id,
            message: `Source ${source.id} returned no events (previously ${state.maxEventCount || active.length})`,
            details: {
              activeEvents: active.length,
              maxEventCount: state.maxEventCount,
              consecutiveZeroResults: state.consecutiveZeroResults + 1,
            },
          },
          nowMs,
        );
      }
      return result;
    }

    const push = (
      kind: ChangeKind,
      stored: StoredEvent,
      before: ValidatedEvent | null,
      after: ValidatedEvent | null,
    ) => {
      result.counts[kind]++;
      let outboxId: number | null = null;
      if (kind !== "unchanged") {
        recordEventChange(db, {
          eventId: stored.id,
          sourceId: stored.sourceId,
          identityKey: stored.identityKey,
          change: kind,
          before,
          after,
          at: nowMs,
        });
        if (enqueue && after) {
          outboxId = enqueueOutbox(
            db,
            {
              eventId: stored.id,
              change: kind,
              event: after,
              observedAt: nowMs,
              evidenceSha256: options.evidenceSha256 ?? null,
            },
            nowMs,
          );
        }
      }
      result.changes.push({ kind, eventId: stored.id, identityKey: stored.identityKey, outboxId });
    };

    // 4. Upsert everything seen.
    for (const event of incoming.values()) {
      const existing = getEventByIdentity(db, source.id, event.identityKey);
      const siteCanceled = event.status === "canceled";
      if (!existing && skipKnown && findKnownEvent(db, event)) {
        result.counts.alreadyInProduction++;
        continue;
      }
      if (!existing) {
        const stored = upsertEvent(db, event, {
          status: siteCanceled ? "canceled" : "active",
          now: nowMs,
          changed: true,
        });
        push("new", stored, null, event);
        continue;
      }
      if (existing.status === "past") {
        // Still listed after its date (validation grace); refresh silently.
        upsertEvent(db, event, { status: "past", now: nowMs });
        continue;
      }
      const changed = existing.contentHash !== eventContentHash(event);
      if (siteCanceled) {
        const stored = upsertEvent(db, event, { status: "canceled", now: nowMs, changed });
        if (existing.status === "canceled") push(changed ? "updated" : "unchanged", stored, existing.data, event);
        else push("canceled", stored, existing.data, event);
        continue;
      }
      if (existing.status === "canceled") {
        const stored = upsertEvent(db, event, { status: "active", now: nowMs, changed: true });
        push("reappeared", stored, existing.data, event);
        continue;
      }
      const stored = upsertEvent(db, event, { status: "active", now: nowMs, changed });
      push(changed ? "updated" : "unchanged", stored, existing.data, event);
    }

    // 5. Missing events: only upcoming ones inside the window this fetch covered.
    let windowEnd = "";
    for (const event of incoming.values())
      if (dateOf(event.startLocal) > windowEnd) windowEnd = dateOf(event.startLocal);
    for (const stored of active) {
      if (incoming.has(stored.identityKey)) continue;
      if (hasStarted(stored, now, today)) continue;
      if (dateOf(stored.startLocal) > windowEnd) {
        result.counts.outsideWindow++;
        continue;
      }
      const misses = stored.missCount + 1;
      result.counts.missed++;
      if (misses < cancelAfter) {
        setEventMissCount(db, stored.id, misses);
        continue;
      }
      setEventMissCount(db, stored.id, misses);
      setEventStatus(db, stored.id, "canceled", nowMs);
      const canceledEvent: ValidatedEvent = {
        ...stored.data,
        status: "canceled",
        warnings: [...(stored.data.warnings ?? []).filter((w) => w !== "missing_from_source"), "missing_from_source"],
      };
      push("canceled", { ...stored, status: "canceled" }, stored.data, canceledEvent);
    }

    // 6. Bookkeeping.
    if (options.updateFetchState ?? true) {
      saveFetchState(db, source.id, {
        consecutiveZeroResults: 0,
        lastEventCount: incoming.size,
        maxEventCount: Math.max(state.maxEventCount, incoming.size),
      });
    }
    resolveAlerts(db, { kind: "zero_results", sourceId: source.id }, nowMs);
    return result;
  });
}
