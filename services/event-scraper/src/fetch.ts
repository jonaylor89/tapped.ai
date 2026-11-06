/**
 * Polite HTTP client over global fetch:
 * - ticketing-domain denylist and private-host block enforced before ANY request (and on every redirect hop)
 * - robots.txt (RFC 9309) fetched, cached and honored, including Crawl-delay
 * - per-host minimum interval between requests (slots reserved synchronously, so concurrent calls queue up; with a
 *   `slotStore` the slots are shared by every process and laptop through Postgres)
 * - hostnames resolved before connecting; private / loopback / link-local answers are refused (every hop)
 * - conditional GET (If-None-Match / If-Modified-Since), timeout, max body bytes, capped manual redirects
 * - identifiable User-Agent; raw bytes + sha256 returned for evidence
 */
import { createHash } from "node:crypto";
import { lookup } from "node:dns/promises";
import { isIpLiteral, isPrivateAddress, isPrivateHost, ticketingMatch } from "./denylist.js";
import type { Clock, FetchLike, FetchRequest, FetchResult, HttpClient, Sleep } from "./types.js";
import { realSleep, systemClock } from "./types.js";
import { parseHttpUrl } from "./url.js";

export const USER_AGENT = "TappedEventScraper/1.0 (+https://tapped.ai)";
/** Product token matched against robots.txt `User-agent` lines. */
export const ROBOTS_AGENT = "TappedEventScraper";

export type BlockReason = "ticketing" | "robots" | "scheme" | "private_host";

export class FetchBlockedError extends Error {
  constructor(
    readonly reason: BlockReason,
    readonly url: string,
    detail?: string,
  ) {
    super(`Blocked (${reason})${detail ? `: ${detail}` : ""}: ${url}`);
    this.name = "FetchBlockedError";
  }
}

export type FetchErrorCode = "timeout" | "network" | "too_large" | "too_many_redirects" | "bad_redirect";

export class FetchError extends Error {
  constructor(
    readonly code: FetchErrorCode,
    readonly url: string,
    message: string,
  ) {
    super(message);
    this.name = "FetchError";
  }
}

export interface HttpClientOptions {
  fetchImpl?: FetchLike;
  clock?: Clock;
  sleep?: Sleep;
  userAgent?: string;
  robotsAgent?: string;
  /** Whole-request timeout including body. Default 20s. */
  timeoutMs?: number;
  /** Max response body. Default 5 MiB. */
  maxBytes?: number;
  /** Default 5. */
  maxRedirects?: number;
  /** Minimum spacing between requests to the same host. Default 5s. */
  minHostIntervalMs?: number;
  /** Upper bound for honoring robots Crawl-delay / Retry-After. Default 60s / 1h. */
  maxCrawlDelayMs?: number;
  maxRetryAfterMs?: number;
  respectRobots?: boolean;
  /** Default 24h for fetched robots, 30 min when robots.txt could not be retrieved. */
  robotsTtlMs?: number;
  robotsErrorTtlMs?: number;
  /**
   * Resolves a hostname to its IP addresses before every request (each redirect hop and robots.txt); any private,
   * loopback, link-local or unspecified answer blocks the request. Default: the system resolver when the real global
   * fetch is used; none when `fetchImpl` is injected (tests are offline). Pass null to disable.
   */
  resolveHost?: ((hostname: string) => Promise<string[]>) | null;
  /** Per-host politeness slots shared across processes (Postgres). Default: in-memory, this client only. */
  slotStore?: HostSlotStore | null;
}

/** Shared per-host request slots (see db.ts `hostSlotStore`). */
export interface HostSlotStore {
  /** Reserves the host's next slot (>= now) and moves its next free slot to slot + interval. */
  reserve(host: string, now: number, intervalMs: number): Promise<number>;
  /** Pushes the host's next free slot to at least `until` (Retry-After). */
  defer(host: string, until: number, now: number): Promise<void>;
}

async function systemResolve(hostname: string): Promise<string[]> {
  const answers = await lookup(hostname, { all: true, verbatim: true });
  return answers.map((a) => a.address);
}

