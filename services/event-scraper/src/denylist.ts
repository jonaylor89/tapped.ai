/**
 * HARD RULE: no ticketing platforms of any kind — not as fetch targets, adapters, or discovery feeds.
 * Enforced before every request (including each redirect hop) and when choosing event sources.
 * Ticket links may be stored on events as plain strings, but they are never fetched.
 */
import { normalizedHost, parseHttpUrl } from "./url.js";

/** Exact domains; any subdomain also matches. */
export const TICKETING_DOMAINS: readonly string[] = [
  "ticketmaster.com",
  "livenation.com",
  "eventbrite.com",
  "dice.fm",
  "axs.com",
  "axs.co.uk",
  "seetickets.com",
  "seetickets.us",
  "ticketweb.com",
  "ticketweb.ca",
  "ticketweb.uk",
  "etix.com",
  "tixr.com",
  "ticketfly.com",
  "stubhub.com",
  "vividseats.com",
  "seatgeek.com",
  "gametime.co",
  "tickpick.com",
  "viagogo.com",
  "songkick.com",
  "showclix.com",
  "ticketleap.com",
  "brownpapertickets.com",
  "universe.com",
  "eventim.com",
  "eventim.de",
  "frontgatetickets.com",
  "prekindle.com",
  "holdmyticket.com",
  "ticketstoday.com",
  "freshtix.com",
  "ticketsauce.com",
  "venuepilot.com",
  "venuepilot.co",
  "opendate.io",
  "ticketbud.com",
  "simpletix.com",
  "purplepass.com",
  "ticketspice.com",
  "ticketsource.co.uk",
  "ticketsource.us",
  "skiddle.com",
  "ra.co",
  "residentadvisor.net",
  "feverup.com",
  "shotgun.live",
  "posh.vip",
  "humanitix.com",
  "tickettailor.com",
  "tixel.com",
  "ticketnetwork.com",
  "ticketcity.com",
  "ticketliquidator.com",
  "ticketsnow.com",
  "tickets.com",
  "ticketek.com",
  "ticketek.com.au",
  "yapsody.com",
  "thundertix.com",
  "ovationtix.com",
  "audienceview.com",
  "ludus.com",
  "vbotickets.com",
  "showtix4u.com",
  "eventvesta.com",
  "ticketfairy.com",
  "tix.com",
  "eventsquid.com",
  "zeffy.com",
  "goldstar.com",
  "showpass.com",
  "ticketstripe.com",
  "wegottickets.com",
  "lyte.com",
  "big-tickets.com",
  "etixnow.com",
];

/**
 * Brand labels matched on any TLD / subdomain (e.g. "ticketmaster.co.uk", "www.eventbrite.ie").
 * Only unambiguous brand names belong here.
 */
export const TICKETING_BRAND_LABELS: readonly string[] = [
  "ticketmaster",
  "livenation",
  "eventbrite",
  "stubhub",
  "vividseats",
  "seatgeek",
  "viagogo",
  "eventim",
  "ticketweb",
  "seetickets",
  "ticketek",
  "tixr",
  "ticketfly",
  "axstickets",
];

/** Returns the denylist entry that matched, or null. */
export function ticketingMatch(url: string | URL): string | null {
  const host = normalizedHost(url);
  if (!host) return null;
  for (const domain of TICKETING_DOMAINS) {
    if (host === domain || host.endsWith(`.${domain}`)) return domain;
  }
  const labels = host.split(".");
  for (const brand of TICKETING_BRAND_LABELS) {
    if (labels.includes(brand)) return brand;
  }
  return null;
}

/** True if the URL belongs to a ticketing platform and must never be fetched or used as a source/feed. */
export function isTicketingUrl(url: string | URL): boolean {
  return ticketingMatch(url) !== null;
}

/** Parses dotted-quad IPv4 into its four octets, or null. */
function parseIpv4(text: string): [number, number, number, number] | null {
  const m = text.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (!m) return null;
  const octets = m.slice(1).map(Number) as [number, number, number, number];
  return octets.every((o) => o <= 255) ? octets : null;
}

function isPrivateIpv4([a, b, c]: [number, number, number, number]): boolean {
  return (
    a === 0 || // "this network" / unspecified
    a === 10 ||
    a === 127 ||
    (a === 100 && b >= 64 && b <= 127) || // carrier-grade NAT
    (a === 169 && b === 254) || // link-local, cloud metadata
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168) ||
    (a === 192 && b === 0 && c === 0) || // IETF protocol assignments
    (a === 198 && (b === 18 || b === 19)) || // benchmarking
    a >= 224 // multicast and reserved
  );
}

