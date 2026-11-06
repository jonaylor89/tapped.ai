/**
 * PROVE IT: a candidate is promoted only when the normal extraction + validation pipeline yields at least
 * `minEvents` (default 3) valid upcoming events from a source on its own website. Otherwise it goes to
 * `no_source` and is retried after `retryAfterMs` (default 30 days).
 *
 * Promotion never creates production venue profiles; it marks the candidate `promoted` for human review (see
 * export.ts). Proof (sample events, extractor, evidence page sha256) is stored on the candidate.
 */
import {
  all,
  type Db,
  dueCandidates,
  getCandidate,
  getVenue,
  normalizeName,
  putRawPage,
  updateCandidate,
} from "../db.js";
import { isTicketingUrl } from "../denylist.js";
import { type ExtractionResult, extractEvents, pageFromFetch } from "../extract/index.js";
import { FetchBlockedError, FetchError } from "../fetch.js";
import type {
  Candidate,
  CandidateStatus,
  Clock,
  ExtractContext,
  ExtractedEvent,
  Extractor,
  FetchResult,
  HttpClient,
  LlmClient,
  Page,
  Source,
  SourceKind,
  ValidatedEvent,
} from "../types.js";
import { systemClock } from "../types.js";
import { type ValidateContext, type ValidateManyResult, validateEvents } from "../validate/index.js";
import { dateOf, isValidTimeZone, localDate } from "../validate/time.js";
import { distanceOrNull } from "./geo.js";
import { compareNames } from "./names.js";
import { type IdentityOptions, resolveCandidate } from "./resolve.js";
import { findEventSources, type SourceFinderResult, type SourceProposal } from "./source-finder.js";

export const DEFAULT_MIN_PROVEN_EVENTS = 3;
export const DEFAULT_RETRY_AFTER_MS = 30 * 24 * 60 * 60 * 1000;
/** A candidate stuck in "proving" (crash mid-run) becomes due again after this. */
export const PROVING_LEASE_MS = 60 * 60 * 1000;

export interface ProveOptions {
  http: HttpClient;
  llm?: LlmClient | null;
  /** Extractor tried when no structured extractor yields events (e.g. the LLM extractor). */
  fallback?: Extractor | null;
  minEvents?: number;
  retryAfterMs?: number;
  /** Proposals actually fetched and extracted. Default 3. */
  maxProposals?: number;
  /** Used when neither the candidate nor its matched venue has a timezone. */
  defaultTimezone?: string | null;
  clock?: Clock;
  /** Injectable pipeline pieces (default: the real extract/validate modules). */
  extract?: (
    page: Page,
    ctx: ExtractContext,
  ) => Promise<Pick<ExtractionResult, "events" | "page" | "extractor"> & Partial<Pick<ExtractionResult, "errors">>>;
  validate?: (events: ExtractedEvent[], ctx: ValidateContext) => Pick<ValidateManyResult, "valid" | "rejected">;
  findSources?: (venue: { name: string; website: string | null }) => Promise<SourceFinderResult>;
}

export interface ProveAttempt {
  url: string;
  kind: SourceKind;
  via: SourceProposal["via"];
  /** Where events were actually found (an endpoint the page linked to, possibly). */
  provenUrl: string | null;
  provenKind: SourceKind | null;
  extractor: string | null;
  extracted: number;
  /** Extracted events whose structured location names another place; never counted toward the proof. */
  elsewhere: number;
  /** Sample of those other locations, for reviewers. */
  elsewhereLocations: string[];
  valid: number;
  upcoming: number;
  rejectedReasons: string[];
  error: string | null;
}

export interface ProveResult {
  candidateId: number;
  status: CandidateStatus;
  reason: string;
  attempts: ProveAttempt[];
  upcoming: number;
}

const KIND_BY_EXTRACTOR: Record<string, SourceKind> = {
  ical: "ical",
  wp_tribe: "wp_tribe",
  squarespace: "squarespace",
};

function defaultExtract(options: ProveOptions) {
  return async (page: Page, ctx: ExtractContext) => extractEvents(page, ctx, { fallback: options.fallback ?? null });
}