const REDIRECT_STATUSES = new Set([301, 302, 303, 307, 308]);
const DEFAULT_ACCEPT =
  "text/html,application/xhtml+xml,application/ld+json;q=0.9,application/json;q=0.9,text/calendar;q=0.9,*/*;q=0.5";

// ---------------------------------------------------------------------------------------------------------------------
// robots.txt
// ---------------------------------------------------------------------------------------------------------------------

interface RobotsRule {
  allow: boolean;
  pattern: string;
  regex: RegExp;
}

export interface RobotsPolicy {
  isAllowed(pathAndQuery: string): boolean;
  crawlDelayMs: number | null;
}

export const ALLOW_ALL: RobotsPolicy = { isAllowed: () => true, crawlDelayMs: null };
export const DISALLOW_ALL: RobotsPolicy = { isAllowed: (path) => path === "/robots.txt", crawlDelayMs: null };

function patternToRegex(pattern: string): RegExp {
  const anchored = pattern.endsWith("$");
  const body = (anchored ? pattern.slice(0, -1) : pattern)
    .split("*")
    .map((part) => part.replace(/[.+?^${}()|[\]\\]/g, "\\$&"))
    .join(".*");
  return new RegExp(`^${body}${anchored ? "$" : ""}`);
}

/** Parses robots.txt for `agent` (case-insensitive product token), falling back to the `*` group. */
export function parseRobots(text: string, agent: string = ROBOTS_AGENT): RobotsPolicy {
  const token = agent.toLowerCase();
  type Group = { agents: string[]; rules: RobotsRule[]; crawlDelay: number | null };
  const groups: Group[] = [];
  let current: Group | null = null;
  let lastWasAgent = false;
  for (const rawLine of text.split(/\r?\n|\r/)) {
    const line = rawLine.replace(/#.*$/, "").trim();
    const separator = line.indexOf(":");
    if (separator < 0) continue;
    const key = line.slice(0, separator).trim().toLowerCase();
    const value = line.slice(separator + 1).trim();
    if (key === "user-agent") {
      if (!current || !lastWasAgent) {
        current = { agents: [], rules: [], crawlDelay: null };
        groups.push(current);
      }
      current.agents.push(value.toLowerCase());
      lastWasAgent = true;
      continue;
    }
    lastWasAgent = false;
    if (!current) continue;
    if (key === "allow" || key === "disallow") {
      if (!value) continue; // empty Disallow means "allow everything" — no rule
      current.rules.push({ allow: key === "allow", pattern: value, regex: patternToRegex(value) });
    } else if (key === "crawl-delay") {
      const seconds = Number(value);
      if (Number.isFinite(seconds) && seconds >= 0) current.crawlDelay = seconds;
    }
  }
  const specific = groups.filter((group) => group.agents.some((name) => name !== "*" && token.startsWith(name)));
  const chosen = specific.length ? specific : groups.filter((group) => group.agents.includes("*"));
  const rules = chosen.flatMap((group) => group.rules);
  const delays = chosen.map((group) => group.crawlDelay).filter((delay): delay is number => delay !== null);
  return {
    crawlDelayMs: delays.length ? Math.max(...delays) * 1000 : null,
    isAllowed(pathAndQuery: string) {
      if (pathAndQuery === "/robots.txt") return true;
      let best: RobotsRule | null = null;
      for (const rule of rules) {
        if (!rule.regex.test(pathAndQuery)) continue;
        if (
          !best ||
          rule.pattern.length > best.pattern.length ||
          (rule.pattern.length === best.pattern.length && rule.allow)
        )
          best = rule;
      }
      return best ? best.allow : true;
    },
  };
}

// ---------------------------------------------------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------------------------------------------------

function charsetOf(contentType: string | null): string {
  const match = contentType?.match(/charset\s*=\s*"?([^";\s]+)/i);
  return match?.[1]?.toLowerCase() ?? "utf-8";
}

export function decodeBody(body: Uint8Array, contentType: string | null): string {
  try {
    return new TextDecoder(charsetOf(contentType)).decode(body);
  } catch {
    return new TextDecoder("utf-8").decode(body);
  }
}

function headersToRecord(headers: Headers): Record<string, string> {
  const record: Record<string, string> = {};
  headers.forEach((value, key) => {
    record[key.toLowerCase()] = value;
  });
  return record;
}

