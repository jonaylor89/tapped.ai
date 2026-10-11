import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import ts from "typescript";
const { outputText } = ts.transpileModule(readFileSync(new URL("../src/lib/map-cache.ts", import.meta.url), "utf8"), { compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 } });
const { canonicalMapBounds, bufferedMapBounds, containsBounds, ViewportCache } = await import(`data:text/javascript;base64,${Buffer.from(outputText).toString("base64")}`);
const bb = (west, south, east, north) => ({ sw: { lat: south, lng: west }, ne: { lat: north, lng: east } });
const bundle = (extra = {}) => ({ venues: [
	{ id: "inside", location: { lat: 1, lng: 1 }, venueInfo: { topPerformerIds: ["a", "a"], genres: ["rock"] } },
	{ id: "outside", location: { lat: 3, lng: 3 }, venueInfo: { topPerformerIds: ["b"], genres: ["jazz"] } },
], performers: [{ id: "a" }, { id: "b" }], genres: { rock: 1, jazz: 1 }, venuesTruncated: false, performersTruncated: false, ...extra });

test("canonical bounds round outward and buffering handles the date line and poles", () => {
	assert.deepEqual(canonicalMapBounds(bb(1.00009, 1.00009, 1.99999, 1.99999)), bb(1, 1, 2, 2));
	const wrapped = bb(170, -10, -170, 10);
	assert.ok(containsBounds(bufferedMapBounds(wrapped), wrapped));
	assert.equal(containsBounds(bb(175, -10, -175, 10), bb(-179, -5, -176, 5)), true);
	assert.equal(containsBounds(wrapped, bb(-10, -5, 10, 5)), false);
	const world = bufferedMapBounds(bb(-180, -90, 180, 90));
	assert.deepEqual(world, bb(-180, -90, 180, 90));
});

test("a fresh complete buffered result answers nearby pans with no loader or lost profiles", () => {
	let now = 1000;
	const cache = new ViewportCache(() => now);
	cache.put(bb(0, 0, 4, 4), bundle());
	const result = cache.peek(bb(0, 0, 2, 2), true);
	assert.deepEqual(result.data.venues.map((v) => v.id), ["inside"]);
	assert.deepEqual(result.data.performers.map((v) => v.id), ["a"]);
	assert.deepEqual(result.data.genres, { rock: 1 });
	assert.equal(result.fetchedAt, 1000);
	now += 30_001;
	assert.equal(cache.peek(bb(0, 0, 2, 2), true), undefined);
	assert.equal(cache.peek(bb(0, 0, 2, 2)).fetchedAt, 1000); // stale UI, refresh in background
	now += 270_000;
	assert.equal(cache.peek(bb(0, 0, 2, 2)), undefined);
});

test("capped outer bundles cannot pretend they cover a smaller area", () => {
	for (const flag of ["venuesTruncated", "performersTruncated"]) {
		const cache = new ViewportCache();
		cache.put(bb(0, 0, 4, 4), bundle({ [flag]: true }));
		assert.equal(cache.peek(bb(0, 0, 2, 2)), undefined);
		assert.ok(cache.peek(bb(0, 0, 4, 4))); // exact capped viewport still renders correctly
	}
});

test("map memory is bounded and older responses cannot replace newer snapshots", () => {
	const cache = new ViewportCache(() => 100, 2);
	cache.put(bb(0, 0, 4, 4), bundle(), 100);
	cache.put(bb(0, 0, 4, 4), bundle({ genres: { stale: 1 } }), 90);
	assert.deepEqual(cache.peek(bb(0, 0, 4, 4)).data.genres, { rock: 1, jazz: 1 });
	cache.put(bb(10, 10, 11, 11), bundle());
	cache.put(bb(20, 20, 21, 21), bundle());
	assert.equal(cache.size, 2);
	assert.equal(cache.peek(bb(0, 0, 4, 4)), undefined);
});
