/**
 * One calendar, many venues: a `multi_venue` source maps each site's venue key to a Tapped venue, or to null when the
 * key is ignored on purpose (that venue has its own source, or is not one of ours). An unknown key is never guessed:
 * the event is held back and reported, so a new room cannot put shows on the wrong venue.
 */
import type { ExtractedEvent, Source } from "../types.js";

export interface RoutedEvents {
  byVenue: Map<string, ExtractedEvent[]>;
  ignored: number;
  /** Held-back events per unknown venue key ("" when the event names no venue). */
  unknown: Map<string, number>;
}

export function routeEvents(source: Pick<Source, "venueRoutes">, events: readonly ExtractedEvent[]): RoutedEvents {
  const routes = source.venueRoutes ?? {};
  const routed: RoutedEvents = { byVenue: new Map(), ignored: 0, unknown: new Map() };
  for (const event of events) {
    const key = event.venueKey ?? "";
    if (!key || !Object.hasOwn(routes, key)) {
      routed.unknown.set(key, (routed.unknown.get(key) ?? 0) + 1);
      continue;
    }
    const venueId = routes[key];
    if (!venueId) {
      routed.ignored++;
      continue;
    }
    routed.byVenue.set(venueId, [...(routed.byVenue.get(venueId) ?? []), event]);
  }
  return routed;
}

/** "the-camel=ignore", "the-broadberry-2=VENUE_ID" -> routes. */
export function parseRoutes(specs: readonly string[]): Record<string, string | null> {
  const routes: Record<string, string | null> = {};
  for (const spec of specs) {
    const separator = spec.indexOf("=");
    const key = spec.slice(0, separator).trim().toLowerCase();
    const target = spec.slice(separator + 1).trim();
    if (separator < 1 || !key || !target) throw new Error(`Bad --route "${spec}"; use KEY=VENUE_ID or KEY=ignore`);
    routes[key] = target === "ignore" ? null : target;
  }
  return routes;
}