function retryAfterMs(value: string | null, now: number): number | null {
  if (!value) return null;
  const seconds = Number(value);
  if (Number.isFinite(seconds)) return Math.max(0, seconds * 1000);
  const date = Date.parse(value);
  return Number.isFinite(date) ? Math.max(0, date - now) : null;
}

interface RawResponse {
  status: number;
  headers: Headers;
  body: Uint8Array;
}

export class PoliteHttpClient implements HttpClient {
  private readonly fetchImpl: FetchLike;
  private readonly clock: Clock;
  private readonly sleep: Sleep;
  private readonly userAgent: string;
  private readonly robotsAgent: string;
  private readonly timeoutMs: number;
  private readonly maxBytes: number;
  private readonly maxRedirects: number;
  private readonly minHostIntervalMs: number;
  private readonly maxCrawlDelayMs: number;
  private readonly maxRetryAfterMs: number;
  private readonly respectRobots: boolean;
  private readonly robotsTtlMs: number;
  private readonly robotsErrorTtlMs: number;
  private readonly resolveHost: ((hostname: string) => Promise<string[]>) | null;
  private readonly slotStore: HostSlotStore | null;
  /** Next free request slot per host (epoch ms). */
  private readonly hostNextSlot = new Map<string, number>();
  private readonly hostInterval = new Map<string, number>();
  private readonly robotsCache = new Map<string, { policy: RobotsPolicy; expiresAt: number }>();
  private readonly robotsInFlight = new Map<string, Promise<RobotsPolicy>>();

  constructor(options: HttpClientOptions = {}) {
    this.fetchImpl = options.fetchImpl ?? ((input, init) => globalThis.fetch(input, init));
    this.clock = options.clock ?? systemClock;
    this.sleep = options.sleep ?? realSleep;
    this.userAgent = options.userAgent ?? USER_AGENT;
    this.robotsAgent = options.robotsAgent ?? ROBOTS_AGENT;
    this.timeoutMs = options.timeoutMs ?? 20_000;
    this.maxBytes = options.maxBytes ?? 5 * 1024 * 1024;
    this.maxRedirects = options.maxRedirects ?? 5;
    this.minHostIntervalMs = options.minHostIntervalMs ?? 5_000;
    this.maxCrawlDelayMs = options.maxCrawlDelayMs ?? 60_000;
    this.maxRetryAfterMs = options.maxRetryAfterMs ?? 60 * 60 * 1000;
    this.respectRobots = options.respectRobots ?? true;
    this.robotsTtlMs = options.robotsTtlMs ?? 24 * 60 * 60 * 1000;
    this.robotsErrorTtlMs = options.robotsErrorTtlMs ?? 30 * 60 * 1000;
    this.resolveHost =
      options.resolveHost !== undefined ? options.resolveHost : options.fetchImpl ? null : systemResolve;
    this.slotStore = options.slotStore ?? null;
  }

  /**
   * DNS check right before connecting: a public-looking name that resolves to a private address (127.0.0.1.nip.io,
   * a rebinding domain, an internal CNAME) is blocked like a private literal.
   */
  private async assertPublicAddress(url: URL): Promise<void> {
    if (!this.resolveHost) return;
    const hostname = url.hostname.replace(/^\[|\]$/g, "");
    if (isIpLiteral(hostname)) return; // literals were already checked by assertFetchable
    let addresses: string[];
    try {
      addresses = await this.resolveHost(hostname);
    } catch (error) {
      throw new FetchError("network", url.href, `DNS lookup failed: ${(error as Error)?.message ?? String(error)}`);
    }
    if (!addresses.length) throw new FetchError("network", url.href, "DNS lookup returned no addresses");
    if (addresses.some((address) => isPrivateAddress(address)))
      throw new FetchBlockedError("private_host", url.href, "resolves to a private address");
  }

