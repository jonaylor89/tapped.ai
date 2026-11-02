/**
 * Finds where a candidate venue publishes its events on its OWN website.
 *
 * 1. Fetch the homepage through the polite HttpClient (robots, ticketing denylist and private hosts enforced there;
 *    a website that is itself a ticketing/social page is refused up front).
 * 2. Structured endpoints advertised by the page (iCal, WordPress The Events Calendar API, Squarespace events
 *    collection) via `discoverStructuredEndpoints` from the extract module.
 * 3. Calendar-like links on the same site ranked by path/anchor text (/events, /calendar, /shows, /live-music,
 *    /whats-on ...), with penalties for rentals, private events, archives and single-event pages.
 * 4. Optionally the LLM picks among the top links when the heuristics are unsure.
 * 5. The homepage itself as a last resort (or first, when it already carries schema.org Event markup).
 *
 * The result is an ordered list of proposals; `prove.ts` runs real extraction on them. Nothing here is trusted.
 */
import { load } from "cheerio";
import { isTicketingUrl, ticketingMatch } from "../denylist.js";
import { discoverStructuredEndpoints, type StructuredEndpoint } from "../extract/endpoints.js";
import { FetchBlockedError, FetchError } from "../fetch.js";
import type { FetchResult, HttpClient, JsonSchema, LlmClient, SourceKind } from "../types.js";
import { parseHttpUrl, registrableDomain } from "../url.js";
import { isNonOwnSite } from "./website.js";

/** Hosts that are not a venue's own website. */
export { NON_OWN_SITE_DOMAINS } from "./website.js";

export type ProposalVia = "endpoint" | "homepage_events" | "llm" | "link" | "homepage";

export interface SourceProposal {
  kind: SourceKind;
  url: string;
  score: number;
  via: ProposalVia;
  reason: string;
}

export interface LinkCandidate {
  url: string;
  text: string;
  score: number;
}

export interface SourceFinderResult {
  ok: boolean;
  /** Why nothing could be proposed (no_website, ticketing_website, social_website, robots_blocked, http_404 ...). */
  reason: string | null;
  homepage: string | null;
  homepageStatus: number | null;
  proposals: SourceProposal[];
  links: LinkCandidate[];
  endpoints: StructuredEndpoint[];
  llmUsed: boolean;
}

export interface SourceFinderOptions {
  http: HttpClient;
  llm?: LlmClient | null;
  /** Max proposals returned. Default 5. */
  maxProposals?: number;
  /** Max links offered to the LLM. Default 15. */
  maxLlmLinks?: number;
  /** Injectable for tests; defaults to the extract module's implementation. */
  discoverEndpoints?: (html: string, url: string) => StructuredEndpoint[];
}