/** Upcoming = not canceled and starting today or later in the venue's timezone. */
export function isUpcoming(event: ValidatedEvent, now: Date): boolean {
  if (event.status === "canceled") return false;
  if (event.startUtc) return Date.parse(event.startUtc) >= now.getTime() - 6 * 60 * 60 * 1000;
  return dateOf(event.startLocal) >= localDate(now, event.timezone);
}

/** Max distance between an event's structured geo and the candidate for it to count as "here". */
/** True when an event carries evidence of being a performance, beyond the default-to-music fallback. */
export function hasPerformanceSignal(event: ValidatedEvent): boolean {
  if (!event.warnings.includes("category_default")) return true;
  return event.performers.length > 0 || event.doorsLocal != null;
}

export const LOCATION_MATCH_METERS = 150;

function streetOf(address: string | null): string | null {
  const first = address?.split(",")[0]?.trim();
  return first && /\d/.test(first) && /[a-z]/i.test(first) ? normalizeName(first) : null;
}

/**
 * Does an extracted event's structured location point at the candidate? "unknown" when the event carries no location
 * (it still counts: venue pages rarely repeat their own address). A location matches by name (same/similar), by the
 * candidate's street address appearing in it, or by coordinates within LOCATION_MATCH_METERS; otherwise the event
 * happens somewhere else (a parent site's other rooms or sister venues) and must not prove this candidate.
 */
export function locationMatch(
  location: ExtractedEvent["location"],
  candidate: Pick<Candidate, "name" | "address" | "lat" | "lng">,
): "match" | "unknown" | "elsewhere" {
  if (!location) return "unknown";
  const name = location.name?.trim() || null;
  const address = location.address?.trim() || null;
  const hasGeo = location.lat != null && location.lng != null;
  if (!name && !address && !hasGeo) return "unknown";
  if (name && compareNames(name, candidate.name) !== "different") return "match";
  const street = streetOf(candidate.address);
  const haystack = normalizeName(`${name ?? ""} ${address ?? ""}`);
  if (street && haystack.includes(street)) return "match";
  if (hasGeo) {
    const distance = distanceOrNull({ lat: location.lat, lng: location.lng }, candidate);
    if (distance != null) return distance <= LOCATION_MATCH_METERS ? "match" : "elsewhere";
  }
  return "elsewhere";
}

function errorMessage(error: unknown): string {
  if (error instanceof FetchBlockedError) return `blocked_${error.reason}`;
  if (error instanceof FetchError) return `fetch_error_${error.code}`;
  return (error instanceof Error ? error.message : String(error)).slice(0, 200);
}

async function candidateTimezone(
  db: Db,
  candidate: Candidate,
  fallback: string | null | undefined,
): Promise<string | null> {
  const venueTz = candidate.matchedVenueId ? (await getVenue(db, candidate.matchedVenueId))?.timezone : null;
  for (const tz of [candidate.timezone, venueTz, fallback]) if (tz && isValidTimeZone(tz)) return tz;
  return null;
}

async function sharedSourceCandidates(db: Db, candidateId: number, url: string): Promise<number[]> {
  const rows = await all(
    db,
    "SELECT id FROM venue_candidates WHERE source_url=? AND id<>? ORDER BY id",
    url,
    candidateId,
  );
  return rows.map((row) => Number(row.id));
}

/**
 * Finds and proves an event source for one candidate. The candidate is marked `proving` (with a lease in
 * next_attempt_at) during network work, then `promoted` or `no_source`.
 */