  /** Throws FetchBlockedError if the URL may never be contacted (scheme, ticketing, private host). */
  assertFetchable(value: string): URL {
    const url = parseHttpUrl(value);
    if (!url || !/^https?:\/\//i.test(value.trim())) throw new FetchBlockedError("scheme", value);
    const ticketing = ticketingMatch(url);
    if (ticketing) throw new FetchBlockedError("ticketing", value, ticketing);
    if (isPrivateHost(url)) throw new FetchBlockedError("private_host", value);
    return url;
  }

  /** Whether robots.txt for the URL's origin allows our agent to fetch it. */
  async robotsAllowed(value: string): Promise<boolean> {
    const url = this.assertFetchable(value);
    if (!this.respectRobots) return true;
    const policy = await this.robotsFor(url);
    return policy.isAllowed(`${url.pathname}${url.search}`);
  }

  async get(request: FetchRequest): Promise<FetchResult> {
    const started = this.clock.now().getTime();
    const chain: string[] = [];
    let current = this.assertFetchable(request.url);
    for (let hop = 0; ; hop++) {
      if (hop > this.maxRedirects) throw new FetchError("too_many_redirects", request.url, "Too many redirects");
      if (hop > 0) this.assertFetchable(current.href);
      if (this.respectRobots) {
        const policy = await this.robotsFor(current);
        if (!policy.isAllowed(`${current.pathname}${current.search}`))
          throw new FetchBlockedError("robots", current.href);
      }
      chain.push(current.href);
      const headers: Record<string, string> = {
        "user-agent": this.userAgent,
        accept: request.accept ?? DEFAULT_ACCEPT,
        "accept-language": "en-US,en;q=0.8",
      };
      if (request.etag) headers["if-none-match"] = request.etag;
      if (request.lastModified) headers["if-modified-since"] = request.lastModified;
      const response = await this.request(current, headers);
      if (REDIRECT_STATUSES.has(response.status)) {
        const location = response.headers.get("location");
        if (!location) throw new FetchError("bad_redirect", current.href, "Redirect without Location");
        let next: URL;
        try {
          next = new URL(location, current);
        } catch {
          throw new FetchError("bad_redirect", current.href, `Invalid redirect Location: ${location}`);
        }
        current = next;
        continue;
      }
      const contentType = response.headers.get("content-type");
      const notModified = response.status === 304;
      const body = notModified ? new Uint8Array(0) : response.body;
      const finished = this.clock.now().getTime();
      return {
        url: request.url,
        finalUrl: current.href,
        redirectChain: chain,
        status: response.status,
        notModified,
        headers: headersToRecord(response.headers),
        contentType,
        etag: response.headers.get("etag"),
        lastModified: response.headers.get("last-modified"),
        body,
        text: notModified ? "" : decodeBody(body, contentType),
        sha256: createHash("sha256").update(body).digest("hex"),
        fetchedAt: finished,
        durationMs: finished - started,
      };
    }
  }

  // -------------------------------------------------------------------------------------------------------------------

  private async robotsFor(url: URL): Promise<RobotsPolicy> {
    const origin = url.origin;
    const cached = this.robotsCache.get(origin);
    if (cached && cached.expiresAt > this.clock.now().getTime()) return cached.policy;
    const pending = this.robotsInFlight.get(origin);
    if (pending) return pending;
    const promise = this.loadRobots(url).finally(() => this.robotsInFlight.delete(origin));
    this.robotsInFlight.set(origin, promise);
    return promise;
  }

  private async loadRobots(url: URL): Promise<RobotsPolicy> {
    const origin = url.origin;
    let policy: RobotsPolicy;
    let ttl = this.robotsTtlMs;
    try {
      let target = new URL("/robots.txt", origin);
      let response: RawResponse | null = null;
      for (let hop = 0; hop <= this.maxRedirects; hop++) {
        this.assertFetchable(target.href);
        const raw = await this.request(
          target,
          { "user-agent": this.userAgent, accept: "text/plain,*/*;q=0.5" },
          512 * 1024,
        );
        const location = raw.headers.get("location");
        if (REDIRECT_STATUSES.has(raw.status) && location) {
          target = new URL(location, target);
          continue;
        }
        response = raw;
        break;
      }
      if (!response) {
        policy = DISALLOW_ALL;
        ttl = this.robotsErrorTtlMs;
      } else if (response.status >= 200 && response.status < 300) {
        policy = parseRobots(decodeBody(response.body, response.headers.get("content-type")), this.robotsAgent);
      } else if (response.status >= 400 && response.status < 500) {
        // RFC 9309: "unavailable" robots.txt (4xx) means no restrictions.
        policy = ALLOW_ALL;
      } else {
        // RFC 9309: "unreachable" (5xx/network) means assume complete disallow, retried later.
        policy = DISALLOW_ALL;
        ttl = this.robotsErrorTtlMs;
      }
    } catch {
      policy = DISALLOW_ALL;
      ttl = this.robotsErrorTtlMs;
    }
    const host = url.host.toLowerCase();
    if (policy.crawlDelayMs !== null) {
      this.hostInterval.set(
        host,
        Math.min(Math.max(policy.crawlDelayMs, this.minHostIntervalMs), this.maxCrawlDelayMs),
      );
    }
    this.robotsCache.set(origin, { policy, expiresAt: this.clock.now().getTime() + ttl });
    return policy;
  }

  /** Waits for this host's next politeness slot. Reserving a slot is atomic, so concurrent callers queue. */
  private async acquireSlot(host: string): Promise<void> {
    const now = this.clock.now().getTime();
    const interval = this.hostInterval.get(host) ?? this.minHostIntervalMs;
    let slot: number;
    if (this.slotStore) {
      slot = await this.slotStore.reserve(host, now, interval);
    } else {
      slot = Math.max(now, this.hostNextSlot.get(host) ?? 0);
      this.hostNextSlot.set(host, slot + interval);
    }
    if (slot > now) await this.sleep(slot - now);
  }

  private async request(url: URL, headers: Record<string, string>, maxBytes = this.maxBytes): Promise<RawResponse> {
    const host = url.host.toLowerCase();
    await this.acquireSlot(host);
    await this.assertPublicAddress(url);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      let response: Response;
      try {
        response = await this.fetchImpl(url.href, {
          method: "GET",
          headers,
          redirect: "manual",
          signal: controller.signal,
        });
      } catch (error) {
        if (controller.signal.aborted) throw new FetchError("timeout", url.href, `Timed out after ${this.timeoutMs}ms`);
        throw new FetchError("network", url.href, `Network error: ${(error as Error)?.message ?? String(error)}`);
      }
      if (response.status === 429 || response.status === 503) {
        const wait = retryAfterMs(response.headers.get("retry-after"), this.clock.now().getTime());
        if (wait !== null) {
          const nowMs = this.clock.now().getTime();
          const until = nowMs + Math.min(wait, this.maxRetryAfterMs);
          if (this.slotStore) await this.slotStore.defer(host, until, nowMs);
          else this.hostNextSlot.set(host, Math.max(this.hostNextSlot.get(host) ?? 0, until));
        }
      }
      const body = await this.readCapped(response, url.href, maxBytes, controller);
      return { status: response.status, headers: response.headers, body };
    } finally {
      clearTimeout(timer);
    }
  }

  private async readCapped(
    response: Response,
    url: string,
    maxBytes: number,
    controller: AbortController,
  ): Promise<Uint8Array> {
    const declared = Number(response.headers.get("content-length"));
    if (Number.isFinite(declared) && declared > maxBytes) {
      await response.body?.cancel().catch(() => undefined);
      throw new FetchError("too_large", url, `Body exceeds ${maxBytes} bytes (declared ${declared})`);
    }
    if (!response.body) return new Uint8Array(0);
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let total = 0;
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        total += value.byteLength;
        if (total > maxBytes) {
          await reader.cancel().catch(() => undefined);
          throw new FetchError("too_large", url, `Body exceeds ${maxBytes} bytes`);
        }
        chunks.push(value);
      }
    } catch (error) {
      if (error instanceof FetchError) throw error;
      if (controller.signal.aborted) throw new FetchError("timeout", url, `Timed out after ${this.timeoutMs}ms`);
      throw new FetchError("network", url, `Body read failed: ${(error as Error)?.message ?? String(error)}`);
    }
    const body = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      body.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return body;
  }
}

export function createHttpClient(options: HttpClientOptions = {}): PoliteHttpClient {
  return new PoliteHttpClient(options);
}