const POSITIVE: [RegExp, number][] = [
  [/(^|[/_-])(events?|calendar)([/_.-]|$)/, 50],
  [/(^|[/_-])(shows?|concerts?|gigs?|live[-_]?music|whats[-_]?on|what-s-on|happenings)([/_.-]|$)/, 45],
  [/(^|[/_-])(lineup|schedule|upcoming|performances?|comedy|music|entertainment|on[-_]?stage)([/_.-]|$)/, 30],
  [/(^|[/_-])tickets?([/_.-]|$)/, 15],
];
const NEGATIVE: [RegExp, number][] = [
  [/(^|[/_-])(private|rentals?|rent|hire|book(ing)?s?|weddings?|parties|party|host)([/_.-]|$)/, -45],
  [/(^|[/_-])(past|archives?|previous|recap|gallery|photos?|videos?)([/_.-]|$)/, -40],
  [
    /(^|[/_-])(careers?|jobs|contact|about|press|blog|news|faq|menu|food|drinks|gift|merch|shop|store|donate)([/_.-]|$)/,
    -30,
  ],
  [/(^|[/_-])(login|account|cart|checkout|wp-admin|feed)([/_.-]|$)/, -60],
];
const TEXT_POSITIVE =
  /\b(events?|calendar|shows?|concerts?|gigs?|live music|what'?s on|line-?up|schedule|upcoming|performances?|tickets?)\b/i;
const TEXT_NEGATIVE = /\b(private|rentals?|book (a|your|the)|weddings?|past|archive|gift cards?|careers?|jobs)\b/i;

const KIND_FOR_ENDPOINT: Record<StructuredEndpoint["kind"], SourceKind> = {
  ical: "ical",
  wp_tribe: "wp_tribe",
  squarespace: "squarespace",
};

/** Scores one same-site link as an event-calendar candidate (higher is better; <= 0 means not a calendar). */
export function scoreCalendarLink(url: URL, text: string): number {
  const path = decodeURIComponent(url.pathname).toLowerCase();
  let score = 0;
  for (const [re, points] of POSITIVE) if (re.test(path)) score = Math.max(score, points);
  for (const [re, points] of NEGATIVE) if (re.test(path)) score += points;
  if (TEXT_POSITIVE.test(text)) score += 20;
  if (TEXT_NEGATIVE.test(text)) score -= 30;
  const segments = path.split("/").filter(Boolean);
  if (segments.length > 1) score -= 6 * (segments.length - 1);
  // "/event/some-show" and "/events/2026/11/07/some-show" are single events, not the calendar.
  if (/^\/event\/[^/]+/.test(path) || /\/\d{4}\/\d{1,2}\/\d{1,2}\//.test(path)) score -= 25;
  if (url.search && /(date|month|year|page|tribe-bar-date)=/i.test(url.search)) score -= 10;
  return score;
}

function isOwnSite(url: URL, siteDomain: string | null): boolean {
  return siteDomain !== null && registrableDomain(url) === siteDomain;
}

/** Same-site links ranked as calendar candidates, best first, deduped by URL. */
export function rankCalendarLinks(html: string, pageUrl: string): LinkCandidate[] {
  const base = parseHttpUrl(pageUrl);
  if (!base) return [];
  const siteDomain = registrableDomain(base);
  const $ = load(html);
  const best = new Map<string, LinkCandidate>();
  $("a[href]").each((_, el) => {
    const href = ($(el).attr("href") ?? "").trim();
    if (!href || href.startsWith("#") || /^(mailto|tel|javascript|sms):/i.test(href)) return;
    let url: URL | null;
    try {
      url = parseHttpUrl(new URL(href, base));
    } catch {
      url = null;
    }
    if (!url || !isOwnSite(url, siteDomain) || isTicketingUrl(url)) return;
    url.hash = "";
    if (url.href === base.href || (url.pathname === "/" && !url.search)) return;
    if (/\.(jpe?g|png|gif|webp|svg|pdf|zip|mp3|mp4|css|js)$/i.test(url.pathname)) return;
    const text = $(el).text().replace(/\s+/g, " ").trim() || ($(el).attr("title") ?? "").trim();
    const score = scoreCalendarLink(url, text);
    if (score <= 0) return;
    const existing = best.get(url.href);
    if (!existing || existing.score < score) best.set(url.href, { url: url.href, text: text.slice(0, 120), score });
  });
  return [...best.values()].sort((a, b) => b.score - a.score || a.url.length - b.url.length);
}

const EVENT_MARKUP_RE = /"@type"\s*:\s*(\[[^\]]*)?"(\w*Event)"|itemtype=["'][^"']*schema\.org\/\w*Event["']/;

/** True when the page itself carries schema.org Event markup (JSON-LD or microdata). */
export function hasEventMarkup(html: string): boolean {
  return EVENT_MARKUP_RE.test(html);
}

export const LINK_CHOICE_SCHEMA: JsonSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    choice: { type: "integer", description: "Index of the best link, or -1 if none lists upcoming events." },
    reason: { type: "string" },
  },
  required: ["choice", "reason"],
};

async function askLlmForLink(
  llm: LlmClient,
  venueName: string,
  homepage: string,
  links: LinkCandidate[],
): Promise<LinkCandidate | null> {
  const list = links.map((link, i) => `${i}. ${link.url} — "${link.text}"`).join("\n");
  const response = await llm.completeJson({
    system:
      "You pick the page on a venue's own website that lists its upcoming public events (concerts, comedy, open mics, " +
      "theater, dance). Prefer a calendar/listing page over single-event pages, private-event rental pages, " +
      "archives or ticketing sites. Answer with the index from the list, or -1 if none fits.",
    user: `Venue: ${venueName}\nHomepage: ${homepage}\nLinks:\n${list}`,
    schemaName: "event_page_choice",
    schema: LINK_CHOICE_SCHEMA,
    maxOutputTokens: 200,
    temperature: 0,
  });
  const choice = (response.data as { choice?: unknown } | null)?.choice;
  if (typeof choice !== "number" || !Number.isInteger(choice) || choice < 0 || choice >= links.length) return null;
  return links[choice] ?? null;
}

