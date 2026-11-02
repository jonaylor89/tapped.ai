import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { isTicketingUrl } from "../../src/denylist.js";
import type {
  ExtractContext,
  ExtractedEvent,
  FetchRequest,
  FetchResult,
  HttpClient,
  Page,
  Source,
} from "../../src/types.js";

/** "Today" for every extraction test: Monday 2026-11-02, 06:00 in Chicago. */
export const NOW = new Date("2026-11-02T12:00:00Z");

export function fixture(name: string): string {
  return readFileSync(new URL(`../fixtures/extract/${name}`, import.meta.url), "utf8");
}

export function makePage(text: string, url: string, contentType: string | null = "text/html; charset=utf-8"): Page {
  return { url, finalUrl: url, contentType, text, body: new TextEncoder().encode(text), fetchedAt: NOW.getTime() };
}

export function fixturePage(name: string, url: string, contentType?: string | null): Page {
  const ct =
    contentType !== undefined
      ? contentType
      : name.endsWith(".ics")
        ? "text/calendar; charset=utf-8"
        : name.endsWith(".json")
          ? "application/json; charset=UTF-8"
          : "text/html; charset=utf-8";
  return makePage(fixture(name), url, ct);
}

export function makeSource(url: string, timezone = "America/Chicago"): Source {
  return {
    id: "src-test",
    venueId: "venue-test",
    kind: "html",
    url,
    timezone,
    enabled: true,
    label: null,
    origin: "manual",
    fetchIntervalMs: 6 * 3600_000,
    createdAt: 0,
    updatedAt: 0,
  };
}

export function makeCtx(url: string, opts: { timezone?: string; now?: Date; http?: HttpClient } = {}): ExtractContext {
  const timezone = opts.timezone ?? "America/Chicago";
  return { source: makeSource(url, timezone), venue: null, timezone, now: opts.now ?? NOW, http: opts.http };
}

export interface FakeRoute {
  status?: number;
  contentType?: string;
  body: string;
}

/** Offline HttpClient: serves canned routes, records requests, and fails loudly if asked for a ticketing URL. */
export class FakeHttp implements HttpClient {
  readonly requests: FetchRequest[] = [];
  constructor(private readonly routes: Record<string, FakeRoute>) {}

  async get(request: FetchRequest): Promise<FetchResult> {
    this.requests.push(request);
    if (isTicketingUrl(request.url)) throw new Error(`test: ticketing URL requested: ${request.url}`);
    const route = this.routes[request.url];
    const status = route ? (route.status ?? 200) : 404;
    const text = route ? route.body : "not found";
    const body = new TextEncoder().encode(text);
    return {
      url: request.url,
      finalUrl: request.url,
      redirectChain: [request.url],
      status,
      notModified: false,
      headers: {},
      contentType: route?.contentType ?? "text/plain",
      etag: null,
      lastModified: null,
      body,
      text,
      sha256: createHash("sha256").update(body).digest("hex"),
      fetchedAt: NOW.getTime(),
      durationMs: 1,
    };
  }
}

export function byTitle(events: ExtractedEvent[], title: string): ExtractedEvent {
  const found = events.find((e) => e.title === title);
  if (!found)
    throw new Error(`no event titled ${JSON.stringify(title)}; have ${events.map((e) => e.title).join(" | ")}`);
  return found;
}