export async function proveCandidate(db: Db, candidateId: number, options: ProveOptions): Promise<ProveResult> {
  const clock = options.clock ?? systemClock;
  const minEvents = options.minEvents ?? DEFAULT_MIN_PROVEN_EVENTS;
  const retryAfterMs = options.retryAfterMs ?? DEFAULT_RETRY_AFTER_MS;
  const start = clock.now();
  const candidate = await getCandidate(db, candidateId);
  if (!candidate) throw new Error(`Unknown candidate ${candidateId}`);

  const finish = async (
    status: CandidateStatus,
    reason: string,
    attempts: ProveAttempt[],
    upcoming: number,
    extra = {},
  ) => {
    const at = clock.now().getTime();
    const current = (await getCandidate(db, candidateId)) as Candidate;
    await updateCandidate(
      db,
      candidateId,
      {
        status,
        statusReason: reason,
        nextAttemptAt: status === "no_source" ? at + retryAfterMs : null,
        provenEventCount: upcoming,
        evidence: {
          ...current.evidence,
          proof: { at, minEvents, upcoming, attempts, ...extra },
        },
      },
      at,
    );
    return { candidateId, status, reason, attempts, upcoming };
  };

  const timezone = await candidateTimezone(db, candidate, options.defaultTimezone);
  await updateCandidate(
    db,
    candidateId,
    { status: "proving", attempts: candidate.attempts + 1, nextAttemptAt: start.getTime() + PROVING_LEASE_MS },
    start.getTime(),
  );
  if (!timezone) return finish("no_source", "missing_timezone", [], 0);

  const find =
    options.findSources ?? (async (venue) => findEventSources(venue, { http: options.http, llm: options.llm }));
  let found: SourceFinderResult;
  try {
    found = await find({ name: candidate.name, website: candidate.website });
  } catch (error) {
    return finish("no_source", `source_finder_failed: ${errorMessage(error)}`, [], 0);
  }
  if (!found.ok || !found.proposals.length) return finish("no_source", found.reason ?? "no_proposals", [], 0);

  const extract = options.extract ?? defaultExtract(options);
  const validate = options.validate ?? validateEvents;
  const attempts: ProveAttempt[] = [];
  let best: { attempt: ProveAttempt; events: ValidatedEvent[]; page: Page } | null = null;

  for (const proposal of found.proposals.slice(0, options.maxProposals ?? 3)) {
    const attempt: ProveAttempt = {
      url: proposal.url,
      kind: proposal.kind,
      via: proposal.via,
      provenUrl: null,
      provenKind: null,
      extractor: null,
      extracted: 0,
      elsewhere: 0,
      elsewhereLocations: [],
      valid: 0,
      upcoming: 0,
      rejectedReasons: [],
      error: null,
    };
    attempts.push(attempt);
    if (isTicketingUrl(proposal.url)) {
      attempt.error = "ticketing_url";
      continue;
    }
    const source: Source = {
      id: `candidate:${candidateId}`,
      venueId: candidate.matchedVenueId,
      kind: proposal.kind,
      url: proposal.url,
      timezone,
      enabled: false,
      label: candidate.name,
      origin: "discovery",
      fetchIntervalMs: 0,
      createdAt: start.getTime(),
      updatedAt: start.getTime(),
    };
    try {
      const fetched: FetchResult = await options.http.get({
        url: proposal.url,
        accept: proposal.kind === "ical" ? "text/calendar, text/plain;q=0.8, */*;q=0.5" : undefined,
      });
      if (fetched.status < 200 || fetched.status >= 300) {
        attempt.error = `http_${fetched.status}`;
        continue;
      }
      const page = pageFromFetch(fetched);
      const now = clock.now();
      const ctx: ExtractContext = {
        source,
        venue: null,
        timezone,
        now,
        llm: options.llm ?? undefined,
        http: options.http,
      };
      const extraction = await extract(page, ctx);
      const evidencePage = extraction.page ?? page;
      attempt.extractor = extraction.extractor;
      attempt.extracted = extraction.events.length;
      if (extraction.errors?.length)
        attempt.error = extraction.errors.map((e) => `${e.extractor}: ${e.message}`.slice(0, 300)).join("; ");
      const followed = evidencePage.finalUrl !== page.finalUrl || evidencePage.url !== page.url;
      attempt.provenUrl = followed ? evidencePage.url : proposal.url;
      attempt.provenKind = followed
        ? (KIND_BY_EXTRACTOR[extraction.extractor ?? ""] ?? "html")
        : proposal.kind === "html" && extraction.extractor && KIND_BY_EXTRACTOR[extraction.extractor]
          ? (KIND_BY_EXTRACTOR[extraction.extractor] as SourceKind)
          : proposal.kind;
      // Only events that happen at this candidate prove it (a hotel or restaurant group's shared /events page
      // lists other rooms and sister venues).
      const here: ExtractedEvent[] = [];
      for (const event of extraction.events) {
        if (locationMatch(event.location ?? null, candidate) === "elsewhere") {
          attempt.elsewhere++;
          const label = [event.location?.name, event.location?.address].filter(Boolean).join(", ");
          if (label && attempt.elsewhereLocations.length < 5 && !attempt.elsewhereLocations.includes(label))
            attempt.elsewhereLocations.push(label);
        } else here.push(event);
      }
      const validated = validate(here, {
        source: { ...source, url: attempt.provenUrl, kind: attempt.provenKind } as Source,
        venue: null,
        timezone,
        now,
        pageText: evidencePage.text,
        pageContentType: evidencePage.contentType,
        pageUrl: evidencePage.finalUrl || evidencePage.url,
      });
      // Only events with a positive signal prove a source: a category keyword/structured type, listed performers or a
      // doors time. Defaulted-to-music events (no signal at all) do not, so parks, museums and restaurants with busy
      // calendars are not promoted as music venues.
      const upcoming = validated.valid.filter((event) => isUpcoming(event, now) && hasPerformanceSignal(event));
      attempt.valid = validated.valid.length;
      attempt.upcoming = upcoming.length;
      attempt.rejectedReasons = [...new Set(validated.rejected.flatMap((r) => r.reasons))].slice(0, 10);
      if (!best || upcoming.length > best.events.length) best = { attempt, events: upcoming, page: evidencePage };
      if (upcoming.length >= minEvents) break;
    } catch (error) {
      attempt.error = errorMessage(error);
    }
  }

  if (!best || best.events.length < minEvents) {
    const count = best?.events.length ?? 0;
    return finish("no_source", `insufficient_events:${count}/${minEvents}`, attempts, count);
  }

  const { attempt, events, page } = best;
  const sha = await putRawPage(
    db,
    { url: page.finalUrl || page.url, contentType: page.contentType, bytes: page.body },
    clock.now().getTime(),
  );
  const sourceUrl = attempt.provenUrl ?? attempt.url;
  const sourceKind = attempt.provenKind ?? attempt.kind;
  await updateCandidate(db, candidateId, { sourceUrl, sourceKind, timezone }, clock.now().getTime());
  return finish("promoted", `proven:${events.length}_upcoming_events`, attempts, events.length, {
    sourceUrl,
    sourceKind,
    extractor: attempt.extractor,
    evidenceSha256: sha,
    sharedSourceWith: await sharedSourceCandidates(db, candidateId, sourceUrl),
    sample: events.slice(0, 10).map((event) => ({
      title: event.title,
      startLocal: event.startLocal,
      category: event.category,
      eventUrl: event.eventUrl,
      ticketUrl: event.ticketUrl,
      evidence: event.evidence.slice(0, 2),
    })),
  });
}

export interface DiscoveryStepOptions extends ProveOptions, IdentityOptions {
  /** Max candidates resolved / proved per call. Default 20 each. */
  limit?: number;
}

export interface DiscoveryStepSummary {
  resolved: number;
  proved: ProveResult[];
}

/**
 * One pass of the slow discovery loop: resolve `new` candidates, then prove due `resolved` / `no_source`
 * candidates (and `proving` ones whose lease expired). Candidates in review are left alone.
 */
export async function runCandidatePipeline(db: Db, options: DiscoveryStepOptions): Promise<DiscoveryStepSummary> {
  const clock = options.clock ?? systemClock;
  const limit = options.limit ?? 20;
  const now = clock.now().getTime();
  let resolved = 0;
  for (const candidate of await dueCandidates(db, ["new"], now, limit)) {
    await resolveCandidate(db, candidate.id, { ...options, now });
    resolved++;
  }
  const proved: ProveResult[] = [];
  for (const candidate of await dueCandidates(db, ["resolved", "no_source", "proving"], clock.now().getTime(), limit)) {
    proved.push(await proveCandidate(db, candidate.id, options));
  }
  return { resolved, proved };
}
