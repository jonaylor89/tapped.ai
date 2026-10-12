import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import test from "node:test";
import ts from "typescript";
const require = createRequire(import.meta.url);
function compile(path, imports = {}) {
	const source = readFileSync(new URL(`../src/${path}`, import.meta.url), "utf8");
	const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } });
	const exports = {};
	new Function("require", "exports", outputText)((name) => imports[name] ?? require(name), exports);
	return exports;
}
function client(t, fetch) {
	const original = globalThis.fetch; globalThis.fetch = fetch; t.after(() => { globalThis.fetch = original; });
	const db = compile("data/database.ts", {
		"@/lib/batch-users": compile("lib/batch-users.ts"),
		"@/lib/public-profile-cache": compile("lib/public-profile-cache.ts"),
		"@/lib/public-booking": compile("lib/public-booking.ts"),
		"@/lib/intent-prefetch": compile("lib/intent-prefetch.ts"),
		"./tapped_api": { tappedApiUrl: "https://api.test" },
	});
	const map = compile("data/public_map.ts", { "./database": db, "./tapped_api": { tappedApiUrl: "https://api.test" }, "@/lib/map-cache": compile("lib/map-cache.ts") });
	return { db, map };
}
const bounds = { sw: { lat: 0, lng: 0 }, ne: { lat: 4, lng: 4 } };
const venue = { id: "v", username: "Venue", timestamp: "2026-10-11T00:00:00Z", location: { lat: 1, lng: 1 }, venueInfo: { topPerformerIds: ["p", "p", "missing"] } };
const performer = { id: "p", username: "Artist", timestamp: "2026-10-11T00:00:00Z" };
const bundle = { venues: [venue], performers: [performer], genres: {}, venuesTruncated: false, performersTruncated: false };
const response = (value, status = 200) => new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json" } });

test("one map response primes ID/username/performer caches; nearby operations make no per-profile reads", async (t) => {
	const calls = [];
	const { db, map } = client(t, async (url) => { calls.push(url); return response(bundle); });
	await map.getMapData(bounds);
	assert.equal(calls.length, 1);
	assert.ok(calls[0].includes("/app/v1/public/map?"));
	assert.equal(db.getCachedUserByUsername("VENUE").id, "v");
	assert.ok(db.getCachedUserById("p").timestamp instanceof Date);
	assert.equal((await db.getUserByUsername("Artist")).id, "p");
	assert.equal((await db.getUserById("v")).id, "v");
	assert.deepEqual((await db.getUsersByIds(["p", "p", "missing"])).map((row) => row.id), ["p"]);
	await map.getMapData({ sw: { lat: 0, lng: 0 }, ne: { lat: 2, lng: 2 } });
	assert.equal(calls.length, 1);
});

test("cancellation before or after the response cannot warm obsolete profiles", async (t) => {
	const controller = new AbortController();
	const { db, map } = client(t, async () => { controller.abort(); return response(bundle); });
	await assert.rejects(map.getMapData(bounds, controller.signal), { name: "AbortError" });
	assert.equal(db.getCachedUserByUsername("Venue"), null);
	assert.equal(map.getCachedMapData(bounds), undefined);
});

test("hover and foreground details reads deduplicate; fresh 404 clears normalized aliases", async (t) => {
	let resolve;
	let calls = 0;
	const { db } = client(t, async () => { calls++; return await new Promise((r) => { resolve = r; }); });
	db.primePublicProfiles([venue]);
	const hover = db.getPublicProfileDetails("v");
	const foreground = db.getPublicProfileDetails("v", true);
	assert.equal(calls, 1);
	resolve(response({ user: venue, bookings: [], bookingCount: 0, latestReview: null }));
	assert.equal(await hover, await foreground);
	await db.getPublicProfileDetails("v"); assert.equal(calls, 1);
	const fresh = db.getPublicProfileDetails("v", true);
	resolve(response({ error: "not found" }, 404));
	assert.equal(await fresh, null);
	db.primePublicProfiles([venue], Date.now() - 1000); // old map snapshot cannot resurrect a deleted user
	assert.equal(db.getCachedUserByUsername("Venue"), null);
	assert.equal(db.getCachedProfileDetails("v"), null);
});

test("an older details response cannot undo a newer missing-profile read", async (t) => {
	let resolve;
	const { db } = client(t, async () => await new Promise((r) => { resolve = r; }));
	db.primePublicProfiles([venue]);
	const pending = db.getPublicProfileDetails("v");
	db.primeMissingPublicProfiles(["v"], Date.now() + 1);
	resolve(response({ user: venue, bookings: [], bookingCount: 0, latestReview: null }));
	assert.equal(await pending, null);
	assert.equal(db.getCachedProfileDetails("v"), null);
});

test("details warm reviewers/booking participants/top performers without retaining duplicate profile arrays", async (t) => {
	let calls = 0;
	const reviewer = { id: "r", username: "Reviewer" };
	const { db } = client(t, async () => {
		calls++;
		return response({ user: venue, bookingCount: 1, relatedUsers: [performer, reviewer],
			bookings: [{ id: "b", requesterId: "r", requesteeId: "v", status: "confirmed", timestamp: "2026-10-11T00:00:00Z", startTime: "2026-10-11T00:00:00Z", endTime: "2026-10-11T00:00:00Z", note: "unexpected", rate: 100 }],
			latestReview: { id: "review", bookerId: "r", performerId: "v", bookingId: "b", type: "performer", timestamp: "2026-10-11T00:00:00Z", overallRating: 4, overallReview: "Public" },
		});
	});
	const details = await db.getPublicProfileDetails("v");
	assert.equal((await db.getUserById("r")).username, "Reviewer");
	assert.equal((await db.getUserByUsername("Reviewer")).id, "r");
	assert.deepEqual((await db.getUsersByIds(["p", "missing"])).map((row) => row.id), ["p"]);
	assert.equal(details.relatedUsers, undefined);
	assert.ok(details.latestReview.timestamp instanceof Date);
	assert.ok(details.bookings[0].startTime instanceof Date);
	assert.equal(details.bookings[0].note, ""); assert.equal(details.bookings[0].rate, 0);
	assert.equal(calls, 1);
});
