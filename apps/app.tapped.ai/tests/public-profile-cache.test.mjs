import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import ts from "typescript";
const { outputText } = ts.transpileModule(readFileSync(new URL("../src/lib/public-profile-cache.ts", import.meta.url), "utf8"), { compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 } });
const { PublicProfileCache } = await import(`data:text/javascript;base64,${Buffer.from(outputText).toString("base64")}`);

test("ID and case-insensitive username share one public entry and freshness", () => {
	let now = 1000;
	const cache = new PublicProfileCache(2, 60, 300, () => now);
	const user = { id: "a", username: "Artist" };
	cache.put(user);
	assert.equal(cache.getByUsername("ARTIST"), user);
	assert.equal(cache.getById("a"), user);
	assert.equal(cache.size, 1);
	now += 61;
	assert.equal(cache.getByUsername("Artist"), undefined);
	assert.equal(cache.getById("a", true), user);
	now += 240;
	assert.equal(cache.getById("a", true), undefined);
	assert.equal(cache.getByUsername("Artist", true), undefined);
});

test("renames and LRU eviction remove aliases without duplicate entries", () => {
	const cache = new PublicProfileCache(2);
	cache.put({ id: "a", username: "old" });
	cache.put({ id: "a", username: "new" });
	assert.equal(cache.getByUsername("old"), undefined);
	cache.put({ id: "b", username: "second" });
	cache.getById("a");
	cache.put({ id: "c", username: "third" });
	assert.equal(cache.size, 2);
	assert.equal(cache.getByUsername("second"), undefined);
	assert.equal(cache.getByUsername("new").id, "a");
});

test("a 404 invalidates both aliases and an obsolete/same-tick prefetch cannot resurrect it", () => {
	const cache = new PublicProfileCache(10, 60, 300, () => 100);
	cache.put({ id: "a", username: "artist" }, 90);
	cache.missing("a", 100);
	for (const fetchedAt of [90, 100]) cache.put({ id: "a", username: "artist" }, fetchedAt);
	assert.equal(cache.getById("a", true), null);
	assert.equal(cache.getByUsername("artist", true), null);
	cache.put({ id: "a", username: "artist" }, 101);
	assert.equal(cache.getById("a").id, "a");
	cache.put({ id: "a", username: "artist", deleted: true }, 102);
	assert.equal(cache.getByUsername("artist"), null);
});
