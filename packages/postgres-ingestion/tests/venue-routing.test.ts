import assert from "node:assert/strict";
import test from "node:test";
import { normalizeObservation, withFormattingV2 } from "../src/observations";
import {
  isScopedDiscoveryLink,
  normalizeVenueRoutes,
  requireUnambiguousVenueRoutes,
  resolveVenueRouting,
  venueRoutesForSeeds,
} from "../src/venue-routing";

const a = { venueId: "hall", url: "https://brand.example/hall" };
const b = { venueId: "tavern", url: "https://brand.example/tavern" };
const context = {
  requestedUrl: "https://brand.example/events/show",
  loadedUrl: "https://brand.example/events/show",
  discoveryVenueId: "hall",
  discoveryUrl: a.url,
};
test("shared hosts never select the last venue, even when paths/seed IDs differ", () => {
  for (const routes of [
    [a, b],
    [b, a],
  ]) {
    assert.equal(normalizeVenueRoutes(routes).length, 2);
    assert.throws(() => requireUnambiguousVenueRoutes(routes), /Ambiguous/);
    assert.deepEqual(resolveVenueRouting(routes, context), { status: "ambiguous", venueId: null });
    assert.deepEqual(
      resolveVenueRouting(routes, {
        ...context,
        requestedUrl: b.url,
        loadedUrl: b.url,
        discoveryVenueId: "tavern",
        discoveryUrl: b.url,
      }),
      { status: "ambiguous", venueId: null },
    );
  }
});
test("unselected known profiles and www aliases still compete; unrelated domains do not block a seed", () => {
  const scoped = venueRoutesForSeeds([b, { venueId: "unrelated", url: "https://other.example/" }], [a]);
  assert.equal(scoped.length, 2);
  assert.throws(() => requireUnambiguousVenueRoutes(scoped), /Ambiguous/);
  assert.equal(resolveVenueRouting(scoped, context).venueId, null);
  assert.throws(
    () => requireUnambiguousVenueRoutes([a, { venueId: "second", url: "https://www.brand.example/" }]),
    /Ambiguous/,
  );
});
test("one venue on a verified discovery host resolves deterministically without registrable-domain guesses", () => {
  const routes = [a, a, { venueId: a.venueId, url: "https://brand.example/another-page" }];
  assert.equal(normalizeVenueRoutes(routes).length, 2);
  requireUnambiguousVenueRoutes(routes);
  assert.deepEqual(resolveVenueRouting(routes, context), { status: "resolved", venueId: "hall" });
  assert.equal(
    resolveVenueRouting(routes, {
      ...context,
      requestedUrl: "https://tickets.brand.example/show",
      loadedUrl: "https://tickets.brand.example/show",
    }).status,
    "unmatched",
  );
  assert.equal(
    resolveVenueRouting(routes, { ...context, loadedUrl: "https://elsewhere.example/show" }).status,
    "cross_host_redirect",
  );
});
test("unseeded, forged or credential-bearing URLs never inherit venue identity", () => {
  for (const c of [
    { ...context, discoveryVenueId: undefined },
    { ...context, discoveryUrl: undefined },
    { ...context, discoveryVenueId: "other" },
    { ...context, discoveryUrl: "https://brand.example/not-a-configured-seed" },
    { ...context, loadedUrl: "https://user:secret@brand.example/show" },
  ])
    assert.equal(resolveVenueRouting([a], c).venueId, null);
  assert.throws(() => normalizeVenueRoutes([{ venueId: "a", url: "https://user:secret@brand.example" }]));
});
test("link traversal cannot follow redirects off the discovery host or inherit an unrelated scope", () => {
  assert.equal(isScopedDiscoveryLink("https://brand.example/events/next", context), true);
  assert.equal(isScopedDiscoveryLink("https://other.example/events/next", context), false);
  assert.equal(isScopedDiscoveryLink("https://user:secret@brand.example/events", context), false);
  assert.equal(
    isScopedDiscoveryLink("https://other.example/events", { ...context, loadedUrl: "https://other.example/show" }),
    false,
  );
  assert.equal(isScopedDiscoveryLink(a.url, { ...context, discoveryVenueId: undefined }), false);
});
test("unresolved routing quarantines otherwise-valid extractions; archived v2 behavior is unchanged", () => {
  const input = withFormattingV2(
    {
      source: "event-crawler",
      sourceKey: "source",
      deliveryKey: "capture",
      observedAt: "2020-01-01T00:00:00Z",
      parserVersion: "routing-v2",
      data: { title: "Show", startTime: "2030-01-01T20:00:00Z", isMusicEvent: true, artists: [] },
    },
    "usd_major",
  );
  assert.deepEqual(normalizeObservation(input).errors, []);
  for (const status of ["ambiguous", "unmatched", "cross_host_redirect", "seed_mismatch"] as const)
    assert.ok(
      normalizeObservation({ ...input, venueRoutingStatus: status }).errors.includes(`venue_context_${status}`),
    );
});
