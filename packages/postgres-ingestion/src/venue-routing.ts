/** Venue identity is not a registrable domain. This module performs no I/O or fuzzy matching. */
export type VenueRoute = { venueId: string; url: string };
export type VenueDiscoveryContext = {
  requestedUrl: string;
  loadedUrl: string;
  discoveryVenueId?: string;
  discoveryUrl?: string;
};
export type VenueRoutingStatus = "resolved" | "ambiguous" | "unmatched" | "cross_host_redirect" | "seed_mismatch";
export type VenueRoutingResult = { status: VenueRoutingStatus; venueId: string | null };
function page(value: string): URL {
  const parsed = new URL(value);
  if (!["https:", "http:"].includes(parsed.protocol) || parsed.username || parsed.password)
    throw new Error("Invalid venue routing URL");
  return parsed;
}
export function normalizeVenueRoutes(routes: VenueRoute[]): VenueRoute[] {
  const seen = new Set<string>();
  return routes.flatMap((route) => {
    if (!route.venueId || typeof route.venueId !== "string") throw new Error("Invalid venue routing identity");
    const url = page(route.url).href;
    const key = JSON.stringify([route.venueId, url]);
    if (seen.has(key)) return [];
    seen.add(key);
    return [{ venueId: route.venueId, url }];
  });
}
/** Include competing known profiles even when they were not selected in this crawl chunk. */
export function venueRoutesForSeeds(known: VenueRoute[], seeds: VenueRoute[]): VenueRoute[] {
  const hosts = new Set(normalizeVenueRoutes(seeds).map((r) => page(r.url).hostname.replace(/^www\./, "")));
  return normalizeVenueRoutes([...known, ...seeds]).filter((r) =>
    hosts.has(page(r.url).hostname.replace(/^www\./, "")),
  );
}

/** Stop before fetching if configured profiles would compete for one hostname, regardless of paths. */
export function requireUnambiguousVenueRoutes(routes: VenueRoute[]): void {
  const venues = new Map<string, Set<string>>();
  for (const route of normalizeVenueRoutes(routes)) {
    const host = page(route.url).hostname.replace(/^www\./, "");
    if (!venues.has(host)) venues.set(host, new Set());
    venues.get(host)?.add(route.venueId);
  }
  if ([...venues.values()].some((ids) => ids.size > 1))
    throw new Error("Ambiguous venue configuration; shared hostnames require explicit reviewed event-level routing");
}
/** Link traversal is scoped to the verified discovery host, never the destination of a cross-host redirect. */
export function isScopedDiscoveryLink(link: string, context: VenueDiscoveryContext): boolean {
  try {
    if (!context.discoveryVenueId || !context.discoveryUrl) return false;
    const target = page(link),
      seed = page(context.discoveryUrl),
      requested = page(context.requestedUrl),
      loaded = page(context.loadedUrl);
    return requested.host === loaded.host && seed.hostname === loaded.hostname && target.host === loaded.host;
  } catch {
    return false;
  }
}

/** Unknown, shared, redirected or unseeded requests never inherit an arbitrary venue. */
export function resolveVenueRouting(routes: VenueRoute[], context: VenueDiscoveryContext): VenueRoutingResult {
  const held = (status: VenueRoutingStatus): VenueRoutingResult => ({ status, venueId: null });
  try {
    const requested = page(context.requestedUrl),
      loaded = page(context.loadedUrl);
    if (requested.host !== loaded.host) return held("cross_host_redirect");
    const configured = normalizeVenueRoutes(routes);
    const candidates = new Set(
      configured
        .filter((r) => page(r.url).hostname.replace(/^www\./, "") === loaded.hostname.replace(/^www\./, ""))
        .map((r) => r.venueId),
    );
    if (!candidates.size) return held("unmatched");
    if (candidates.size !== 1) return held("ambiguous");
    if (!context.discoveryVenueId || !context.discoveryUrl) return held("seed_mismatch");
    const seed = page(context.discoveryUrl);
    if (
      seed.hostname !== loaded.hostname ||
      !candidates.has(context.discoveryVenueId) ||
      !configured.some((r) => r.venueId === context.discoveryVenueId && r.url === seed.href)
    )
      return held("seed_mismatch");
    return { status: "resolved", venueId: context.discoveryVenueId };
  } catch {
    return held("unmatched");
  }
}
