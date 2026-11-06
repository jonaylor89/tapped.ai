/**
 * Structured extraction, cheapest first:
 *   ical -> wp_tribe (JSON) -> squarespace (JSON) -> aeg (JSON) -> rhp -> jsonld -> microdata
 * The first extractor that yields events wins. JSON-LD and microdata come from the same HTML, so when JSON-LD wins
 * microdata is still consulted and events it alone has are merged in (duplicates collapse, JSON-LD fields win).
 * When an HTML page yields nothing and `ctx.http` is available, calendar endpoints advertised by the page on the
 * venue's own site (or a public Google Calendar) are fetched and extracted instead. Ticketing URLs are never followed.
 */
import { isTicketingUrl } from "../denylist.js";
import type { ExtractContext, ExtractedEvent, Extractor, FetchResult, Page } from "../types.js";
import { aegExtractor } from "./aeg.js";
import { discoverStructuredEndpoints, type StructuredEndpoint } from "./endpoints.js";
import { icalExtractor } from "./ical.js";
import { jsonLdExtractor } from "./jsonld.js";
import { microdataExtractor } from "./microdata.js";
import { rhpExtractor } from "./rhp.js";
import { squarespaceExtractor } from "./squarespace.js";
import { dedupeEvents, looksLikeHtml, moveTicketingEventUrl } from "./util.js";
import { webflowShowsExtractor } from "./webflow-shows.js";
import { wpTribeExtractor } from "./wp-tribe.js";

export * from "./aeg.js";
export * from "./endpoints.js";
export * from "./ical.js";
export * from "./jsonld.js";
export * from "./microdata.js";
export * from "./rhp.js";
export * from "./routes.js";
export * from "./schemaorg.js";
export * from "./squarespace.js";
export * from "./time.js";
export * from "./util.js";
export * from "./wp-tribe.js";

/** Structured extractors in cost order. */
export const STRUCTURED_EXTRACTORS: readonly Extractor[] = [
  icalExtractor,
  wpTribeExtractor,
  squarespaceExtractor,
  aegExtractor,
  rhpExtractor,
  webflowShowsExtractor,
  jsonLdExtractor,
  microdataExtractor,
];

export interface ExtractionError {
  extractor: string;
  message: string;
}

export interface FollowedEndpoint {
  endpoint: StructuredEndpoint;
  ok: boolean;
  status: number | null;
  eventCount: number;
  message?: string;
}

export interface ExtractionResult {
  /** Name of the extractor that won, or null when nothing produced events. */
  extractor: string | null;
  events: ExtractedEvent[];
  /** The page the events came from: the input page, or a followed endpoint's response (keep it as evidence). */
  page: Page;
  /** Extractors whose canHandle() accepted a page, in the order tried. */
  attempted: string[];
  errors: ExtractionError[];
  /** Calendar endpoints advertised by the input HTML page. */
  endpoints: StructuredEndpoint[];
  followed: FollowedEndpoint[];
}

export interface ExtractOptions {
  /** Override the structured extractor list (default STRUCTURED_EXTRACTORS). */
  extractors?: readonly Extractor[];
  /** Follow advertised calendar endpoints when the page itself yields nothing (default true; needs ctx.http). */
  followEndpoints?: boolean;
  /** Max endpoints fetched per page (default 2). */
  maxFollow?: number;
  /** Extractor tried last when no structured extractor produced events (e.g. the LLM extractor). */
  fallback?: Extractor | null;
}

function message(err: unknown): string {
  return (err instanceof Error ? err.message : String(err)).slice(0, 300);
}

export function pageFromFetch(res: FetchResult): Page {
  return {
    url: res.url,
    finalUrl: res.finalUrl,
    contentType: res.contentType,
    text: res.text,
    body: res.body,
    fetchedAt: res.fetchedAt,
  };
}

