/**
 * Which website hosts say something about a venue's identity. Social profiles, link-in-bio pages, aggregators and
 * ticketing platforms are shared by thousands of venues, so they never identify one; shared-hosting parents
 * (*.squarespace.com, *.wixsite.com, ...) identify a venue only by the full host.
 */
import { isTicketingUrl } from "../denylist.js";
import { normalizedHost, parseHttpUrl, registrableDomain } from "../url.js";

/** Hosts that are not a venue's own website (social, link-in-bio, aggregators, maps). */
export const NON_OWN_SITE_DOMAINS: ReadonlySet<string> = new Set([
  "facebook.com",
  "fb.com",
  "fb.me",
  "instagram.com",
  "twitter.com",
  "x.com",
  "tiktok.com",
  "youtube.com",
  "linktr.ee",
  "linkin.bio",
  "beacons.ai",
  "bandsintown.com",
  "songkick.com",
  "yelp.com",
  "tripadvisor.com",
  "google.com",
  "goo.gl",
  "g.page",
  "maps.app.goo.gl",
]);

/** Registrable domains of shared hosting where each customer gets a subdomain. */
export const SHARED_HOSTING_DOMAINS: ReadonlySet<string> = new Set([
  "squarespace.com",
  "wixsite.com",
  "wix.com",
  "wordpress.com",
  "blogspot.com",
  "weebly.com",
  "webflow.io",
  "godaddysites.com",
  "square.site",
  "carrd.co",
  "netlify.app",
  "vercel.app",
  "github.io",
  "tumblr.com",
  "myshopify.com",
  "business.site",
]);

/** True for social / aggregator / link-in-bio URLs (never a venue's own site). */
export function isNonOwnSite(url: string | URL): boolean {
  const host = normalizedHost(url) ?? "";
  const domain = registrableDomain(url) ?? "";
  return NON_OWN_SITE_DOMAINS.has(domain) || NON_OWN_SITE_DOMAINS.has(host);
}

/**
 * The part of a website URL that may identify a venue: the registrable domain for normal sites, the full host on
 * shared hosting, and null for ticketing, social, aggregator and invalid URLs.
 */
export function identityDomain(url: string | null | undefined): string | null {
  if (!url) return null;
  const parsed = parseHttpUrl(url);
  if (!parsed || isTicketingUrl(parsed) || isNonOwnSite(parsed)) return null;
  const domain = registrableDomain(parsed);
  if (!domain) return null;
  return SHARED_HOSTING_DOMAINS.has(domain) ? normalizedHost(parsed) : domain;
}