/** Expands an IPv6 literal (with optional embedded IPv4 tail) into eight 16-bit groups, or null. */
function parseIpv6(text: string): number[] | null {
  let host = text.toLowerCase().replace(/%.*$/, "");
  let tail: number[] = [];
  const v4 = host.match(/^(.*:)(\d{1,3}(?:\.\d{1,3}){3})$/);
  if (v4) {
    const octets = parseIpv4(v4[2] as string);
    if (!octets) return null;
    tail = [(octets[0] << 8) | octets[1], (octets[2] << 8) | octets[3]];
    host = (v4[1] as string).endsWith("::") ? (v4[1] as string) : (v4[1] as string).slice(0, -1);
  }
  const halves = host.split("::");
  if (halves.length > 2) return null;
  const parse = (part: string) => (part ? part.split(":") : []);
  const head = parse(halves[0] as string);
  const rest = halves.length === 2 ? parse(halves[1] as string) : [];
  if ([...head, ...rest].some((g) => !/^[0-9a-f]{1,4}$/.test(g))) return null;
  const known = head.length + rest.length + tail.length;
  if (halves.length === 1 ? known !== 8 : known > 7) return null;
  const zeros = Array.from({ length: 8 - known }, () => 0);
  return [...head.map((g) => Number.parseInt(g, 16)), ...zeros, ...rest.map((g) => Number.parseInt(g, 16)), ...tail];
}

function isPrivateIpv6(groups: number[]): boolean {
  const [g0 = 0, g1 = 0, g2 = 0, g3 = 0, g4 = 0, g5 = 0, g6 = 0, g7 = 0] = groups;
  const embedded: [number, number, number, number] = [g6 >> 8, g6 & 0xff, g7 >> 8, g7 & 0xff];
  const firstFiveZero = g0 === 0 && g1 === 0 && g2 === 0 && g3 === 0 && g4 === 0;
  if (firstFiveZero && g5 === 0 && g6 === 0 && (g7 === 0 || g7 === 1)) return true; // :: and ::1
  if (firstFiveZero && (g5 === 0xffff || g5 === 0)) return isPrivateIpv4(embedded); // ::ffff:a.b.c.d, ::a.b.c.d
  if (g0 === 0x64 && g1 === 0xff9b && g2 === 0 && g3 === 0 && g4 === 0 && g5 === 0) return isPrivateIpv4(embedded);
  if ((g0 & 0xfe00) === 0xfc00) return true; // unique local fc00::/7
  if ((g0 & 0xffc0) === 0xfe80) return true; // link-local fe80::/10
  if ((g0 & 0xff00) === 0xff00) return true; // multicast
  return false;
}

/**
 * True for a literal IP address (v4, or v6 with or without brackets) in a private, loopback, link-local, unspecified,
 * multicast or reserved range, including IPv4-mapped/compatible/NAT64 IPv6 forms of such addresses. Used both for URL
 * hosts and for the addresses a hostname resolves to.
 */
export function isPrivateAddress(address: string): boolean {
  const host = address.trim().replace(/^\[|\]$/g, "");
  const v4 = parseIpv4(host);
  if (v4) return isPrivateIpv4(v4);
  if (!host.includes(":")) return false;
  const v6 = parseIpv6(host);
  // An address we cannot parse is not trusted.
  return v6 ? isPrivateIpv6(v6) : true;
}

/** True when the host is an IP literal (no DNS lookup needed). */
export function isIpLiteral(hostname: string): boolean {
  const host = hostname.replace(/^\[|\]$/g, "");
  return parseIpv4(host) !== null || host.includes(":");
}

/**
 * Hosts we never contact (SSRF hygiene for URLs that come from third-party data like Places and OSM): local names
 * and private / loopback / link-local / unspecified IP literals in any IPv4 or IPv6 spelling. Names that RESOLVE to
 * such addresses are caught at connect time by the HTTP client (see fetch.ts `resolveHost`).
 */
export function isPrivateHost(url: string | URL): boolean {
  const parsed = parseHttpUrl(url);
  if (!parsed) return false;
  const host = parsed.hostname
    .toLowerCase()
    .replace(/^\[|\]$/g, "")
    .replace(/\.$/, "");
  if (host === "localhost" || host.endsWith(".localhost") || host.endsWith(".local") || host.endsWith(".internal"))
    return true;
  return isIpLiteral(host) && isPrivateAddress(host);
}