function failure(reason: string, homepage: string | null, homepageStatus: number | null = null): SourceFinderResult {
  return { ok: false, reason, homepage, homepageStatus, proposals: [], links: [], endpoints: [], llmUsed: false };
}

/** Why a website cannot be the venue's own site, or null when it can. */
export function websiteRejection(website: string | null | undefined): string | null {
  if (!website) return "no_website";
  const url = parseHttpUrl(website);
  if (!url) return "invalid_website";
  if (ticketingMatch(url)) return "ticketing_website";
  if (isNonOwnSite(url)) return "social_website";
  return null;
}

/** Proposes event sources on the candidate's own website, best first. */
export async function findEventSources(
  venue: { name: string; website: string | null },
  options: SourceFinderOptions,
): Promise<SourceFinderResult> {
  const rejection = websiteRejection(venue.website);
  if (rejection) return failure(rejection, venue.website);
  const homepage = (parseHttpUrl(venue.website as string) as URL).href;

  let result: FetchResult;
  try {
    result = await options.http.get({ url: homepage });
  } catch (error) {
    if (error instanceof FetchBlockedError) {
      const reason =
        error.reason === "ticketing"
          ? "ticketing_website"
          : error.reason === "robots"
            ? "robots_blocked"
            : `blocked_${error.reason}`;
      return failure(reason, homepage);
    }
    if (error instanceof FetchError) return failure(`fetch_error_${error.code}`, homepage);
    throw error;
  }
  if (result.status < 200 || result.status >= 300) return failure(`http_${result.status}`, homepage, result.status);
  const finalUrl = result.finalUrl || homepage;
  // A homepage that redirects off-site (e.g. to a link-in-bio page) is not the venue's own website.
  const offSite = websiteRejection(finalUrl);
  if (offSite) return failure(offSite, homepage, result.status);

  const html = result.text;
  const discover = options.discoverEndpoints ?? discoverStructuredEndpoints;
  const endpoints = discover(html, finalUrl).filter(
    (endpoint) => !isTicketingUrl(endpoint.url) && (endpoint.sameSite || endpoint.trustedCalendarHost),
  );
  const links = rankCalendarLinks(html, finalUrl);
  const proposals: SourceProposal[] = [];
  const seen = new Set<string>();
  const push = (proposal: SourceProposal) => {
    if (seen.has(proposal.url) || isTicketingUrl(proposal.url)) return;
    seen.add(proposal.url);
    proposals.push(proposal);
  };

  for (const endpoint of endpoints) {
    push({
      kind: KIND_FOR_ENDPOINT[endpoint.kind],
      url: endpoint.url,
      score: Math.round(100 + endpoint.confidence * 100),
      via: "endpoint",
      reason: endpoint.reason,
    });
  }
  if (hasEventMarkup(html))
    push({ kind: "html", url: finalUrl, score: 120, via: "homepage_events", reason: "event markup" });

  let llmUsed = false;
  const top = links[0];
  const second = links[1];
  const unsure = !top || top.score < 45 || (second !== undefined && second.score === top.score);
  if (options.llm && links.length > 1 && unsure) {
    try {
      const pick = await askLlmForLink(options.llm, venue.name, finalUrl, links.slice(0, options.maxLlmLinks ?? 15));
      llmUsed = true;
      if (pick) push({ kind: "html", url: pick.url, score: pick.score + 30, via: "llm", reason: `llm: ${pick.text}` });
    } catch {
      // The LLM is an optional tie-breaker; heuristics still apply.
    }
  }
  for (const link of links) push({ kind: "html", url: link.url, score: link.score, via: "link", reason: link.text });
  push({ kind: "html", url: finalUrl, score: 1, via: "homepage", reason: "homepage fallback" });

  return {
    ok: true,
    reason: null,
    homepage: finalUrl,
    homepageStatus: result.status,
    proposals: proposals.slice(0, options.maxProposals ?? 5),
    links,
    endpoints,
    llmUsed,
  };
}