async function runExtractors(
  page: Page,
  ctx: ExtractContext,
  extractors: readonly Extractor[],
  attempted: string[],
  errors: ExtractionError[],
): Promise<{ extractor: string | null; events: ExtractedEvent[] }> {
  for (let i = 0; i < extractors.length; i++) {
    const ex = extractors[i];
    let events: ExtractedEvent[];
    try {
      if (!ex.canHandle(page, ctx)) continue;
      attempted.push(ex.name);
      events = await ex.extract(page, ctx);
    } catch (err) {
      errors.push({ extractor: ex.name, message: message(err) });
      continue;
    }
    if (!events.length) continue;
    events = events.map(moveTicketingEventUrl);
    if (ex.name === jsonLdExtractor.name) {
      const micro = extractors.slice(i + 1).find((e) => e.name === microdataExtractor.name);
      if (micro) {
        try {
          if (micro.canHandle(page, ctx)) {
            attempted.push(micro.name);
            const extra = (await micro.extract(page, ctx)).map(moveTicketingEventUrl);
            events = dedupeEvents([...events, ...extra], true);
          }
        } catch (err) {
          errors.push({ extractor: micro.name, message: message(err) });
        }
      }
    }
    return { extractor: ex.name, events };
  }
  return { extractor: null, events: [] };
}

const ACCEPT: Record<StructuredEndpoint["kind"], string> = {
  ical: "text/calendar, text/plain;q=0.8, */*;q=0.5",
  wp_tribe: "application/json",
  squarespace: "application/json",
};

/** Runs structured extractors (and endpoint following) over one fetched page. */
export async function extractStructured(
  page: Page,
  ctx: ExtractContext,
  options: ExtractOptions = {},
): Promise<ExtractionResult> {
  const extractors = options.extractors ?? STRUCTURED_EXTRACTORS;
  const attempted: string[] = [];
  const errors: ExtractionError[] = [];
  const isHtml = looksLikeHtml(page);
  const endpoints = isHtml ? discoverStructuredEndpoints(page.text, page.finalUrl || page.url) : [];
  const followed: FollowedEndpoint[] = [];

  const first = await runExtractors(page, ctx, extractors, attempted, errors);
  if (first.events.length) return { ...first, page, attempted, errors, endpoints, followed };

  if (isHtml && ctx.http && options.followEndpoints !== false) {
    const max = options.maxFollow ?? 2;
    const tried = new Set([page.url, page.finalUrl]);
    for (const endpoint of endpoints) {
      if (followed.length >= max) break;
      if (tried.has(endpoint.url) || isTicketingUrl(endpoint.url)) continue;
      if (!endpoint.sameSite && !endpoint.trustedCalendarHost) continue;
      tried.add(endpoint.url);
      let res: FetchResult;
      try {
        res = await ctx.http.get({ url: endpoint.url, accept: ACCEPT[endpoint.kind] });
      } catch (err) {
        followed.push({ endpoint, ok: false, status: null, eventCount: 0, message: message(err) });
        continue;
      }
      if (res.notModified || res.status < 200 || res.status >= 300) {
        followed.push({ endpoint, ok: false, status: res.status, eventCount: 0, message: `HTTP ${res.status}` });
        continue;
      }
      const endpointPage = pageFromFetch(res);
      const result = await runExtractors(endpointPage, ctx, extractors, attempted, errors);
      followed.push({ endpoint, ok: true, status: res.status, eventCount: result.events.length });
      if (result.events.length) return { ...result, page: endpointPage, attempted, errors, endpoints, followed };
    }
  }

  return { extractor: null, events: [], page, attempted, errors, endpoints, followed };
}

/** Structured extraction, then `options.fallback` (e.g. the LLM extractor) on the original page if nothing was found. */
export async function extractEvents(
  page: Page,
  ctx: ExtractContext,
  options: ExtractOptions = {},
): Promise<ExtractionResult> {
  const result = await extractStructured(page, ctx, options);
  const fallback = options.fallback;
  if (result.events.length || !fallback) return result;
  try {
    if (!fallback.canHandle(page, ctx)) return result;
    result.attempted.push(fallback.name);
    const events = await fallback.extract(page, ctx);
    if (events.length) return { ...result, extractor: fallback.name, events, page };
  } catch (err) {
    result.errors.push({ extractor: fallback.name, message: message(err) });
  }
  return result;
}
